// studio: 018 — what a rejected upload tells the user, and the promise that
// every rejection xcross knows has a check that finds it.
import 'dart:io';

import 'package:studio_ext/src/shared/appstore/apple_rejections.dart';
import 'package:test/test.dart';

void main() {
  test(
    'every known rejection names a rule that exists in the release check',
    () {
      final sources = [
        for (final name in ['release_checks.dart', 'release_structure.dart'])
          File('lib/src/shared/release/$name').readAsStringSync(),
      ].join('\n');
      for (final MapEntry(key: code, value: rejection)
          in knownRejections.entries) {
        expect(
          sources,
          contains("'${rejection.rule}'"),
          reason: '$code points at ${rejection.rule}',
        );
      }
    },
  );

  test('known codes get their fix, unknown ones say the check has no rule', () {
    const apple =
        '90429 Invalid Swift Support. The files libswiftCore.dylib are not at '
        'the expected location.';
    final hints = rejectionHints([
      apple,
      '90429 The same code again.',
      '90999 Something new.',
      'no code here',
    ]);
    expect(hints, hasLength(2));
    expect(hints.first, contains('standalone .dylib'));
    expect(hints.first, contains('release.loose_dylib'));
    expect(hints.last, allOf(contains('90999'), contains('no rule')));
    expect(rejectionHints(const []), isEmpty);
  });
}
