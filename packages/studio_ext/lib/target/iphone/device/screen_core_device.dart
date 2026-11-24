// studio: 048 — the live iPhone screen through Apple's own screen service
// (CoreDevice display service, iOS 27+): HEVC video and live touch, no driver
// change. pymobiledevice3 serves a viewer page on 127.0.0.1.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:studio_ext/target/iphone/device/screen_touch.dart';

/// Why Apple's screen service could not start.
final class CoreDeviceScreenUnavailable implements Exception {
  const CoreDeviceScreenUnavailable(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A running Apple screen service viewer.
abstract interface class CoreDeviceScreenSession {
  /// `http://127.0.0.1:<port>/`: the viewer page (picture and touch).
  Uri get viewer;

  /// The tool's output lines (for errors).
  Stream<String> get output;

  Future<int> get exitCode;

  Future<void> stop();
}

/// Starts Apple's screen service for an iPhone that has it.
abstract interface class CoreDeviceScreen {
  /// The iPhone's iOS major version (0 when unknown).
  Future<int> iosMajor(String udid);

  /// Starts the viewer; throws [CoreDeviceScreenUnavailable] with a short reason on failure.
  Future<CoreDeviceScreenSession> start(String udid);
}

/// [CoreDeviceScreen] through the engine's pymobiledevice3.
final class PymdCoreDeviceScreen implements CoreDeviceScreen {
  PymdCoreDeviceScreen(
    this._tools, {
    this.readyTimeout = const Duration(seconds: 60),
    Future<bool> Function(Uri)? answers,
  }) : _answers = answers ?? _httpAnswers;

  /// The first iOS with the display service.
  static const firstIos = 27;

  final ScreenTouchTools _tools;
  final Duration readyTimeout;
  final Future<bool> Function(Uri) _answers;

  @override
  Future<int> iosMajor(String udid) async {
    try {
      final Object? info = jsonDecode(
        await _tools.run([
          'lockdown',
          'info',
          '--udid',
          udid,
        ], timeout: const Duration(seconds: 30)),
      );
      if (info case {'ProductVersion': final String version}) {
        return int.tryParse(version.split('.').first) ?? 0;
      }
    } on Object {
      // Unknown.
    }
    return 0;
  }

  @override
  Future<CoreDeviceScreenSession> start(String udid) async {
    // The service is on the developer image; "already mounted" is fine.
    try {
      await _tools.run([
        'mounter',
        'auto-mount',
        '--udid',
        udid,
      ], timeout: const Duration(minutes: 3));
    } on Object {
      // A real failure shows up as the service missing below.
    }
    final port = await _tools.freePort();
    final process = await _tools.start([
      'developer',
      'core-device',
      'display',
      'serve-web',
      '--userspace',
      '--no-audio',
      '--http-port',
      '$port',
    ]);
    final viewer = Uri.parse('http://127.0.0.1:$port/');
    final lines = <String>[];
    final output = process.output.asBroadcastStream();
    final sub = output.listen((line) {
      lines.add(line);
      if (lines.length > 40) lines.removeAt(0);
    });
    var exited = false;
    unawaited(process.exitCode.then((_) => exited = true));
    final deadline = DateTime.now().add(readyTimeout);
    var ready = false;
    while (!exited && DateTime.now().isBefore(deadline)) {
      if (await _answers(viewer)) {
        ready = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (ready) {
      // The page answers before the video starts: a missing service shows up
      // in the log right after.
      await Future<void>.delayed(const Duration(seconds: 2));
      if (lines.any((l) => l.contains('does not offer'))) ready = false;
    }
    await sub.cancel();
    if (!ready || exited) {
      await process.kill();
      throw CoreDeviceScreenUnavailable(_reason(lines));
    }
    return _Session(viewer, process, output);
  }

  static String _reason(List<String> lines) {
    if (lines.any((l) => l.contains('does not offer'))) {
      return "This iPhone does not offer Apple's screen service (iOS 27 or "
          'later with Developer Mode on is needed).';
    }
    final last = lines.lastWhere(
      (l) => l.contains('Error') || l.contains('error'),
      orElse: () => '',
    );
    return last.isEmpty
        ? "Apple's screen service did not start."
        : "Apple's screen service did not start: ${last.trim()}";
  }

  static Future<bool> _httpAnswers(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final response = await (await client.getUrl(uri)).close();
      await response.drain<void>();
      return response.statusCode == 200;
    } on Object {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}

final class _Session implements CoreDeviceScreenSession {
  _Session(this.viewer, this._process, this.output);

  @override
  final Uri viewer;
  final TouchProcess _process;

  @override
  final Stream<String> output;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<void> stop() => _process.kill();
}
