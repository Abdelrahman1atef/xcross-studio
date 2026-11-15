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
        for (final name in [
          'release_checks.dart',
          'release_structure.dart',
          'release_online.dart', // the --online rules
        ])
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

  // mastkdm 2026-11-15: all three were "no rule yet".
  test('90208, 90062 and 90186 name their rules', () {
    const minimum =
        '90208 Invalid Bundle. The bundle '
        'mastkdm.app/Frameworks/objective_c.framework does not support the '
        'minimum OS Version '
        'specified in the Info.plist.';
    const version =
        '90062 This bundle is invalid. The value for key '
        'CFBundleShortVersionString [1.0.6] …';
    final hints = rejectionHints([
      minimum,
      version,
      '90186 Invalid Pre-Release Train.',
    ]);
    expect(hints, hasLength(3));
    expect(hints[0], contains('release.framework_minimum_os'));
    expect(hints[1], contains('release.asc_version_closed'));
    expect(hints[2], contains('release.asc_version_closed'));
    expect(hints.join(), isNot(contains('no rule')));
  });
}
