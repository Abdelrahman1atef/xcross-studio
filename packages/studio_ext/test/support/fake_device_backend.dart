import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mobile_device/shared/device/models/device.dart';
import 'package:studio_ext/target/iphone/device/device_log_backend.dart';

/// One `pymobiledevice3 syslog live --format json` line.
String syslogLine({
  required String process,
  required String message,
  int pid = 100,
  String level = 'NOTICE',
  String time = '2026-11-01T12:00:00.123456',
  String? subsystem,
}) => jsonEncode({
  'pid': pid,
  'procid': pid,
  'thread_id': 1,
  'timestamp': time,
  'level': level,
  'image_name': '/usr/lib/libsystem.dylib',
  'filename': process.startsWith('/') ? process : '/private/var/apps/$process',
  'message': message,
  'label': {'subsystem': subsystem, 'category': null},
});

/// An `apps list` entry.
Map<String, Object?> appEntry({
  required String executable,
  Map<String, Object?> entitlements = const {},
  String signer = 'Apple Development: Planted Person (ABCDE12345)',
  String version = '1.2.3',
  String build = '45',
}) => {
  'CFBundleExecutable': executable,
  'CFBundleDisplayName': 'Fixture',
  'CFBundleShortVersionString': version,
  'CFBundleVersion': build,
  'SignerIdentity': signer,
  'Entitlements': entitlements,
};

/// In-memory [DeviceLogBackend] for command tests.
final class FakeDeviceBackend implements DeviceLogBackend {
  FakeDeviceBackend({
    this.lines = const [],
    this.apps = const {},
    this.crashes = const [],
    this.crashFiles = const {},
    this.ensureError,
    this.keepOpen = false,
    this.streamErrors = const [],
    this.devices = const [],
  });

  /// What [usbDevices] returns.
  final List<Device> devices;

  final List<String> lines;
  final Map<String, Map<String, Object?>> apps;
  final List<String> crashes;
  final Map<String, String> crashFiles;
  final Exception? ensureError;

  /// Keep the stream open after [lines] (ends only by stop/interrupt/timer).
  final bool keepOpen;
  final List<String> streamErrors;
  final calls = <String>[];
  FakeSyslogSession? session;

  @override
  Future<String> ensureDevice(String? udid) async {
    calls.add('ensure:${udid ?? '-'}');
    if (ensureError case final error?) throw error;
    return '00008020-001A2B3C4D5E6F70';
  }

  @override
  Future<List<Device>> usbDevices() async {
    calls.add('devices');
    if (ensureError case final error?) throw error;
    return devices;
  }

  @override
  Future<SyslogSession> syslog(String udid) async {
    calls.add('syslog');
    return session = FakeSyslogSession(
      lines,
      keepOpen: keepOpen,
      errors: streamErrors,
    );
  }

  @override
  Future<Map<String, Map<String, Object?>>> installedApps(String udid) async {
    calls.add('apps');
    return apps;
  }

  @override
  Future<List<String>> crashNames(String udid) async {
    calls.add('crash ls');
    return crashes;
  }

  @override
  Future<void> pullCrashes(
    String udid,
    List<String> names,
    String directory,
  ) async {
    calls.add('crash pull ${names.join(',')}');
    for (final name in names) {
      final text = crashFiles[name];
      if (text == null) continue;
      File('$directory/$name')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);
    }
  }
}

/// A syslog stream replaying fixed lines.
final class FakeSyslogSession implements SyslogSession {
  FakeSyslogSession(
    List<String> lines, {
    required bool keepOpen,
    required this.errors,
  }) {
    for (final line in lines) {
      _controller.add(line);
    }
    if (!keepOpen) unawaited(_controller.close());
  }

  final _controller = StreamController<String>();
  bool stopped = false;

  @override
  final List<String> errors;

  @override
  Stream<String> get lines => _controller.stream;

  @override
  Future<void> stop() async {
    stopped = true;
    if (!_controller.isClosed) await _controller.close();
  }
}
