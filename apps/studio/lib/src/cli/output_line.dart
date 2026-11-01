/// How a line of xcross output is shown.
enum LineKind { plain, command, success, failure, warning, error, hint, stderr }

/// One line of a job's output, classified for colouring and the issue list.
class OutputLine {
  const OutputLine(this.text, this.kind, {this.code});

  /// Classifies [raw] as xcross prints it: `error: [code] …`,
  /// `warning: [code] …`, `hint: …`, `✔ …` and `✖ …` lines; ANSI colour
  /// codes are removed.
  factory OutputLine.classify(String raw, {bool fromStderr = false}) {
    final text = stripAnsi(raw).replaceAll('\r', '');
    final trimmed = text.trimLeft();
    final code = _code.firstMatch(trimmed)?.group(1);
    final lower = trimmed.toLowerCase();
    final LineKind kind;
    if (lower.startsWith('error:') || lower.startsWith('error -')) {
      kind = LineKind.error;
    } else if (lower.startsWith('warning:') || lower.startsWith('warn:')) {
      kind = LineKind.warning;
    } else if (lower.startsWith('hint:')) {
      kind = LineKind.hint;
    } else if (trimmed.startsWith('✔') || trimmed.startsWith('✓')) {
      kind = LineKind.success;
    } else if (trimmed.startsWith('✖') || trimmed.startsWith('✗')) {
      kind = LineKind.failure;
    } else {
      kind = fromStderr ? LineKind.stderr : LineKind.plain;
    }
    return OutputLine(text, kind, code: code);
  }

  final String text;
  final LineKind kind;

  /// The stable xcross code (`device.not_found`) on error/warning lines.
  final String? code;

  bool get isIssue => kind == LineKind.error || kind == LineKind.warning;

  static final _code = RegExp(r'\[([a-z0-9_]+\.[a-z0-9_.]+)\]');
  static final _ansi = RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]');

  static String stripAnsi(String text) => text.replaceAll(_ansi, '');
}
