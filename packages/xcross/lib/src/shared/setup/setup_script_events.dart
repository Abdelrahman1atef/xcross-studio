import 'dart:async';
import 'dart:convert';

import 'package:cli_kit/shared/logging/logging.dart';
import 'package:cli_kit/shared/process/process.dart';
import 'package:meta/meta.dart';
import 'package:xcross/src/shared/errors/errors.dart';

/// A setup script's output as structured events, for when xcross reports
/// NDJSON events (`XCROSS_EVENTS=ndjson`) and raw script output would break
/// the stream.
///
/// The built-in scripts print `##xcross {"step":"llvm","status":"start",
/// "label":"LLVM"}` around each installer when `XCROSS_SETUP_EVENTS=1`.
/// Each marker becomes a `step` event (`name` is the step id, `message` the
/// label, `status` one of start, done, skipped or failed, `elapsedMs` once it
/// ends); every other line becomes a `log` event tagged with the running
/// step.
@internal
final class SetupScriptEvents {
  SetupScriptEvents(this._events);

  /// What starts a marker line.
  static const marker = '##xcross ';
  static const _statuses = {'start', 'done', 'skipped', 'failed'};
  static final _ansi = RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]');

  final LogEvents _events;
  final _running = <String, Stopwatch>{};
  final _failed = <String>[];
  String? _current;

  /// Steps that ended failed, in order.
  List<String> get failed => List.unmodifiable(_failed);

  /// Reports one line the script printed on [stream] (`stdout`, `stderr`).
  void line(String text, {required String stream}) {
    final line = text.replaceAll(_ansi, '').trimRight();
    if (line.trim().isEmpty) return;
    if (_marker(line) case (:final step, :final status, :final label)) {
      _step(step, status, label);
      return;
    }
    _events.event('log', {
      'level': 'info',
      'message': line,
      'stream': stream,
      'step': ?_current,
    });
  }

  /// Fails every step the script began but did not end (it stopped early).
  void finish() {
    for (final step in [..._running.keys]) {
      _step(step, 'failed', 'The setup script stopped during this step.');
    }
  }

  void _step(String step, String status, String? label) {
    final Stopwatch? watch;
    if (status == 'start') {
      watch = null;
      _running[step] = Stopwatch()..start();
      _current = step;
    } else {
      watch = _running.remove(step);
      if (_current == step) _current = null;
      if (status == 'failed') _failed.add(step);
    }
    _events.event('step', {
      'name': step,
      'status': status,
      'message': label,
      'elapsedMs': ?watch?.elapsedMilliseconds,
    });
  }

  static ({String step, String status, String? label})? _marker(String line) {
    final start = line.indexOf(marker);
    if (start < 0 || line.substring(0, start).trim().isNotEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(line.substring(start + marker.length));
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    if (decoded case {
      'step': final String step,
      'status': final String status,
    } when step.isNotEmpty && _statuses.contains(status)) {
      final label = decoded['label'];
      return (
        step: step,
        status: status,
        label: label is String ? label : null,
      );
    }
    return null;
  }

  /// Runs a setup script with its output captured and reported through
  /// [events] instead of inherited by the terminal.
  static Future<void> run(
    ProcessRunner runner,
    LogEvents events,
    String executable,
    List<String> arguments,
    Map<String, String> environment,
  ) async {
    final reporter = SetupScriptEvents(events);
    final process = await runner.start(
      executable,
      arguments,
      environment: environment,
    );
    // Nothing answers prompts here; the scripts skip what they cannot ask.
    try {
      await process.stdin.close();
    } on Object catch (_) {}
    Future<void> pump(Stream<List<int>> source, String stream) => source
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach((line) => reporter.line(line, stream: stream));
    final drained = Future.wait([
      pump(process.stdout, 'stdout'),
      pump(process.stderr, 'stderr'),
    ]);
    final code = await process.exitCode;
    await drained;
    reporter.finish();
    if (code == 0) return;
    final failed = reporter.failed;
    throw XcrossError(
      failed.isEmpty
          ? 'Setup script failed (exit code $code): '
                '${ProcessRunner.commandLine(executable, arguments)}'
          : 'Setup could not install ${failed.join(', ')} '
                '(exit code $code); see the log for why.',
    );
  }
}
