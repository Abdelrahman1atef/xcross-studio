// Feature 030: the Signing page lists the accounts used before and switches
// between them through `xcross auth`.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:xcross_studio/design_system/design_system.dart';
import 'package:xcross_studio/src/state/settings.dart';
import 'package:xcross_studio/src/state/signing_accounts.dart';

import 'app_test.dart' show Studio, check, go, pumpStudio, settle;

String _status(String keyPath) => jsonEncode({
  'v': 1,
  'type': 'auth_status',
  'deviceBuilds': 'api-key',
  'appStoreBuilds': 'api-key',
  'apiKey': {
    'keyType': 'team',
    'issuerId': 'issuer-a',
    'keyId': 'KEYAAA',
    'privateKeyPath': keyPath,
    'privateKeyFound': true,
  },
});

final _doctor = [
  check('Deployment', 'Authentication', 'success', 'API key is available.'),
];

Finder _button(String label) => find.byWidgetPredicate(
  (widget) => widget is XButton && widget.label == label,
);

void main() {
  late Directory temp;
  late String fileB;
  late SigningAccounts accounts;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('studio-accounts-ui-');
    fileB = p.join(temp.path, 'AuthKey_KEYBBB.p8');
    File(fileB).writeAsStringSync('private-key-bytes');
    File(p.join(temp.path, 'AuthKey_KEYAAA.p8')).writeAsStringSync('a');
    accounts = SigningAccounts(
      accounts: [
        SigningAccount(
          name: 'Team A',
          keyId: 'KEYAAA',
          issuerId: 'issuer-a',
          privateKeyPath: p.join(temp.path, 'AuthKey_KEYAAA.p8'),
          lastUsed: DateTime.utc(2026, 11, 8),
        ),
        SigningAccount(
          name: 'Team B',
          keyId: 'KEYBBB',
          issuerId: 'issuer-b',
          privateKeyPath: fileB,
          note: 'Team 5PA5',
          lastUsed: DateTime.utc(2026, 11, 6),
        ),
        SigningAccount(
          name: 'Old team',
          keyId: 'KEYCCC',
          issuerId: 'issuer-c',
          privateKeyPath: p.join(temp.path, 'gone', 'AuthKey_KEYCCC.p8'),
          lastUsed: DateTime.utc(2026, 10, 1),
        ),
      ],
    );
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<Studio> open(WidgetTester tester) async {
    final studio = await pumpStudio(
      tester,
      doctor: _doctor,
      authStatus: _status(p.join(temp.path, 'AuthKey_KEYAAA.p8')),
      settings: Settings()..wizardDismissed = true,
      signingAccounts: accounts,
    );
    await go(tester, 'Signing');
    await settle(tester, 5);
    return studio;
  }

  testWidgets('AC-030-8 the accounts are listed and the saved one is in use', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('Team A'), findsOneWidget);
    expect(find.text('Team B'), findsOneWidget);
    expect(find.text('Team 5PA5'), findsOneWidget);
    // Only the account that matches the saved key says "In use" and has no
    // Use button; the other two do.
    expect(find.text('In use'), findsOneWidget);
    expect(_button('Use'), findsNWidgets(2));
    expect(find.textContaining('Key KEYBBB'), findsOneWidget);
  });

  testWidgets('AC-030-9 Use runs xcross auth with that key and nothing else', (
    tester,
  ) async {
    final studio = await open(tester);
    final before = studio.commands.length;
    await tester.tap(_button('Use').first);
    await settle(tester, 8);

    final switched = studio.launcher.starts
        .skip(before)
        .map((s) => s.arguments)
        .firstWhere((a) => a.first == 'auth');
    expect(switched, [
      'auth',
      '--issuer-id',
      'issuer-b',
      '--key-id',
      'KEYBBB',
      '--private-key',
      fileB,
    ]);
    // Nothing reads or sends the key file's contents: the command carries the
    // path only.
    expect(switched.join(' '), isNot(contains('private-key-bytes')));
    // A switch that worked is stamped as used just now.
    final used = accounts.accounts.firstWhere((a) => a.keyId == 'KEYBBB');
    expect(used.lastUsed!.isAfter(DateTime.utc(2026, 11, 7)), isTrue);
    // The app asked what is saved again, so "In use" follows Apple's answer.
    expect(
      studio.commands.skip(before).where((c) => c == 'auth status --json'),
      isNotEmpty,
    );
  });

  testWidgets('AC-030-10 a missing key file cannot be switched to', (
    tester,
  ) async {
    await open(tester);
    final buttons = tester.widgetList<XButton>(_button('Use')).toList();
    expect(buttons, hasLength(2));
    expect(buttons[0].onPressed, isNotNull); // Team B: file exists
    expect(buttons[1].onPressed, isNull); // Old team: file is gone
    expect(buttons[1].disabledReason, contains('missing'));
    expect(find.textContaining('The key file is gone'), findsOneWidget);
  });

  testWidgets('AC-030-11 remove asks first and leaves the key file alone', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Remove from the list').at(1));
    await settle(tester, 3);
    expect(
      find.textContaining('Only the entry here is removed'),
      findsOneWidget,
    );
    // Cancel keeps it.
    await tester.tap(find.text('Cancel'));
    await settle(tester, 3);
    expect(accounts.accounts, hasLength(3));

    await tester.tap(find.byTooltip('Remove from the list').at(1));
    await settle(tester, 3);
    await tester.tap(_button('Remove'));
    await settle(tester, 3);
    expect(accounts.accounts.map((a) => a.keyId), ['KEYAAA', 'KEYCCC']);
    expect(File(fileB).readAsStringSync(), 'private-key-bytes');
    expect(find.text('Team B'), findsNothing);
  });

  testWidgets('AC-030-12 renaming changes the name and note', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Rename').at(1));
    await settle(tester, 3);
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'Car wash');
    await tester.enterText(fields.at(1), 'Prod team');
    await tester.tap(_button('Save'));
    await settle(tester, 12); // the dialog's closing animation
    final renamed = accounts.accounts.firstWhere((a) => a.keyId == 'KEYBBB');
    expect((renamed.name, renamed.note), ('Car wash', 'Prod team'));
    expect(find.text('Car wash'), findsOneWidget);
  });

  testWidgets('AC-030-13 with no accounts the card is not shown', (
    tester,
  ) async {
    accounts = SigningAccounts();
    await pumpStudio(
      tester,
      doctor: _doctor,
      settings: Settings()..wizardDismissed = true,
      signingAccounts: accounts,
    );
    await go(tester, 'Signing');
    await settle(tester, 5);
    expect(find.text('Accounts'), findsNothing);
  });

  testWidgets('AC-030-14 a key Apple accepted joins the list on its own', (
    tester,
  ) async {
    accounts = SigningAccounts();
    await pumpStudio(
      tester,
      doctor: _doctor,
      authStatus: _status(p.join(temp.path, 'AuthKey_KEYAAA.p8')),
      settings: Settings()..wizardDismissed = true,
      signingAccounts: accounts,
    );
    await go(tester, 'Signing');
    await settle(tester, 5);
    final added = accounts.accounts.single;
    expect(
      (added.keyId, added.name, added.issuerId),
      ('KEYAAA', 'KEYAAA', 'issuer-a'),
    );
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('In use'), findsOneWidget);
  });
}
