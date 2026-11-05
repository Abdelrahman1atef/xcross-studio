// studio: 018 — what xcross knows about the errors App Store Connect answers an
// upload with. Every entry names the `release check` rule that finds the same
// problem before an upload, so a rejection teaches the check once: an error
// code that is not here is one the check cannot find yet.
import 'package:meta/meta.dart';

/// One App Store Connect error code xcross has a rule for.
@internal
@immutable
final class KnownRejection {
  const KnownRejection(this.rule, this.fix);

  /// The `release.*` code that reports the same problem.
  final String rule;

  /// What to do, in a sentence.
  final String fix;
}

/// The rejections xcross has met, by Apple's code.
@internal
const knownRejections = <String, KnownRejection>{
  '90426': KnownRejection(
    'release.swift_support_missing',
    'The IPA lacks SwiftSupport. Install the SDK again (`xcross sdk install '
        '<Xcode.xip>`, or Settings → Darwin SDK) and build again.',
  ),
  '90429': KnownRejection(
    'release.loose_dylib',
    'Apple names the Swift libraries, but the cause is usually a standalone '
        '.dylib in Frameworks (iOS allows dynamic libraries only inside '
        'frameworks). Build again with a current xcross, which wraps the '
        'plugin library in a framework.',
  ),
  '90683': KnownRejection(
    'release.permission_missing_for_call',
    'The code calls an API that needs a usage description. Add the key Apple '
        'names to ios/Runner/Info.plist, with a sentence saying why.',
  ),
};

/// The lines to add under a rejection for the error codes in [descriptions]
/// (`code description` strings): the fix for the ones xcross knows, and for
/// the others a note that the check does not cover them yet.
@internal
List<String> rejectionHints(Iterable<String> descriptions) {
  final hints = <String>[];
  final seen = <String>{};
  for (final description in descriptions) {
    final code = RegExp(r'^\s*(\d{5})\b').firstMatch(description)?.group(1);
    if (code == null || !seen.add(code)) continue;
    final known = knownRejections[code];
    hints.add(
      known == null
          ? 'hint: `xcross release check` has no rule for $code yet; the '
                'check passing does not mean this is fixed. Keep the exact '
                'message, it is what a new rule is written from.'
          : 'hint: ${known.fix} (`xcross release check` reports it as '
                '${known.rule}.)',
    );
  }
  return hints;
}
