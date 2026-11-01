// studio: 012 — NDJSON build events for the XCross Studio GUI
// (specs/012-build-events/contracts/events.schema.json).
import 'dart:convert';

import 'package:cli_kit/shared/logging/logging.dart';

/// Writes what [Log] reports as one JSON object per line: `v` 1, ASCII-only.
///
/// Enabled by `XCROSS_EVENTS=ndjson` ([fromEnvironment]); the composition
/// root passes it as both `Log.events` and (through [logOutput]) `Log.output`.
final class NdjsonEvents implements LogEvents {
  NdjsonEvents(this._writeBytes);

  /// Events when `XCROSS_EVENTS=ndjson` is set, otherwise null.
  static NdjsonEvents? fromEnvironment(
    Map<String, String> environment,
    void Function(List<int> bytes) writeBytes,
  ) => environment['XCROSS_EVENTS']?.trim().toLowerCase() == 'ndjson'
      ? NdjsonEvents(writeBytes)
      : null;

  final void Function(List<int> bytes) _writeBytes;

  /// The `Log.output` for event mode: text written straight to the output
  /// becomes `log` events.
  late final LogOutput logOutput = NdjsonLogOutput(this);

  @override
  void message(LogEventLevel level, String message) {
    final text = stripAnsi(message);
    switch (level) {
      case LogEventLevel.warn || LogEventLevel.error:
        final issue = parseCoded(text);
        event(level == LogEventLevel.warn ? 'warning' : 'error', {
          'code': issue.code,
          'message': issue.message,
          'hint': issue.hint,
        });
      case LogEventLevel.info || LogEventLevel.trace:
        event('log', {'level': level.name, 'message': text});
    }
  }

  @override
  void stepStarted(String label) =>
      event('step', {'name': stripAnsi(label), 'status': 'start'});

  @override
  void stepOutput(String label, String line) => event('log', {
    'level': 'trace',
    'message': stripAnsi(line),
    'step': stripAnsi(label),
  });

  @override
  void stepFinished(
    String label, {
    required bool ok,
    required String message,
    required Duration elapsed,
  }) => event('step', {
    'name': stripAnsi(label),
    'status': ok ? 'done' : 'failed',
    'message': message == label ? null : stripAnsi(message),
    'elapsedMs': elapsed.inMilliseconds,
  });

  @override
  void event(String type, Map<String, Object?> fields) =>
      _writeBytes(utf8.encode(_asciiLine({'v': 1, 'type': type, ...fields})));

  /// `[code] message` + `hint: …` as printed by xcross (`codedError`,
  /// `codedWarning`, `formatFailure`); code and hint are null when absent.
  static ({String? code, String message, String? hint}) parseCoded(
    String text,
  ) {
    var body = text.trim();
    final prefix = _severity.firstMatch(body);
    if (prefix != null) body = body.substring(prefix.end);
    String? hint;
    final lines = <String>[];
    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (hint == null && trimmed.toLowerCase().startsWith('hint:')) {
        hint = trimmed.substring(5).trim();
      } else if (hint != null) {
        hint = '$hint\n$trimmed';
      } else {
        lines.add(line);
      }
    }
    var message = lines.join('\n').trim();
    String? code;
    final coded = _code.firstMatch(message);
    if (coded != null) {
      code = coded.group(1);
      message = message.substring(coded.end).trim();
    }
    return (code: code, message: message, hint: hint);
  }

  static final _severity = RegExp(
    r'^(error|warning|warn):\s*',
    caseSensitive: false,
  );
  static final _code = RegExp(r'^\[([a-z0-9_]+(?:\.[a-z0-9_]+)+)\]\s*');
  static final _ansi = RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]');

  /// [text] without ANSI escape sequences.
  static String stripAnsi(String text) => text.replaceAll(_ansi, '');

  /// Compact JSON with every code unit above 0x7e escaped, plus LF.
  static String _asciiLine(Map<String, Object?> event) {
    final out = StringBuffer();
    for (final unit in jsonEncode(event).codeUnits) {
      if (unit > 0x7e) {
        out
          ..write(r'\u')
          ..write(unit.toRadixString(16).padLeft(4, '0'));
      } else {
        out.writeCharCode(unit);
      }
    }
    out.write('\n');
    return out.toString();
  }
}

/// [LogOutput] of event mode: each line written straight to the output is a
/// `log` event (stream `stdout` or `stderr`), so nothing is lost.
final class NdjsonLogOutput implements LogOutput {
  NdjsonLogOutput(this.events);

  final NdjsonEvents events;
  String _partial = '';

  @override
  bool get supportsAnsi => false;

  @override
  int get terminalColumns => 120;

  @override
  void stdout(String message) {
    _flush();
    _emit(message, 'stdout');
  }

  @override
  void stderr(String message) {
    _flush();
    _emit(message, 'stderr');
  }

  @override
  void write(String message) {
    final text =
        _partial + message.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = text.split('\n');
    _partial = lines.removeLast();
    for (final line in lines) {
      _emit(line, 'stdout');
    }
  }

  void _flush() {
    if (_partial.isEmpty) return;
    final line = _partial;
    _partial = '';
    _emit(line, 'stdout');
  }

  void _emit(String message, String stream) {
    final text = NdjsonEvents.stripAnsi(message);
    if (text.trim().isEmpty) return;
    events.event('log', {'level': 'info', 'message': text, 'stream': stream});
  }
}
