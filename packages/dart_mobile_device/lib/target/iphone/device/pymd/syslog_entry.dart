// studio: 010 — one parsed `pymobiledevice3 syslog live --format json` line,
// shared by `xcross logs` and the `flutter run` device log.
import 'dart:convert';

/// One device log entry.
final class SyslogEntry {
  const SyslogEntry({
    required this.pid,
    required this.process,
    required this.time,
    required this.level,
    required this.subsystem,
    required this.category,
    required this.message,
  });

  /// Parses one JSON line; null when it is not a log entry.
  static SyslogEntry? tryParse(String line) {
    final Object? json;
    try {
      json = jsonDecode(line);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, Object?>) return null;
    final pid = json['pid'];
    final message = json['message'];
    if (pid is! int || message is! String) return null;
    final label = json['label'];
    return SyslogEntry(
      pid: pid,
      process:
          _basename(json['filename']) ?? _basename(json['image_name']) ?? '',
      time: json['timestamp'] is String ? json['timestamp']! as String : '',
      level: _level(json['level']),
      subsystem: label is Map ? label['subsystem'] as String? : null,
      category: label is Map ? label['category'] as String? : null,
      message: message,
    );
  }

  final int pid;

  /// Process name: the basename of the executable path, e.g. `SpringBoard`.
  final String process;

  /// Device-local timestamp as reported, e.g. `2026-11-01T16:55:51.018604`.
  final String time;

  /// `debug`, `info`, `notice`, `error` or `fault`.
  final String level;
  final String? subsystem;
  final String? category;
  final String message;

  static const levels = ['debug', 'info', 'notice', 'error', 'fault'];

  static String _level(Object? raw) {
    final value = raw is String ? raw.toLowerCase() : '';
    if (value == 'default') return 'notice';
    return levels.contains(value) ? value : 'notice';
  }

  static String? _basename(Object? path) {
    if (path is! String || path.isEmpty) return null;
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }
}
