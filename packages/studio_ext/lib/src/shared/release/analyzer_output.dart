// studio: 022 — reads `flutter analyze` output for `xcross release gate`:
// the issues it lists and the lines worth showing without `pub get`'s noise
// (specs/022-studio-release-flow, AC-022-5).
import 'package:meta/meta.dart';

/// One issue `flutter analyze` reported.
@internal
final class AnalyzerIssue {
  const AnalyzerIssue({
    required this.severity,
    required this.message,
    required this.file,
    required this.line,
    required this.column,
    required this.code,
  });

  /// `error`, `warning` or `info`.
  final String severity;
  final String message;

  /// As the analyzer printed it, relative to the project.
  final String file;
  final int line;
  final int column;

  /// The lint or diagnostic name, e.g. `deprecated_member_use`.
  final String code;

  String get location => '$file:$line:$column';

  Map<String, Object?> toJson() => {
    'severity': severity,
    'message': message,
    'file': file,
    'line': line,
    'column': column,
    'code': code,
  };

  /// `info · <message> · <file>:<line>:<column> (<code>)`.
  String render() => '$severity · $message · $location ($code)';
}

/// Parses `flutter analyze` output.
@internal
abstract final class AnalyzerOutput {
  // `   info - <message> - lib\a.dart:7:30 - deprecated_member_use` (current
  // Flutter) or `  info • <message> • lib/a.dart:7:30 • code` (older). The
  // message may itself contain ` - `: the location anchors the end.
  static final _messageFirst = RegExp(
    r'^\s*(error|warning|info)\s+[-•]\s+(.+)\s+[-•]\s+(\S+):(\d+):(\d+)'
    r'\s+[-•]\s+([a-z0-9_]+)\s*$',
  );

  // `  error - lib\a.dart:7:30 - <message> - code` (`dart analyze`).
  static final _locationFirst = RegExp(
    r'^\s*(error|warning|info)\s+[-•]\s+(\S+):(\d+):(\d+)\s+[-•]\s+(.+)'
    r'\s+[-•]\s+([a-z0-9_]+)\s*$',
  );

  // What `flutter analyze` prints while it gets the packages first.
  static final _pubNoise = [
    RegExp(r'^\s*[\w.-]+ \S+ \(\S+ available\)\s*$'),
    RegExp(r'^\s*[<>+*~-] [\w.-]+ \d+\.\d+\.\d+\S*( \(.*\))?\s*$'),
    RegExp(r'^\s*(Resolving dependencies|Downloading packages)'),
    RegExp(
      r'^\s*(Got dependencies|Changed \d+ dependenc|No dependencies changed)',
    ),
    RegExp(r'^\s*\d+ packages? ha(s|ve) newer versions'),
    RegExp(r'^\s*Try `(flutter|dart) pub outdated`'),
  ];

  static List<AnalyzerIssue> issues(Iterable<String> lines) => [
    for (final line in lines)
      if (_locationFirst.firstMatch(line) case final match?)
        AnalyzerIssue(
          severity: match[1]!,
          message: match[5]!.trim(),
          file: match[2]!,
          line: int.parse(match[3]!),
          column: int.parse(match[4]!),
          code: match[6]!,
        )
      else if (_messageFirst.firstMatch(line) case final match?)
        AnalyzerIssue(
          severity: match[1]!,
          message: match[2]!.trim(),
          file: match[3]!,
          line: int.parse(match[4]!),
          column: int.parse(match[5]!),
          code: match[6]!,
        ),
  ];

  /// [lines] without the package resolution `flutter analyze` prints first.
  static List<String> withoutPubNoise(Iterable<String> lines) => [
    for (final line in lines)
      if (!_pubNoise.any((noise) => noise.hasMatch(line))) line,
  ];
}
