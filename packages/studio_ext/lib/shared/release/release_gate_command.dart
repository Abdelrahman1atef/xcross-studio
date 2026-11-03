// studio: 022 — `xcross release gate` and `xcross release ci`
// (specs/022-studio-release-flow, AC-022-5, AC-022-6).
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/appstore/command_exit.dart';
import 'package:studio_ext/src/shared/release/analyzer_output.dart';
import 'package:studio_ext/src/shared/release/ci_template.dart';

/// Runs a tool in a folder and returns its exit code and combined output.
typedef RunTool =
    Future<({int exitCode, String output})> Function(
      String executable,
      List<String> arguments, {
      required String workingDirectory,
    });

/// `xcross release gate [--json] [--skip-tests] [--fatal-infos]`: `flutter
/// analyze` and `flutter test` as the release's quality gate. Analyzer errors
/// and warnings fail it; infos (a deprecation, a style lint) are reported and
/// only fail it with `--fatal-infos`.
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
      )
      ..addFlag(
        'fatal-infos',
        negatable: false,
        help:
            'Fail on info-level analyzer issues too (errors and warnings '
            'always fail).',
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
    final fatalInfos = argResults!.flag('fatal-infos');
    final steps = <Map<String, Object?>>[];
    for (final (name, arguments) in [
      (
        'flutter analyze',
        ['analyze', if (fatalInfos) '--fatal-infos' else '--no-fatal-infos'],
      ),
      if (!argResults!.flag('skip-tests')) ('flutter test', ['test']),
    ]) {
      if (!json) _write('Running $name…\n');
      final result = await _runTool(flutter, arguments, workingDirectory: root);
      final lines = AnalyzerOutput.withoutPubNoise(
        const LineSplitter()
            .convert(result.output)
            .where((line) => line.trim().isNotEmpty),
      );
      final tail = lines.length > tailLines
          ? lines.sublist(lines.length - tailLines)
          : lines;
      final issues = arguments.first == 'analyze'
          ? AnalyzerOutput.issues(lines)
          : const <AnalyzerIssue>[];
      final passed = result.exitCode == 0;
      int count(String severity) =>
          issues.where((issue) => issue.severity == severity).length;
      steps.add({
        'name': name,
        'passed': passed,
        'exitCode': result.exitCode,
        'tail': tail,
        if (arguments.first == 'analyze') ...{
          'issues': [for (final issue in issues) issue.toJson()],
          'errors': count('error'),
          'warnings': count('warning'),
          'infos': count('info'),
        },
      });
      if (!json) {
        final summary = issues.isEmpty ? '' : ' (${_count(issues)})';
        _write('${passed ? '✓' : '✗'} $name$summary\n');
        // The issues when the analyzer listed them, else the last lines.
        if (issues.isNotEmpty) {
          _write('${issues.map((i) => '  ${i.render()}').join('\n')}\n');
          if (passed) {
            _write(
              '  Infos do not fail the gate; pass --fatal-infos to make '
              'them.\n',
            );
          }
        } else if (!passed) {
          _write('${tail.map((l) => '  $l').join('\n')}\n');
        }
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

  // `1 error, 2 infos`.
  static String _count(List<AnalyzerIssue> issues) => [
    for (final severity in const ['error', 'warning', 'info'])
      if (issues.where((i) => i.severity == severity).length case final n
          when n > 0)
        '$n $severity${n == 1 ? '' : 's'}',
  ].join(', ');
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
