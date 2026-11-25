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
  WdaScreenTouch(
    this._tools, {
    this.retryDelay = const Duration(seconds: 4),
    this.startTimeout = const Duration(seconds: 45),
    this.attempts = 3,
  });

  final ScreenTouchTools _tools;

  /// The wait before starting the touch helper again after it closed early.
  /// Right after a previous session was stopped (Studio restarting the
  /// screen), the iPhone needs a few seconds before XCTest starts again.
  final Duration retryDelay;

  /// How long to wait for XCTest to report the touch helper running.
  final Duration startTimeout;

  /// Starts tried before giving up.
  final int attempts;

  /// Lines pymobiledevice3 prints once the touch helper's test is running.
  static const _startedMarkers = [
    'didBeginExecutingTestPlan',
    'testCaseDidStart',
  ];

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
    final (int, String?, void) found;
    try {
      found = await (
        _iosMajor(udid),
        findRunner(lockdown),
        _mountDeveloperImage(lockdown),
      ).wait;
      // ignore: avoid_catching_errors
    } on ParallelWaitError<Object?, Object?> catch (e) {
      // `.wait` wraps the failure: hand on the one the caller understands.
      final errors = e.errors;
      if (errors is (AsyncError?, AsyncError?, AsyncError?)) {
        for (final failure in [errors.$1, errors.$2, errors.$3]) {
          final inner = failure?.error;
          if (inner is ScreenTouchUnavailable) throw inner;
        }
      }
      rethrow;
    }
    final (major, bundleId, _) = found;
    if (bundleId == null) {
      throw const ScreenTouchUnavailable('not_installed', notInstalledMessage);
    }
    // iOS 17 and later reach XCTest through the tunnel.
    final xcuitest = [
      'developer',
      'dvt',
      'xcuitest',
      ...(major >= 17 ? ['--tunnel', udid] : lockdown),
      bundleId,
    ];
    TouchProcess? runner;
    var problem = '';
    for (var attempt = 1; attempt <= attempts; attempt++) {
      final process = await _tools.start(xcuitest);
      final failed = await _waitStarted(process);
      if (failed == null) {
        runner = process;
        break;
      }
      problem = failed;
      await process.kill();
      if (attempt < attempts) await Future<void>.delayed(retryDelay);
    }
    if (runner == null) {
      throw ScreenTouchUnavailable(
        'error',
        'The touch helper did not start on the iPhone'
            '${problem.isEmpty ? '' : ': $problem'}',
      );
    }
    final port = await _tools.freePort();
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

  /// Null once XCTest reports the touch helper running (or after
  /// [startTimeout], leaving the final word to the screen helper); else why
  /// it closed.
  Future<String?> _waitStarted(TouchProcess process) async {
    final lines = <String>[];
    final outcome = Completer<String?>();
    final sub = process.output.listen((line) {
      lines.add(line);
      if (lines.length > 40) lines.removeAt(0);
      if (_startedMarkers.any(line.contains) && !outcome.isCompleted) {
        outcome.complete(null);
      }
    });
    unawaited(
      process.exitCode.then((_) {
        if (outcome.isCompleted) return;
        final why = WdaTouchLink.lastProblem(lines);
        outcome.complete(why.isEmpty ? 'it closed' : why);
      }),
    );
    final result = await outcome.future.timeout(
      startTimeout,
      onTimeout: () => null,
    );
    await sub.cancel();
    return result;
  }

  static const unreachableMessage =
      "Apple's service cannot reach this iPhone for touch right now. In Smooth "
      'mode it sees the iPhone only over Wi-Fi (turn on Wi-Fi sync for it, and '
      'give it a minute after a driver switch). Studio tries again by itself '
      'when the screen restarts.';

  /// The bundle id of the installed WebDriverAgent runner, or null when the
  /// iPhone answered and has none. Throws [ScreenTouchUnavailable] with
  /// `unreachable` when it could not be asked at all: that is not "not
  /// installed" (a phone in Smooth mode is hidden from Apple's service).
  Future<String?> findRunner(List<String> device) async {
    for (var pass = 0; pass < 2; pass++) {
      var answered = false;
      for (final flags in const [
        ['--type', 'User'],
        ['--user'],
      ]) {
        final id = await _runnerIn(flags, device, () => answered = true);
        if (id != null) return id;
        if (answered) return null;
      }
      if (pass == 0) await Future<void>.delayed(retryDelay);
    }
    throw const ScreenTouchUnavailable('unreachable', unreachableMessage);
  }

  /// The runner's bundle id from one `apps list` query; [answered] is called
  /// once the iPhone gave a readable answer (with or without the runner).
  Future<String?> _runnerIn(
    List<String> flags,
    List<String> device,
    void Function() answered,
  ) async {
    final String out;
    try {
      out = await _tools.run([
        'apps',
        'list',
        ...flags,
        ...device,
      ], timeout: const Duration(seconds: 45));
    } on Object {
      return null;
    }
    final Object? apps;
    try {
      apps = jsonDecode(out);
    } on FormatException {
      return null;
    }
    if (apps is! Map<Object?, Object?>) return null;
    answered();
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
