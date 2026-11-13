import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xcross_studio/src/state/settings.dart';

import 'app_test.dart' show check, go, pumpStudio, settle;

/// Doctor output after saving an API key Apple refuses.
final _rejectedKeyDoctor = [
  check('Flutter project', 'Flutter SDK', 'success', 'Found'),
  check(
    'Deployment',
    'Authentication',
    'failure',
    'App Store Connect credentials are unusable: App Store Connect API '
        'error (HTTP 401): Provide a properly configured and signed bearer '
        'token.',
  ),
];

/// Doctor output after saving an individual key (feature 015).
final _individualKeyDoctor = [
  check('Flutter project', 'Flutter SDK', 'success', 'Found'),
  check(
    'Deployment',
    'Authentication',
    'failure',
    'Apple accepts this individual API key but does not let it manage '
        'devices, certificates, bundle IDs or provisioning profiles.',
  ),
];

Future<void> _fill(WidgetTester tester, String label, String text) async {
  final field = find.widgetWithText(TextField, label);
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
}

/// Runbook F18: the form is team-key only (Issuer ID, Key ID, .p8).
Future<void> _signInWithKey(WidgetTester tester) async {
  await _fill(tester, 'Issuer ID', 'issuer-uuid');
  await _fill(tester, 'Key ID', 'KEY123');
  await _fill(tester, 'Private key (.p8)', r'C:\keys\AuthKey_KEY123.p8');
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await settle(tester, 2);
  await tester.ensureVisible(find.text('Sign in').last);
  await tester.tap(find.text('Sign in').last);
  await settle(tester, 10);
}

void main() {
  testWidgets(
    'AC-013-9 the sign-in button ends with the job (was stuck on "Signing in…")',
    (tester) async {
      await pumpStudio(
        tester,
        doctor: _rejectedKeyDoctor,
        settings: Settings()..wizardDismissed = true,
      );
      await go(tester, 'Signing');
      await _signInWithKey(tester);
      expect(find.text('Signing in…'), findsNothing);
      expect(find.text('Sign in'), findsWidgets);
    },
  );

  testWidgets(
    'AC-013-10 AC-TK-1 a refused team key gets steps and App Store Connect, '
    'never an Apple ID action',
    (tester) async {
      final studio = await pumpStudio(
        tester,
        doctor: _rejectedKeyDoctor,
        settings: Settings()..wizardDismissed = true,
      );
      await go(tester, 'Signing');
      await _signInWithKey(tester);

      expect(
        find.text('Apple did not accept these credentials'),
        findsOneWidget,
      );
      expect(
        find.textContaining('refused the API key (HTTP 401)'),
        findsOneWidget,
      );
      expect(find.textContaining('KEY123 is listed as active'), findsOneWidget);
      expect(
        find.textContaining('Provide a properly configured'),
        findsNothing,
      );

      await tester.ensureVisible(find.text('Show details'));
      await tester.tap(find.text('Show details'));
      await settle(tester, 2);
      expect(
        find.textContaining('Provide a properly configured'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Open App Store Connect'));
      await tester.tap(find.text('Open App Store Connect'));
      await settle(tester, 2);
      expect(
        studio.launcher.opened,
        contains('https://appstoreconnect.apple.com/access/integrations/api'),
      );

      expect(find.text('Use Apple ID instead'), findsNothing);
      expect(find.widgetWithText(TextField, 'Apple ID (email)'), findsNothing);
    },
  );

  testWidgets(
    'AC-TK-4 an individual key gets the team-key message, with no Apple ID way out',
    (tester) async {
      final studio = await pumpStudio(
        tester,
        doctor: _individualKeyDoctor,
        settings: Settings()..wizardDismissed = true,
      );
      await go(tester, 'Signing');
      await _signInWithKey(tester);

      expect(
        studio.commands,
        contains(
          r'auth --issuer-id issuer-uuid --key-id KEY123 '
          r'--private-key C:\keys\AuthKey_KEY123.p8',
        ),
      );
      expect(find.text('This is an individual key'), findsOneWidget);
      expect(find.text('Use Apple ID instead'), findsNothing);

      await tester.ensureVisible(find.text('Create a team key'));
      await tester.tap(find.text('Create a team key'));
      await settle(tester, 2);
      expect(
        studio.launcher.opened,
        contains('https://appstoreconnect.apple.com/access/integrations/api'),
      );
    },
  );
}
