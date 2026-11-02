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

Future<void> _signInWithKey(WidgetTester tester) async {
  await tester.tap(find.text('App Store Connect API key'));
  await settle(tester, 2);
  await tester.enterText(
    find.widgetWithText(TextField, 'Issuer ID'),
    'issuer-uuid',
  );
  await tester.enterText(find.widgetWithText(TextField, 'Key ID'), 'KEY123');
  await tester.enterText(
    find.widgetWithText(TextField, 'Private key (.p8)'),
    r'C:\keys\AuthKey_KEY123.p8',
  );
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
    'AC-013-10 a refused API key gets steps, App Store Connect and Apple ID actions',
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

      await tester.ensureVisible(find.text('Use Apple ID instead'));
      await tester.tap(find.text('Use Apple ID instead'));
      await settle(tester, 2);
      expect(
        find.widgetWithText(TextField, 'Apple ID (email)'),
        findsOneWidget,
      );
    },
  );
}
