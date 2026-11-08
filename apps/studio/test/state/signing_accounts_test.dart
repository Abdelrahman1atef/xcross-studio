// Feature 030: the accounts signed in with before, kept for a quick switch.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:xcross_studio/src/cli/xcross_events.dart';
import 'package:xcross_studio/src/state/signing_accounts.dart';

SavedApiKey _key(
  String keyId, {
  String? issuer = 'issuer-1',
  String path = r'C:\keys\AuthKey_KEY.p8',
  String? problem,
}) => SavedApiKey(
  keyType: issuer == null ? 'individual' : 'team',
  issuerId: issuer,
  keyId: keyId,
  privateKeyPath: path,
  privateKeyFound: true,
  problem: problem,
);

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('studio-accounts-'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('AC-030-1 a signed-in key is added under its Key ID and then kept', () {
    final accounts = SigningAccounts();
    final at = DateTime.utc(2026, 11, 8, 10);
    accounts.remember(_key('AAA111'), now: at);

    final first = accounts.accounts.single;
    expect(first.name, 'AAA111');
    expect(first.issuerId, 'issuer-1');
    expect(first.isIndividual, isFalse);
    expect(first.lastUsed, at);

    // The same key again keeps the name and note the user gave it, and
    // follows the file when it moved.
    accounts.rename(first, 'Car wash team', note: 'TestFlight');
    accounts.remember(
      _key('AAA111', path: r'D:\keys\AuthKey_AAA111.p8'),
      now: at.add(const Duration(hours: 2)),
    );
    final again = accounts.accounts.single;
    expect(again.name, 'Car wash team');
    expect(again.note, 'TestFlight');
    expect(again.privateKeyPath, r'D:\keys\AuthKey_AAA111.p8');
    expect(again.lastUsed, at.add(const Duration(hours: 2)));
  });

  test('AC-030-1 an individual key is kept without an issuer', () {
    final accounts = SigningAccounts()..remember(_key('IND1', issuer: null));
    expect(accounts.accounts.single.isIndividual, isTrue);
    expect(accounts.accounts.single.issuerId, isNull);
  });

  test('AC-030-2 a key that could not be read is not remembered', () {
    final accounts = SigningAccounts()
      ..remember(_key('BAD1', problem: 'unreadable'))
      ..remember(const SavedApiKey(keyId: 'NOPATH'))
      ..remember(const SavedApiKey(privateKeyPath: 'x.p8'));
    expect(accounts.accounts, isEmpty);
  });

  test(
    'AC-030-3 the one in use is found by Key ID, the latest comes first',
    () {
      final accounts = SigningAccounts()
        ..remember(_key('OLD1'), now: DateTime.utc(2026, 11, 1))
        ..remember(
          _key('NEW1', issuer: 'issuer-2'),
          now: DateTime.utc(2026, 11, 8),
        )
        ..remember(_key('MID1'), now: DateTime.utc(2026, 11, 4));
      expect(accounts.accounts.map((a) => a.keyId), ['NEW1', 'MID1', 'OLD1']);
      expect(accounts.current(_key('MID1'))!.keyId, 'MID1');
      expect(accounts.current(_key('NONE')), isNull);
      expect(accounts.current(null), isNull);
    },
  );

  test('AC-030-4 removing forgets the entry and touches no file', () {
    final keyFile = File(p.join(temp.path, 'AuthKey_DEL1.p8'))
      ..writeAsStringSync('-----BEGIN PRIVATE KEY-----\nsecret\n');
    final accounts = SigningAccounts()
      ..remember(_key('DEL1', path: keyFile.path))
      ..remember(_key('KEEP1'));
    accounts.remove(accounts.current(_key('DEL1'))!);
    expect(accounts.accounts.map((a) => a.keyId), ['KEEP1']);
    expect(keyFile.existsSync(), isTrue);
    expect(keyFile.readAsStringSync(), contains('secret'));
  });

  test(
    'AC-030-5 the file keeps only the key ID, issuer, path and names',
    () async {
      final keyFile = File(p.join(temp.path, 'AuthKey_SAVE1.p8'))
        ..writeAsStringSync('-----BEGIN PRIVATE KEY-----\ntop-secret-bytes\n');
      final accounts = await SigningAccounts.load(temp.path);
      accounts.remember(_key('SAVE1', path: keyFile.path));
      await accounts.saved;

      final text = File(p.join(temp.path, 'signing-accounts.json'))
          .readAsStringSync();
      expect(text, isNot(contains('top-secret-bytes')));
      expect(text.toLowerCase(), isNot(contains('password')));
      final json = jsonDecode(text) as Map<String, Object?>;
      final entry = ((json['accounts']! as List).single as Map).keys.toSet();
      expect(entry, {
        'name',
        'keyId',
        'issuerId',
        'privateKeyPath',
        'note',
        'lastUsed',
      });

      final reloaded = await SigningAccounts.load(temp.path);
      expect(reloaded.accounts.single.keyId, 'SAVE1');
      expect(reloaded.accounts.single.privateKeyPath, keyFile.path);
    },
  );

  test(
    'AC-030-6 the profiles of the xcross-key script are read once',
    () async {
      final script = File(p.join(temp.path, 'key-profiles.json'))
        ..writeAsStringSync(
          jsonEncode({
            'profiles': {
              'team-a': {
                'keyId': 'DOC111',
                'issuerId': 'issuer-d',
                'privateKey': r'C:\keys\AuthKey_DOC111.p8',
                'note': 'Team A key',
              },
              'broken': {'keyId': 'NOFILE'},
            },
            'history': [
              {'name': 'team-a', 'at': '2026-11-08 12:07'},
            ],
          }),
        );
      final config = p.join(temp.path, 'config');
      final first = await SigningAccounts.load(config, importFrom: script);
      expect(first.accounts.map((a) => (a.name, a.keyId, a.note)), [
        ('team-a', 'DOC111', 'Team A key'),
      ]);

      // Once Studio has its own file the script's file is not read again.
      first.remove(first.accounts.single);
      await first.saved;
      final second = await SigningAccounts.load(config, importFrom: script);
      expect(second.accounts, isEmpty);
    },
  );

  test('AC-030-7 an unreadable file starts empty and never throws', () async {
    File(p.join(temp.path, 'signing-accounts.json'))
        .writeAsStringSync('{not json');
    final accounts = await SigningAccounts.load(temp.path);
    expect(accounts.accounts, isEmpty);
  });
}
