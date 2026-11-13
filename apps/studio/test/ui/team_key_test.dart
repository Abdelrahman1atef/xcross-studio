// Runbook F18 / S38: install and Build & Run need an App Store Connect team key.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xcross_studio/features/signing/team_key.dart';
import 'package:xcross_studio/src/cli/xcross_events.dart';

AuthStatusReport _saved({
  Map<String, Object?>? apiKey,
  Map<String, Object?>? appleId,
}) =>
    XcrossEvent.tryParse(
          jsonEncode({
            'v': 1,
            'type': 'auth_status',
            'deviceBuilds': apiKey != null ? 'api-key' : 'apple-id',
            'appStoreBuilds': null,
            'appleId': appleId,
            'apiKey': apiKey,
          }),
        )!
        as AuthStatusReport;

const _team = <String, Object?>{
  'keyType': 'team',
  'issuerId': 'issuer-uuid',
  'keyId': 'KEY123',
  'privateKeyPath': r'C:\keys\AuthKey_KEY123.p8',
  'privateKeyFound': true,
};

void main() {
  group('AC-TK-3 install and Build & Run need a team key', () {
    test('a usable team key allows signing', () {
      expect(teamKeyMissingReason(_saved(apiKey: _team)), isNull);
    });

    test('only an Apple ID session (from the CLI) is not enough', () {
      expect(
        teamKeyMissingReason(_saved(appleId: const {'email': 'me@x.invalid'})),
        contains('team key'),
      );
    });

    test('an individual key is not enough', () {
      expect(
        teamKeyMissingReason(
          _saved(apiKey: {..._team, 'keyType': 'individual', 'issuerId': null}),
        ),
        contains('individual key'),
      );
    });

    test('a missing key file or an unreadable key is not enough', () {
      expect(
        teamKeyMissingReason(
          _saved(apiKey: {..._team, 'privateKeyFound': false}),
        ),
        isNotNull,
      );
      expect(
        teamKeyMissingReason(
          _saved(apiKey: {..._team, 'problem': 'unreadable'}),
        ),
        isNotNull,
      );
    });

    test('nothing is blocked before the saved sign-in has been read', () {
      expect(teamKeyMissingReason(null), isNull);
    });
  });
}
