import 'dart:convert';

import 'package:dart_mobile_device/target/iphone/device/pymd/syslog_entry.dart';
import 'package:meta/meta.dart';

/// Why a push-preset line is highlighted.
@internal
enum Highlight { registration, delivery, error }

/// A log entry ready to print: the parsed entry, the (masked) message and an
/// optional highlight.
@internal
final class DeviceLogEvent {
  const DeviceLogEvent({
    required this.entry,
    required this.message,
    this.highlight,
  });

  final SyslogEntry entry;
  final String message;
  final Highlight? highlight;

  /// NDJSON `devicelog` event (contracts/devicelog.schema.json).
  Map<String, Object?> toJson() => {
    'v': 1,
    'type': 'devicelog',
    'time': entry.time,
    'process': entry.process,
    'pid': entry.pid,
    'subsystem': entry.subsystem,
    'category': entry.category,
    'level': entry.level,
    'message': message,
    'highlight': highlight?.name,
  };

  /// `HH:MM:SS.mmm process[pid] L message`, `★`-prefixed when highlighted.
  String toHumanLine() {
    final clock = _clock(entry.time);
    final letter = entry.level.isEmpty ? '?' : entry.level[0].toUpperCase();
    final star = highlight == null ? '' : '★ ';
    return '$star$clock ${entry.process}[${entry.pid}] $letter $message';
  }

  /// `HH:MM:SS.mmm` from `YYYY-MM-DDTHH:MM:SS.ffffff`; the input otherwise.
  static String _clock(String time) {
    final t = time.indexOf('T');
    if (t < 0) return time;
    final clock = time.substring(t + 1);
    final dot = clock.indexOf('.');
    if (dot < 0) return clock;
    final fraction = clock.substring(dot + 1).padRight(3, '0').substring(0, 3);
    return '${clock.substring(0, dot)}.$fraction';
  }
}

/// One NDJSON line: compact JSON, every code unit above 0x7e escaped, LF.
@internal
String ndjsonLine(Map<String, Object?> event) {
  final text = jsonEncode(event);
  final out = StringBuffer();
  for (final unit in text.codeUnits) {
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
