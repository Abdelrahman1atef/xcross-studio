// studio: 022 — `xcross release gate` and `xcross release ci`
// (specs/022-studio-release-flow, AC-022-5, AC-022-6).
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/appstore/command_exit.dart';
import 'package:studio_ext/src/shared/release/ci_template.dart';

/// Runs a tool in a folder and returns its exit code and combined output.
typedef RunTool =
    Future<({int exitCode, String output})> Function(
      String executable,
      List<String> arguments, {
      required String workingDirectory,
    });

/// `xcross release gate [--json] [--skip-tests]`: `flutter analyze` and
/// `flutter test` as the release's quality gate.
final class ReleaseGateCommand extends Command<void> {
  ReleaseGateCommand({
    required Future<String> Function(String projectRoot) flutter,
    required RunTool runTool,
    required HostFileSystemInterface fileSystem,
    required String Function() currentDirectory,
    required void Function(String text) write,
  }) : _flutter = flutter,
       _runTool = runTool,
       _fileSystem = fileSystem,
       _cwd = currentDirectory,
       _write = write {
    argParser
      ..addFlag('json', negatable: false, help: 'Print one JSON object.')
      ..addFlag(
        'skip-tests',
        negatable: false,
        help: 'Run flutter analyze only.',
      );
  }

  final Future<String> Function(String projectRoot) _flutter;
  final RunTool _runTool;
  final HostFileSystemInterface _fileSystem;
  final String Function() _cwd;
  final void Function(String text) _write;

  @override
  String get name => 'gate';

  @override
  String get description =>
      'Run flutter analyze and flutter test in the project (the release '
      'quality gate).';

  /// Lines of output kept per step.
  static const tailLines = 15;

  @override
  Future<void> run() async {
    final root = _cwd();
    if (!_fileSystem.file(p.join(root, 'pubspec.yaml')).existsSync()) {
      throw const CommandExit(
        'No pubspec.yaml here: run `xcross release gate` in the Flutter '
        'project.',
      );
    }
    final json = argResults!.flag('json');
    final flutter = await _flutter(root);
    final steps = <Map<String, Object?>>[];
    for (final (name, arguments) in [
      ('flutter analyze', ['analyze']),
      if (!argResults!.flag('skip-tests')) ('flutter test', ['test']),
    ]) {
      if (!json) _write('Running $name…\n');
      final result = await _runTool(flutter, arguments, workingDirectory: root);
      final lines = const LineSplitter()
          .convert(result.output)
          .where((line) => line.trim().isNotEmpty)
          .toList();
      final tail = lines.length > tailLines
          ? lines.sublist(lines.length - tailLines)
          : lines;
      final passed = result.exitCode == 0;
      steps.add({
        'name': name,
        'passed': passed,
        'exitCode': result.exitCode,
        'tail': tail,
      });
      if (!json) {
        _write('${passed ? '✓' : '✗'} $name\n');
        if (!passed) _write('${tail.map((l) => '  $l').join('\n')}\n');
      }
    }
    final failed = steps.where((step) => step['passed'] != true).toList();
    if (json) {
      _write(
        '${jsonEncode({'v': 1, 'type': 'release_gate', 'steps': steps})}\n',
      );
    }
    if (failed.isNotEmpty) {
      throw CommandExit(
        'The quality gate failed: ${failed.map((s) => s['name']).join(', ')}.',
      );
    }
  }
}

/// `xcross release ci [--output <path>] [--force]`: writes the GitHub Actions
/// workflow that releases from ubuntu-latest.
final class ReleaseCiCommand extends Command<void> {
  ReleaseCiCommand({
    required HostFileSystemInterface fileSystem,
    required String Function() currentDirectory,
    required void Function(String text) write,
  }) : _fileSystem = fileSystem,
       _cwd = currentDirectory,
       _write = write {
    argParser
      ..addOption(
        'output',
        defaultsTo: CiTemplate.defaultPath,
        help: 'Where to write the workflow, relative to the project.',
      )
      ..addFlag('force', negatable: false, help: 'Replace an existing file.');
  }

  final HostFileSystemInterface _fileSystem;
  final String Function() _cwd;
  final void Function(String text) _write;

  @override
  String get name => 'ci';

  @override
  String get description =>
      'Write a GitHub Actions workflow that builds, signs and uploads the app '
      'from ubuntu-latest.';

  @override
  Future<void> run() async {
    final output = argResults!.option('output') ?? CiTemplate.defaultPath;
    final path = p.isAbsolute(output)
        ? output
        : p.joinAll([_cwd(), ...output.split('/')]);
    final file = _fileSystem.file(path);
    if (file.existsSync() && !argResults!.flag('force')) {
      throw CommandExit('$path already exists; pass --force to replace it.');
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(CiTemplate.githubTestflight.trimLeft());
    _write(
      'Wrote $path\n'
      'Add the secrets it lists (App Store Connect key, CERTIFICATE_PRIVATE_KEY, '
      'XCODE_XIP_URL) under Settings → Secrets and variables → Actions.\n',
    );
  }
}
