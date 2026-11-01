import 'package:meta/meta.dart';

/// Masks device identifiers, push tokens and email addresses (FR-004).
@internal
abstract final class SensitiveMasker {
  static final _rules = <(RegExp, String)>[
    (RegExp('[A-Za-z0-9_-]{11,}:APA91b[A-Za-z0-9_-]{20,}'), '<token>'),
    (RegExp('(?<![0-9A-Fa-f])[0-9A-Fa-f]{64}(?![0-9A-Fa-f])'), '<token>'),
    (RegExp('(?<![0-9A-Fa-f])[0-9A-Fa-f]{40}(?![0-9A-Fa-f])'), '<udid>'),
    (
      RegExp('(?<![0-9A-Fa-f])[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}(?![0-9A-Fa-f])'),
      '<udid>',
    ),
    (RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'), '<email>'),
  ];

  /// [text] with every sensitive value replaced by a placeholder.
  static String mask(String text) {
    var result = text;
    for (final (pattern, replacement) in _rules) {
      result = result.replaceAll(pattern, replacement);
    }
    return result;
  }
}
