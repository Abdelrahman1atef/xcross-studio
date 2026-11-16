import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/pods/pod_report.dart';

/// `xcross pods`: inspects CocoaPods pod conversion status and reports.
final class PodsCommand extends Command<void> {
  PodsCommand({
    required HostFileSystemInterface fileSystem,
    required p.Context paths,
    required void Function(String) write,
    String? home,
    String? projectDirectory,
  }) {
    addSubcommand(
      PodsReportCommand(
        fileSystem: fileSystem,
        paths: paths,
        write: write,
        home: home,
        projectDirectory: projectDirectory,
      ),
    );
  }

  @override
  String get name => 'pods';

  @override
  String get description =>
      'Inspect and report CocoaPods pods converted for Swift Package Manager.';
}

/// `xcross pods report [<Pod>] [--json]`
final class PodsReportCommand extends Command<void> {
  PodsReportCommand({
    required HostFileSystemInterface fileSystem,
    required p.Context paths,
    required this.write,
    this.home,
    this.projectDirectory,
  }) : _fileSystem = fileSystem,
       _paths = paths {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Output the redacted report in JSON format.',
    );
    argParser.addOption(
      'project',
      abbr: 'p',
      help: 'Flutter project root directory.',
    );
    argParser.addOption('file', help: 'Path to pods-report.json.');
  }

  final HostFileSystemInterface _fileSystem;
  final p.Context _paths;
  final void Function(String) write;
  final String? home;
  final String? projectDirectory;

  @override
  String get name => 'report';

  @override
  String get description =>
      'Print the redacted report of left-out pods from the last build.';

  @override
  void run() {
    final targetPod = argResults?.rest.isNotEmpty == true
        ? argResults!.rest.first
        : null;
    final jsonMode = argResults?['json'] as bool? ?? false;
    final customFile = argResults?['file'] as String?;
    final projectDir =
        argResults?['project'] as String? ?? projectDirectory ?? _paths.current;

    final reportPath =
        customFile ??
        _paths.join(projectDir, PodsReportFile.defaultRelativePath);

    final reportFile = _fileSystem.file(reportPath);
    const handler = PodsReportFile();
    final reports = handler.load(reportFile);

    final filtered = targetPod == null
        ? reports
        : reports
              .where((r) => r.pod.toLowerCase() == targetPod.toLowerCase())
              .toList();

    final redacted = [
      for (final r in filtered) r.redact(homeDir: home, projectDir: projectDir),
    ];

    if (jsonMode) {
      write(
        const JsonEncoder.withIndent(
          '  ',
        ).convert([for (final r in redacted) r.toJson()]),
      );
      return;
    }

    if (redacted.isEmpty) {
      if (targetPod != null) {
        write('No pod report found for "$targetPod".');
      } else {
        write('No pod reports found in $reportPath.');
      }
      return;
    }

    for (var i = 0; i < redacted.length; i++) {
      if (i > 0) write('');
      write(redacted[i].formatWarning());
    }
  }
}
