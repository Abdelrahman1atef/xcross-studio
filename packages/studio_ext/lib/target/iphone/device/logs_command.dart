import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:dart_mobile_device/target/iphone/device/pymd/syslog_entry.dart';
import 'package:studio_ext/src/target/iphone/device/device_codes.dart';
import 'package:studio_ext/src/target/iphone/device/installed_app_info.dart';
import 'package:studio_ext/src/target/iphone/device/log_filter.dart';
import 'package:studio_ext/src/target/iphone/device/log_output.dart';
import 'package:studio_ext/src/target/iphone/device/push_diagnosis.dart';
import 'package:studio_ext/target/iphone/device/device_log_backend.dart';

/// `xcross logs`: the iPhone's live log over plain usbmux (feature 010,
/// specs/010-device-logs/contracts/cli.md).
///
/// Read-only toward the device. Runs until the stream ends, `--duration`
/// passes or the user presses Ctrl+C ([interrupts]).
final class LogsCommand extends Command<void> {
  LogsCommand({
    required DeviceLogBackend backend,
    required HostFileSystemInterface fileSystem,
    required void Function(List<int>) writeBytes,
    required Stream<void> Function() interrupts,
    Duration pushCheckpoint = const Duration(seconds: 30),
  }) : _backend = backend,
       _fileSystem = fileSystem,
       _writeBytes = writeBytes,
       _interrupts = interrupts,
       _pushCheckpoint = pushCheckpoint {
    argParser
      ..addOption('udid', help: 'Device UDID (when several are connected).')
      ..addOption('app', help: 'Only this app (bundle id); follows relaunches.')
      ..addMultiOption('process', help: 'Process name or pid (repeatable).')
      ..addOption('grep', help: 'Case-insensitive regex on the message.')
      ..addOption(
        'level',
        allowed: SyslogEntry.levels,
        defaultsTo: 'debug',
        help: 'Minimum level.',
      )
      ..addOption(
        'preset',
        allowed: ['push', 'crash', 'flutter'],
        help: 'push/crash need --app.',
      )
      ..addOption('save', help: 'Also write the shown lines to this file.')
      ..addFlag('json', negatable: false, help: 'NDJSON events on stdout.')
      ..addOption('duration', help: 'Stop after this many seconds.')
      ..addFlag(
        'show-sensitive',
        negatable: false,
        help: 'Do not mask UDIDs, push tokens and emails.',
      );
  }

  final DeviceLogBackend _backend;
  final HostFileSystemInterface _fileSystem;
  final void Function(List<int>) _writeBytes;
  final Stream<void> Function() _interrupts;
  final Duration _pushCheckpoint;

  @override
  String get name => 'logs';

  @override
  String get description =>
      "Stream the iPhone's live log (USB, iOS 16 and 17+; no tunnel, no "
      'DeveloperDiskImage). Filters, push/crash/flutter presets, --json.';

  @override
  String get invocation =>
      'xcross logs [--app <bundle-id>] [--preset push|crash|flutter] '
      '[--process <name>] [--grep <regex>] [--level <level>] [--save <file>] '
      '[--json] [--duration <seconds>]';

  @override
  Future<void> run() async {
    final args = argResults!;
    final appId = args.option('app');
    final preset = switch (args.option('preset')) {
      'push' => LogPreset.push,
      'crash' => LogPreset.crash,
      'flutter' => LogPreset.flutter,
      _ => LogPreset.none,
    };
    if ((preset == LogPreset.push || preset == LogPreset.crash) &&
        appId == null) {
      usageException('--preset ${preset.name} needs --app <bundle-id>.');
    }
    final durationText = args.option('duration');
    final seconds = durationText == null ? null : int.tryParse(durationText);
    if (durationText != null && (seconds == null || seconds <= 0)) {
      usageException('--duration takes a positive number of seconds.');
    }
    final grepText = args.option('grep');
    final RegExp? grep;
    try {
      grep = grepText == null ? null : RegExp(grepText, caseSensitive: false);
    } on FormatException catch (error) {
      usageException('--grep is not a valid regex: ${error.message}');
    }
    final json = args.flag('json');
    final mask = !args.flag('show-sensitive');

    try {
      await _stream(
        udid: await _backend.ensureDevice(args.option('udid')),
        appId: appId,
        preset: preset,
        processes: args.multiOption('process'),
        grep: grep,
        minLevel: args.option('level')!,
        savePath: args.option('save'),
        json: json,
        mask: mask,
        duration: seconds == null ? null : Duration(seconds: seconds),
      );
    } on DeviceFailure catch (failure) {
      throw failure.toCliError();
    }
  }

