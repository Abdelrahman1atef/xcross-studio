// studio: 048 — touch for the live iPhone screen when the picture has no
// touch of its own (QuickTime capture): WebDriverAgent ("the touch helper")
// runs on the phone and the screen helper sends it taps and swipes.
import 'dart:async';
import 'dart:convert';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:dart_mobile_device/target/iphone/device/pymd/pymd.dart';
import 'package:studio_ext/src/target/iphone/device/screen_touch_link.dart';

/// Why touch could not start.
final class ScreenTouchUnavailable implements Exception {
  const ScreenTouchUnavailable(this.reason, this.message);

  /// `not_installed` (the touch helper is not on the iPhone yet) or `error`.
  final String reason;
  final String message;

  @override
  String toString() => message;
}

/// A running touch helper: the local address touches go to.
abstract interface class ScreenTouchLink {
  /// `http://127.0.0.1:<port>`, forwarded to the touch helper on the iPhone.
  String get url;

  /// Completes when the touch helper stops by itself, with a short reason.
  Future<String> get ended;

  /// Stops the touch helper.
  Future<void> close();
}

/// Starts the touch helper on an iPhone.
abstract interface class ScreenTouch {
  /// Throws [ScreenTouchUnavailable] when touch cannot start.
  Future<ScreenTouchLink> start(String udid);
}

/// A long-running tool process: its output lines, its end, and a way to stop it.
abstract interface class TouchProcess {
  /// stdout and stderr lines.
  Stream<String> get output;
  Future<int> get exitCode;
  Future<void> kill();
}

/// The pymobiledevice3 commands touch needs.
abstract interface class ScreenTouchTools {
  /// Runs pymobiledevice3 [args] and returns its stdout; throws when it fails.
  Future<String> run(List<String> args, {required Duration timeout});

  /// Starts a long-running pymobiledevice3 command.
  Future<TouchProcess> start(List<String> args);

  /// A free port on 127.0.0.1.
  Future<int> freePort();
}

/// The engine's pymobiledevice3, as [ScreenTouchTools].
final class PymdScreenTouchTools implements ScreenTouchTools {
  PymdScreenTouchTools({
    required Pymd pymd,
    required HostProcessInterface processes,
    required Future<int> Function() freePort,
  }) : _pymd = pymd,
       _processes = processes,
       _freePort = freePort;

  final Pymd _pymd;
  final HostProcessInterface _processes;
  final Future<int> Function() _freePort;

  @override
  Future<String> run(List<String> args, {required Duration timeout}) async =>
      (await _pymd.run(args, timeout: timeout)).stdout;

  @override
  Future<TouchProcess> start(List<String> args) async {
    final inv = await _pymd.resolve();
    final process = await _processes.start(inv.executable, [
      ...inv.prefixArgs,
      ...args,
    ]);
    return HostTouchProcess(process, _processes);
  }

  @override
  Future<int> freePort() => _freePort();
}

/// Touch through WebDriverAgent: finds the touch helper on the iPhone, mounts
/// the developer image, starts it with XCTest and forwards its port 8100.
final class WdaScreenTouch implements ScreenTouch {
  WdaScreenTouch(this._tools);

  final ScreenTouchTools _tools;

  /// The executable of WebDriverAgent's runner app, whatever its bundle id.
  static const runnerExecutable = 'WebDriverAgentRunner-Runner';

  /// WebDriverAgent's control port on the iPhone.
  static const devicePort = 8100;

  static const notInstalledMessage =
      'The touch helper is not on this iPhone yet. Set it up once from the '
      'Device screen (menu > Set up touch).';

  @override
  Future<ScreenTouchLink> start(String udid) async {
    // Each query costs seconds over Wi-Fi: ask all three at once. They are
    // lockdown services (no tunnel needed, even on iOS 17+).
    final lockdown = ['--udid', udid];
    final (major, bundleId, _) = await (
      _iosMajor(udid),
      findRunner(lockdown),
      _mountDeveloperImage(lockdown),
    ).wait;
    if (bundleId == null) {
      throw const ScreenTouchUnavailable('not_installed', notInstalledMessage);
    }
    final port = await _tools.freePort();
    // iOS 17 and later reach XCTest through the tunnel.
    final runner = await _tools.start([
      'developer',
      'dvt',
      'xcuitest',
      ...(major >= 17 ? ['--tunnel', udid] : lockdown),
      bundleId,
    ]);
    final TouchProcess forward;
    try {
      forward = await _tools.start([
        'usbmux',
        'forward',
        '--serial',
        udid,
        '$port',
        '$devicePort',
      ]);
    } on Object {
      await runner.kill();
      rethrow;
    }
    return WdaTouchLink(
      url: 'http://127.0.0.1:$port',
      runner: runner,
      forward: forward,
    );
  }

  /// The bundle id of the installed WebDriverAgent runner, or null.
  Future<String?> findRunner(List<String> device) async {
    for (final flags in const [
      ['--type', 'User'],
      ['--user'],
    ]) {
      final String out;
      try {
        out = await _tools.run([
          'apps',
          'list',
          ...flags,
          ...device,
        ], timeout: const Duration(seconds: 45));
      } on Object {
        continue;
      }
      final Object? apps;
      try {
        apps = jsonDecode(out);
      } on FormatException {
        continue;
      }
      if (apps is! Map<Object?, Object?>) continue;
      final runners = [
        for (final MapEntry(:key, :value) in apps.entries)
          if (key is String &&
              value is Map<Object?, Object?> &&
              value['CFBundleExecutable'] == runnerExecutable)
            key,
      ]..sort();
      // Prefer the one Studio set up.
      return runners.where((id) => id.contains('xcross')).firstOrNull ??
          runners.firstOrNull;
    }
    return null;
  }

  Future<int> _iosMajor(String udid) async {
    try {
      final info = jsonDecode(
        await _tools.run([
          'lockdown',
          'info',
          '--udid',
          udid,
        ], timeout: const Duration(seconds: 30)),
      );
      if (info is Map<Object?, Object?>) {
        final version = info['ProductVersion'];
        if (version is String) {
          return int.tryParse(version.split('.').first) ?? 0;
        }
      }
    } on Object {
      // Unknown: try the classic way.
    }
    return 0;
  }

  /// XCTest needs the developer image; "already mounted" is fine, and a real
  /// failure shows up as the touch helper not starting.
  Future<void> _mountDeveloperImage(List<String> device) async {
    try {
      await _tools.run([
        'mounter',
        'auto-mount',
        ...device,
      ], timeout: const Duration(minutes: 3));
    } on Object {
      // See above.
    }
  }
}
