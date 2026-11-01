// studio: 002 — per-build warning collector (specs/002-quick-wins).
import 'package:cli_kit/shared/logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:xcross/src/shared/diagnostics/xcross_diagnostics.dart';

/// Prints coded build warnings once per (code, subject) and summarises them
/// at the end of a build.
@internal
final class BuildWarnings {
  BuildWarnings(this.log);

  final Log log;
  final Set<String> _seen = {};
  final Map<String, int> _counts = {};

  /// Prints `[code] message` + hint the first time [subject] is reported for
  /// [code]; later reports of the same pair are ignored.
  void warn(
    DiagnosticCode code, {
    required String subject,
    required String message,
    String? hint,
  }) {
    if (!_seen.add('${code.code}\u0000$subject')) return;
    _counts.update(code.code, (count) => count + 1, ifAbsent: () => 1);
    log.logWarn(codedWarning(code, message, hint: hint));
  }

  /// The end-of-build summary, or null when nothing was reported. Resets the
  /// collector for the next build.
  String? takeSummary() {
    if (_counts.isEmpty) return null;
    final codes = _counts.keys.toList()..sort();
    final total = _counts.values.fold(0, (sum, count) => sum + count);
    final summary =
        'Build finished with $total warning${total == 1 ? '' : 's'}: '
        '${[for (final code in codes) '$code ×${_counts[code]}'].join(', ')}';
    _seen.clear();
    _counts.clear();
    return summary;
  }
}
