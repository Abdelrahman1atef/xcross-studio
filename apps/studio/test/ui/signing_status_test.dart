// Feature 026: the Signing page shows how the user signed in.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcross_studio/design_system/design_system.dart';
import 'package:xcross_studio/features/signing/signing_page.dart';
import 'package:xcross_studio/src/cli/xcross_events.dart';
import 'package:xcross_studio/src/state/settings.dart';

import 'app_test.dart' show check, go, pumpStudio, settle;

String _status({
  String? device,
  String? appStore,
  Map<String, Object?>? appleId,
  Map<String, Object?>? apiKey,
}) => jsonEncode({
  'v': 1,
  'type': 'auth_status',
  'deviceBuilds': device,
  'appStoreBuilds': appStore,
  'appleId': appleId,
  'apiKey': apiKey,
});

const _appleId = <String, Object?>{
  'email': 'me@example.invalid',
  'teamId': 'TEAM123',
  'anisetteUrl': 'https://anisette.example.invalid',
  'expires': '2099-01-02T00:00:00.000Z',
  'expired': false,
};

const _teamKey = <String, Object?>{
  'keyType': 'team',
  'issuerId': 'issuer-uuid',
  'keyId': 'KEY123',
  'privateKeyPath': r'C:\keys\AuthKey_KEY123.p8',
  'privateKeyFound': true,
};

final _doctor = [
  check(
    'Deployment',
    'Authentication',
    'success',
    'Apple ID session is available.',
  ),
];

Future<void> _open(WidgetTester tester, String status) async {
  await pumpStudio(
    tester,
    doctor: _doctor,
    authStatus: status,
    // Feature 030 added the Accounts card above the form: a taller window
    // keeps the form built (lists build only what is on screen).
    size: const Size(1500, 1500),
    settings: Settings()..wizardDismissed = true,
  );
  await go(tester, 'Signing');
  await settle(tester, 5);
}

String _field(WidgetTester tester, String label) => tester
    .widget<TextField>(find.widgetWithText(TextField, label))
    .controller!
    .text;

void main() {
  test(
    'AC-026-1 AC-026-2 the event parses, and a part that cannot be read',
    () {
      final event =
          XcrossEvent.tryParse(
                _status(
                  device: 'api-key',
                  appleId: const {'problem': 'unreadable'},
                  apiKey: _teamKey,
                ),
              )!
              as AuthStatusReport;
      expect(event.deviceBuilds, 'api-key');
      expect(event.appStoreBuilds, isNull);
      expect(event.appleId!.problem, 'unreadable');
      expect(event.apiKey!.keyId, 'KEY123');
      expect(event.apiKey!.privateKeyFound, isTrue);
      expect(event.apiKey!.isIndividual, isFalse);
    },
  );

  group('AC-026-5 the Status section', () {
    testWidgets('shows both methods and what each kind of build uses', (
      tester,
    ) async {
      await _open(
        tester,
        _status(
          device: 'apple-id',
          appStore: 'api-key',
          appleId: _appleId,
          apiKey: _teamKey,
        ),
      );
      for (final text in [
        'me@example.invalid',
        'TEAM123',
        'https://anisette.example.invalid',
        'Team key',
        'issuer-uuid',
        'KEY123',
        r'C:\keys\AuthKey_KEY123.p8',
        'Device builds use',
        'App Store builds use',
      ]) {
        expect(
          find.descendant(
            of: find.byType(SavedSignInDetails),
            matching: find.text(text),
          ),
          findsOneWidget,
          reason: text,
        );
      }
      expect(find.text('Needs attention'), findsNothing);
    });

    testWidgets('warns about an expired session and a missing key file', (
      tester,
    ) async {
      await _open(
        tester,
        _status(
          device: 'apple-id',
          appStore: 'api-key',
          appleId: {
            ..._appleId,
            'expires': '2001-01-02T00:00:00.000Z',
            'expired': true,
          },
          apiKey: {..._teamKey, 'privateKeyFound': false},
        ),
      );
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.textContaining('session expired on 2001'), findsOneWidget);
      expect(find.textContaining('private key file is gone'), findsOneWidget);
    });

    testWidgets('warns that App Store builds have no team key', (tester) async {
      await _open(tester, _status(device: 'apple-id', appleId: _appleId));
      expect(find.textContaining('need a team key'), findsOneWidget);
    });

    testWidgets('an older CLI shows what the section showed before', (
      tester,
    ) async {
      await pumpStudio(
        tester,
        doctor: _doctor,
        settings: Settings()..wizardDismissed = true,
      );
      await go(tester, 'Signing');
      await settle(tester, 5);
      expect(find.text('Authenticated'), findsOneWidget);
      expect(find.text('Device builds use'), findsNothing);
    });
  });

  group('AC-026-6 the sign-in form', () {
    testWidgets('starts on Apple ID with its details, never a password', (
      tester,
    ) async {
      await _open(tester, _status(device: 'apple-id', appleId: _appleId));
      expect(_field(tester, 'Apple ID (email)'), 'me@example.invalid');
      expect(
        _field(tester, 'Anisette server (optional)'),
        'https://anisette.example.invalid',
      );
      expect(_field(tester, 'Password'), isEmpty);
    });

    testWidgets('starts on the API key when device builds use it', (
      tester,
    ) async {
      await _open(
        tester,
        _status(device: 'api-key', appStore: 'api-key', apiKey: _teamKey),
      );
      expect(_field(tester, 'Issuer ID'), 'issuer-uuid');
      expect(_field(tester, 'Key ID'), 'KEY123');
      expect(find.text(r'C:\keys\AuthKey_KEY123.p8'), findsWidgets);
    });

    testWidgets('an individual key starts on Individual key, with no issuer', (
      tester,
    ) async {
      await _open(
        tester,
        _status(
          device: 'api-key',
          apiKey: const {
            'keyType': 'individual',
            'issuerId': null,
            'keyId': 'KEY999',
            'privateKeyPath': r'C:\keys\AuthKey_KEY999.p8',
            'privateKeyFound': true,
          },
        ),
      );
      expect(find.widgetWithText(TextField, 'Issuer ID'), findsNothing);
      expect(_field(tester, 'Key ID'), 'KEY999');
    });

    testWidgets('a later refresh leaves what the user typed and chose', (
      tester,
    ) async {
      await _open(tester, _status(device: 'apple-id', appleId: _appleId));
      await tester.enterText(
        find.widgetWithText(TextField, 'Apple ID (email)'),
        'other@example.invalid',
      );
      await tester.ensureVisible(find.text('Re-check'));
      await tester.tap(find.text('Re-check'));
      await settle(tester, 5);
      expect(_field(tester, 'Apple ID (email)'), 'other@example.invalid');
    });
  });

  testWidgets('AC-026-7 with nothing saved the section and form are empty', (
    tester,
  ) async {
    await _open(tester, _status());
    expect(find.text('No sign-in is saved on this computer.'), findsOneWidget);
    expect(_field(tester, 'Apple ID (email)'), isEmpty);
    expect(find.byType(XCallout), findsWidgets, reason: 'the risk notes stay');
  });
}
