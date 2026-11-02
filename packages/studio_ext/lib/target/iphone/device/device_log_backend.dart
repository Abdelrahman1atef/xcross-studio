import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mobile_device/shared/device/models/device.dart';
import 'package:dart_mobile_device/shared/errors/errors.dart';
import 'package:dart_mobile_device/target/iphone/device/pymd/pymd.dart';
import 'package:dart_mobile_device/target/iphone/device/pymd/pymd_devices.dart';

import 'package:studio_ext/src/target/iphone/device/device_codes.dart';

/// A running `syslog live` stream.
abstract interface class SyslogSession {
  /// Raw JSON lines, one per log entry.
  Stream<String> get lines;

  /// The last stderr lines (for a failed start).
  List<String> get errors;

  Future<void> stop();
}

/// Everything the device commands need from the device (research D3).
abstract interface class DeviceLogBackend {
  /// Checks the host service, resolves one USB device and returns its UDID.
  Future<String> ensureDevice(String? udid);

  /// Checks the host service and lists the USB devices (feature 008).
  Future<List<Device>> usbDevices();

  Future<SyslogSession> syslog(String udid);

  /// `apps list --type User`: bundle id → app properties.
  Future<Map<String, Map<String, Object?>>> installedApps(String udid);

  /// Crash report paths as listed by `crash ls` (top level).
  Future<List<String>> crashNames(String udid);

  /// Copies the reports at [paths] (device paths such as `/X.ips` or
  /// `/Retired/X.ips`) into [directory], keeping their folders.
  Future<void> pullCrashes(String udid, List<String> paths, String directory);
}

/// [DeviceLogBackend] over pymobiledevice3: plain usbmux, no tunnel, no DDI.
final class PymdDeviceLogBackend implements DeviceLogBackend {
  PymdDeviceLogBackend(this.pymd);

  final Pymd pymd;

  static final _trust = RegExp(
    'PasswordProtected|PairingDialogResponsePending|NotPaired|InvalidHostID|'
    'UserDeniedPairing',
  );

  Map<String, String> get _environment => {
    ...pymd.usbmuxEnvironment(),
    'PYTHONUNBUFFERED': '1',
    'PYTHONIOENCODING': 'utf-8',
  };

  @override
  Future<String> ensureDevice(String? udid) async {
    final devices = await usbDevices();
    if (udid != null) {
      final wanted = PymdDevices.normalizeUdid(udid);
      for (final device in devices) {
        if (PymdDevices.normalizeUdid(device.udid) == wanted) {
          return device.udid;
        }
      }
      throw DeviceFailure(
        DeviceCodes.notFound,
        'No USB device matches the given --udid.',
      );
    }
    if (devices.isEmpty) {
      throw DeviceFailure(
        DeviceCodes.notFound,
        'No iPhone is connected by USB.',
      );
    }
    if (devices.length > 1) {
      throw DeviceFailure(
        DeviceCodes.selectRequired,
        'Several devices are connected: '
        '${[for (final d in devices) d.name].join(', ')}.',
      );
    }
    return devices.single.udid;
  }

  @override
  Future<List<Device>> usbDevices() async {
    final problem = await pymd.hostPolicy.deviceServiceProblem(
      pymd.resolvedUsbmuxAddress(),
    );
    if (problem != null) {
      final end = problem.indexOf('. ');
      throw DeviceFailure(
        DeviceCodes.hostServiceUnavailable,
        end < 0 ? problem : problem.substring(0, end + 1),
        hint: end < 0 ? null : problem.substring(end + 2),
      );
    }
    // Listed directly (not through the interactive resolver): it prints no
    // progress to stdout, which would corrupt --json, and never prompts.
    try {
      return await PymdDevices(pymd).devices(mode: DeviceSearchMode.usb);
    } on TunnelError catch (error) {
      throw _trustOr(error.message);
    }
  }

  Exception _trustOr(String message) => _trust.hasMatch(message)
      ? DeviceFailure(
          DeviceCodes.notTrusted,
          'The iPhone is locked or does not trust this computer.',
        )
      : TunnelError(message);

  Future<List<String>> _command(List<String> args, String udid) async {
    final invocation = await pymd.resolve();
    return [...invocation.prefixArgs, ...args, '--udid', udid];
  }

  @override
  Future<SyslogSession> syslog(String udid) async {
    final invocation = await pymd.resolve();
    final process = await pymd.runner.start(
      invocation.executable,
      await _command(['syslog', 'live', '--format', 'json'], udid),
      environment: _environment,
    );
    return PymdSyslogSession(process, pymd.runner.killTree);
  }

  Future<String> _run(List<String> args, String udid) async {
    final invocation = await pymd.resolve();
    final result = await pymd.runner.run(
      invocation.executable,
      await _command(args, udid),
      environment: _environment,
    );
    if (result.exitCode != 0) {
      final detail = result.stderr.isNotEmpty ? result.stderr : result.stdout;
      throw _trustOr('pymobiledevice3 ${args.join(' ')} failed: $detail');
    }
    return result.stdout;
  }

  @override
  Future<Map<String, Map<String, Object?>>> installedApps(String udid) async {
    final json = jsonDecode(
      await _run(['apps', 'list', '--type', 'User'], udid),
    );
    if (json is! Map) return const {};
    return {
      for (final MapEntry(:key, :value) in json.entries)
        if (value is Map) '$key': value.cast<String, Object?>(),
    };
  }

  // Depth 2: iOS moves a report into /Retired once it has been copied off
  // (our own `crashes list` copies the newest ones), and a top-level listing
  // would then lose it (found on the iPhone X, 2026-11-02).
  @override
  Future<List<String>> crashNames(String udid) async => [
    for (final line in const LineSplitter().convert(
      await _run(['crash', 'ls', '--depth', '2'], udid),
    ))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  @override
  Future<void> pullCrashes(
    String udid,
    List<String> paths,
    String directory,
  ) async {
    // `crash pull` does not descend into /Retired from `/`, so each folder is
    // pulled on its own (found on the iPhone X, 2026-11-02).
    final byFolder = <String, List<String>>{};
    for (final path in paths) {
      final cut = path.lastIndexOf('/');
      final folder = cut <= 0 ? '/' : path.substring(0, cut);
      byFolder.putIfAbsent(folder, () => []).add(path.substring(cut + 1));
    }
    for (final MapEntry(key: folder, value: names) in byFolder.entries) {
      await _run([
        'crash',
        'pull',
        directory,
        folder,
        '--match',
        '^(${[for (final name in names) RegExp.escape(name)].join('|')})\$',
      ], udid);
    }
  }
}

/// A `syslog live` child process.
final class PymdSyslogSession implements SyslogSession {
  PymdSyslogSession(this._process, this._kill) {
    _process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          errors.add(line);
          if (errors.length > 20) errors.removeAt(0);
        });
  }

  final Process _process;
  final Future<void> Function(Process) _kill;

  @override
  final List<String> errors = [];

  @override
  Stream<String> get lines => _process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter());

  @override
  Future<void> stop() async {
    try {
      await _kill(_process).timeout(const Duration(seconds: 3));
    } on Object {
      _process.kill();
    }
  }
}
