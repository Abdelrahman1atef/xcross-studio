import 'dart:convert';

import 'package:meta/meta.dart';

/// A crash report file name: `<Process>-YYYY-MM-DD-HHMMSS.ips`.
@internal
final class CrashName {
  const CrashName({
    required this.name,
    required this.process,
    required this.time,
    String? path,
  }) : path = path ?? '/$name';

  static final _pattern = RegExp(
    r'^(.+)-(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})(\d{2})\.ips$',
  );

  /// Parses a `crash ls` entry (leading `/` and folders allowed); null for
  /// folders and non-report files.
  static CrashName? tryParse(String entry) {
    final name = entry.split('/').last;
    final match = _pattern.firstMatch(name);
    if (match == null) return null;
    final trimmed = entry.trim();
    return CrashName(
      name: name,
      path: trimmed.startsWith('/') ? trimmed : '/$trimmed',
      process: match[1]!,
      time:
          '${match[2]}-${match[3]}-${match[4]}T${match[5]}:${match[6]}:${match[7]}',
    );
  }

  final String name;

  /// Path on the device (`/Retired/<name>` once iOS has retired it).
  final String path;
  final String process;

  /// `YYYY-MM-DDTHH:MM:SS` (device-local).
  final String time;

  /// Newest first.
  static int newestFirst(CrashName a, CrashName b) => b.time.compareTo(a.time);
}

/// What a crash report says (`.ips`: JSON header line + JSON body).
@internal
final class CrashReportSummary {
  const CrashReportSummary({
    required this.exceptionType,
    required this.signal,
    required this.frames,
  });

  factory CrashReportSummary.fromIps(String text) {
    final newline = text.indexOf('\n');
    final body = newline < 0 ? '' : text.substring(newline + 1);
    Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      json = null;
    }
    if (json is! Map) {
      return const CrashReportSummary(
        exceptionType: null,
        signal: null,
        frames: [],
      );
    }
    final exception = json['exception'];
    final images = json['usedImages'];
    final threads = json['threads'];
    final faulting = json['faultingThread'];
    final frames = <String>[];
    if (threads is List && faulting is int && faulting < threads.length) {
      final thread = threads[faulting];
      final list = thread is Map ? thread['frames'] : null;
      if (list is List) {
        for (final frame in list.take(5)) {
          if (frame is! Map) continue;
          final index = frame['imageIndex'];
          final image = images is List && index is int && index < images.length
              ? images[index]
              : null;
          final imageName = image is Map ? '${image['name'] ?? '?'}' : '?';
          final symbol = frame['symbol'];
          frames.add(
            symbol is String
                ? '$imageName  $symbol'
                : '$imageName  +${frame['imageOffset'] ?? '?'}',
          );
        }
      }
    }
    return CrashReportSummary(
      exceptionType: exception is Map ? exception['type'] as String? : null,
      signal: exception is Map ? exception['signal'] as String? : null,
      frames: frames,
    );
  }

  final String? exceptionType;
  final String? signal;

  /// Top frames of the faulting thread: `image  symbol` or `image  +offset`.
  final List<String> frames;
}
