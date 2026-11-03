// studio: 018 — `xcross release check`: what App Store Connect would reject,
// found before an upload (specs/018-app-store-build).
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/inspect/inspect_failure.dart';
import 'package:studio_ext/src/shared/inspect/inspect_source.dart';
import 'package:studio_ext/src/shared/release/release_checks.dart';

/// `xcross release …`: steps of an App Store release.
final class ReleaseCommand extends Command<void> {
  ReleaseCommand({
    required HostFileSystemInterface fileSystem,
    required p.Context paths,
    required String Function() currentDirectory,
    required void Function(String) write,
    DateTime Function()? now,
  }) {
    addSubcommand(
      ReleaseCheckCommand(
        fileSystem: fileSystem,
        paths: paths,
        currentDirectory: currentDirectory,
        write: write,
        now: now,
      ),
    );
  }

  @override
  String get name => 'release';

  @override
  String get description => 'Prepare an App Store release.';
}

/// `xcross release check [<ipa|app>] [--json] [--project <dir>]`.
final class ReleaseCheckCommand extends Command<void> {
  ReleaseCheckCommand({
    required HostFileSystemInterface fileSystem,
    required p.Context paths,
    required String Function() currentDirectory,
    required void Function(String) write,
    DateTime Function()? now,
  }) : _fileSystem = fileSystem,
       _paths = paths,
       _currentDirectory = currentDirectory,
       _write = write,
       _now = now ?? DateTime.now {
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print one JSON object instead of the report.',
      )
      ..addOption(
        'project',
        valueHelp: 'dir',
        help:
            'The Flutter project the app was built from (default: the '
            'current folder when it has a pubspec.yaml).',
      );
  }

  final HostFileSystemInterface _fileSystem;
  final p.Context _paths;
  final String Function() _currentDirectory;
  final void Function(String) _write;
  final DateTime Function() _now;

  @override
  String get name => 'check';

  @override
  String get description =>
      "Check a built .ipa or .app against App Store Connect's rules: "
      'signing, SDK, permissions, privacy manifests, icon, launch screen.';

  @override
  String get invocation =>
      'xcross release check [<ipa|app>] [--json] [--project <dir>]';

  @override
  Future<void> run() async {
    final results = argResults!;
    if (results.rest.length > 1) {
      usageException('Pass at most one .ipa file or .app directory.');
    }
    final cwd = _currentDirectory();
    final input = results.rest.isEmpty ? _newestIpa(cwd) : results.rest.single;
    if (input == null) {
      throw CliError(
        '[release.no_input] No .ipa under build/xcross-ios/ in $cwd.\n'
        'hint: Build one with `xcross flutter build --release --ipa '
        '--export-method app-store`, or pass a path.',
      );
    }
    final project = _project(results.option('project'), cwd);
    final json = results.flag('json');
    InspectSource? source;
    final ReleaseReport report;
    try {
      source = InspectSource.open(_fileSystem, input);
      report = runReleaseChecks(source, project: project, now: _now());
    } on InspectFailure catch (failure) {
      throw CliError(
        '[${failure.code}] ${failure.message}\nhint: ${failure.hint}',
      );
    } finally {
      source?.close();
    }
    _write(json ? '${jsonEncode(report.toJson())}\n' : render(report));
    if (report.errors > 0) {
      throw CliError(
        '[release.check_failed] ${report.errors} '
        'error${report.errors == 1 ? '' : 's'} would stop the App Store '
        'upload.\nhint: Fix the errors above and build again.',
      );
    }
  }

  ReleaseProject? _project(String? option, String cwd) {
    final root = option ?? cwd;
    if (option == null &&
        !_fileSystem.file(_paths.join(root, 'pubspec.yaml')).existsSync()) {
      return null;
    }
    if (!_fileSystem.directory(root).existsSync()) {
      usageException('--project $root does not exist.');
    }
    return ReleaseProject(fileSystem: _fileSystem, paths: _paths, root: root);
  }

  /// The newest `.ipa` in `build/xcross-ios/ipa/`, else `build/xcross-ios/`.
  String? _newestIpa(String cwd) {
    for (final parts in const [
      ['build', 'xcross-ios', 'ipa'],
      ['build', 'xcross-ios'],
    ]) {
      final directory = _fileSystem.directory(_paths.joinAll([cwd, ...parts]));
      if (!directory.existsSync()) continue;
      final ipas = [
        for (final entity in directory.listSync())
          if (entity is File && entity.path.toLowerCase().endsWith('.ipa'))
            entity,
      ]..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      if (ipas.isNotEmpty) return ipas.first.path;
    }
    return null;
  }

  /// The text report: configuration, then issues (errors first).
  static String render(ReleaseReport report) {
    final out = StringBuffer('Release check: ${report.input}\n');
    final configuration = report.configuration;
    void line(String label, Object? value) {
      if (value == null) return;
      final text = value is List ? value.join(', ') : '$value';
      if (text.isEmpty) return;
      out.writeln('  ${label.padRight(14)}$text');
    }

    line('Bundle ID', configuration['bundleId']);
    line('Name', configuration['displayName'] ?? configuration['name']);
    line(
      'Version',
      configuration['version'] == null
          ? null
          : '${configuration['version']} (${configuration['build']})',
    );
    line('Minimum iOS', configuration['minimumOS']);
    line('Devices', configuration['devices']);
    line('Orientations', configuration['orientations']);
    line('iOS SDK', configuration['sdk']);
    line('Entitlements', configuration['entitlements']);
    if (configuration['profile'] case {
      'kind': final Object? kind,
      'teamId': final Object? team,
    }) {
      line('Profile', '$kind (team $team)');
    }
    line('Encryption', configuration['usesNonExemptEncryption']);
    out.writeln();
    for (final issue in report.issues) {
      out.writeln('${issue.severity.name} [${issue.code}] ${issue.message}');
      if (issue.hint case final hint?) out.writeln('  hint: $hint');
    }
    out.writeln(
      report.errors == 0 && report.warnings == 0
          ? 'No problems found.'
          : '${report.errors} error${report.errors == 1 ? '' : 's'}, '
                '${report.warnings} warning'
                '${report.warnings == 1 ? '' : 's'}.',
    );
    return out.toString();
  }
}