  Future<void> _stream({
    required String udid,
    required String? appId,
    required LogPreset preset,
    required List<String> processes,
    required RegExp? grep,
    required String minLevel,
    required String? savePath,
    required bool json,
    required bool mask,
    required Duration? duration,
  }) async {
    InstalledAppInfo? app;
    if (appId != null) {
      final entry = (await _backend.installedApps(udid))[appId];
      if (entry == null) {
        throw DeviceFailure(
          DeviceCodes.appNotInstalled,
          '$appId is not installed on the iPhone.',
        );
      }
      app = InstalledAppInfo.fromAppsList(appId, entry);
    }
    final executable = app == null ? null : (app.executable ?? appId);
    final filter = LogFilter(
      appExecutable: executable,
      bundleId: appId,
      processes: processes,
      grep: grep,
      minLevel: minLevel,
      preset: preset,
    );
    final diagnosis = preset == LogPreset.push && app != null
        ? PushDiagnosis(bundleId: app.bundleId, entitlement: app.push)
        : null;

    final save = savePath == null
        ? null
        : _fileSystem.file(savePath).openSync(mode: FileMode.write);
    void emit(String text) {
      final bytes = utf8.encode(text);
      _writeBytes(bytes);
      save?.writeFromSync(bytes);
    }

    void notice(String message) => emit(
      json
          ? ndjsonLine({'v': 1, 'type': 'notice', 'message': message})
          : '$message\n',
    );

    void report(PushDiagnosis value) =>
        emit(json ? ndjsonLine(value.toJson()) : value.toHuman());

    if (executable != null) {
      notice('Waiting for $executable logs — launch the app on the iPhone.');
    }

    final session = await _backend.syslog(udid);
    final done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    var lines = 0;
    var appSeen = false;
    Timer? checkpoint;
    void scheduleCheckpoint() {
      checkpoint?.cancel();
      checkpoint = Timer(_pushCheckpoint, () {
        if (diagnosis != null) report(diagnosis);
      });
    }

    if (diagnosis != null) scheduleCheckpoint();

    final subscription = session.lines.listen(
      (line) {
        final entry = SyslogEntry.tryParse(line);
        if (entry == null) return;
        lines++;
        final fromApp = executable != null && entry.process == executable;
        if (fromApp && !appSeen) {
          appSeen = true;
          diagnosis?.sawApp();
          if (diagnosis != null) scheduleCheckpoint();
        }
        final event = filter.apply(entry, mask: mask);
        if (event == null) return;
        diagnosis?.observe(event, fromApp: fromApp);
        emit(json ? ndjsonLine(event.toJson()) : '${event.toHumanLine()}\n');
      },
      onDone: finish,
      onError: (Object _) => finish(),
    );
    final interrupt = _interrupts().listen((_) => finish());
    final timer = duration == null ? null : Timer(duration, finish);

    try {
      await done.future;
    } finally {
      timer?.cancel();
      checkpoint?.cancel();
      await interrupt.cancel();
      await subscription.cancel();
      await session.stop();
    }

    if (lines == 0 && session.errors.isNotEmpty) {
      save?.closeSync();
      final detail = session.errors.join('\n');
      if (RegExp(
        'PasswordProtected|PairingDialogResponsePending|NotPaired|'
        'InvalidHostID',
      ).hasMatch(detail)) {
        throw DeviceFailure(
          DeviceCodes.notTrusted,
          'The iPhone is locked or does not trust this computer.',
        );
      }
      throw DeviceFailure(
        DeviceCodes.notFound,
        'The device log stream stopped: ${session.errors.last}',
      );
    }
    if (diagnosis != null) report(diagnosis);
    if (executable != null && !appSeen && !json) {
      emit(
        'No lines from $executable. If the app ran, it may log nothing in '
        'release builds; try a profile or debug build.\n',
      );
    }
    save?.closeSync();
  }
}
