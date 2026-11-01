import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/src/target/iphone/device/crash_reports.dart';
import 'package:studio_ext/src/target/iphone/device/crash_tools.dart';
import 'package:studio_ext/src/target/iphone/device/device_codes.dart';
import 'package:studio_ext/src/target/iphone/device/log_output.dart';
import 'package:studio_ext/target/iphone/device/device_log_backend.dart';

/// `xcross crashes list|pull` (feature 010).
final class CrashesCommand extends Command<void> {
  CrashesCommand({
    required DeviceLogBackend backend,
    required HostFileSystemInterface fileSystem,
    required p.Context paths,
    required String cacheRoot,
    required void Function(List<int>) writeBytes,
  }) {
    final shared = CrashTools(
      backend: backend,
      fileSystem: fileSystem,
      paths: paths,
      cacheRoot: cacheRoot,
      writeBytes: writeBytes,
    );
    addSubcommand(CrashesListCommand(shared));
    addSubcommand(CrashesPullCommand(shared));
  }

  @override
  String get name => 'crashes';

  @override
  String get description => 'List and pull crash reports from the iPhone.';
}

/// `xcross crashes list [--app <bundle-id>] [--json]`.
final class CrashesListCommand extends Command<void> {
  CrashesListCommand(this._tools) {
    argParser
      ..addOption('udid', help: 'Device UDID (when several are connected).')
      ..addOption('app', help: "Only this app's crashes (bundle id).")
      ..addFlag('json', negatable: false, help: 'NDJSON crash events.');
  }

  final CrashTools _tools;
  static const _detailLimit = 20;

  @override
  String get name => 'list';

  @override
  String get description => 'Crash reports on the device, newest first.';

  @override
  Future<void> run() async {
    final args = argResults!;
    try {
      final udid = await _tools.backend.ensureDevice(args.option('udid'));
      final reports = await _tools.reports(udid, args.option('app'));
      final detailed = reports.take(_detailLimit).toList();
      final summaries = detailed.isEmpty
          ? const <String, CrashReportSummary>{}
          : await _tools.pullAndRead(
              udid,
              detailed,
              _tools.paths.join(_tools.cacheRoot, 'xcross-crash-cache'),
            );
      if (reports.isEmpty && !args.flag('json')) {
        _tools.write('No crash reports.\n');
      }
      for (final report in reports) {
        final type = summaries[report.name]?.exceptionType;
        _tools.write(
          args.flag('json')
              ? ndjsonLine({
                  'v': 1,
                  'type': 'crash',
                  'name': report.name,
                  'process': report.process,
                  'time': report.time,
                  'exceptionType': type,
                })
              : '${report.time.replaceFirst('T', ' ')}  ${report.process}  '
                    '${type ?? '-'}  ${report.name}\n',
        );
      }
    } on DeviceFailure catch (failure) {
      throw failure.toCliError();
    }
  }
}

/// `xcross crashes pull (<name> | --latest) [--app] [--out <dir>]`.
final class CrashesPullCommand extends Command<void> {
  CrashesPullCommand(this._tools) {
    argParser
      ..addOption('udid', help: 'Device UDID (when several are connected).')
      ..addOption('app', help: 'Limit --latest to this app (bundle id).')
      ..addFlag('latest', negatable: false, help: 'The newest report.')
      ..addOption('out', defaultsTo: 'crash-reports', help: 'Directory.');
  }

  final CrashTools _tools;

  static const _shareNote =
      'Note: the saved report can contain device identifiers; mask them '
      'before sharing it publicly.';

  @override
  String get name => 'pull';

  @override
  String get description =>
      'Save a crash report and print its exception summary.';

  @override
  String get invocation =>
      'xcross crashes pull (<name> | --latest) [--app <bundle-id>] '
      '[--out <dir>]';

  @override
  Future<void> run() async {
    final args = argResults!;
    final latest = args.flag('latest');
    if (latest == args.rest.isNotEmpty || args.rest.length > 1) {
      usageException('Pass one report name, or --latest.');
    }
    try {
      final udid = await _tools.backend.ensureDevice(args.option('udid'));
      final reports = await _tools.reports(udid, args.option('app'));
      final wanted = latest ? null : args.rest.single.split('/').last;
      final report = latest
          ? (reports.isEmpty ? null : reports.first)
          : reports.where((r) => r.name == wanted).firstOrNull;
      if (report == null) {
        throw DeviceFailure(
          DeviceCodes.crashNotFound,
          latest ? 'No crash report found.' : '$wanted is not on the device.',
        );
      }
      final out = args.option('out')!;
      final summary = (await _tools.pullAndRead(udid, [
        report,
      ], out))[report.name];
      final exceptionLine =
          'exception: ${summary?.exceptionType ?? 'unknown'}'
          '${summary?.signal == null ? '' : ' (${summary!.signal})'}';
      final lines = <String>[
        'Saved ${_tools.paths.join(out, report.name)}',
        '${report.process} crashed at ${report.time.replaceFirst('T', ' ')}',
        exceptionLine,
        if (summary != null && summary.frames.isNotEmpty) ...[
          'crashed thread:',
          for (final frame in summary.frames) '  $frame',
        ],
        _shareNote,
      ];
      _tools.write('${lines.join('\n')}\n');
    } on DeviceFailure catch (failure) {
      throw failure.toCliError();
    }
  }
}
