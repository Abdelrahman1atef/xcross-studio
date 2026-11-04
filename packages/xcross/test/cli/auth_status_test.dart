// studio: 026 — `xcross auth status`: how the user signed in.
import 'dart:convert';

import 'package:apple_developer_kit/shared/appstoreconnect/asc_config.dart';
import 'package:apple_developer_kit/shared/grandslam/app_token_exchange.dart';
import 'package:apple_developer_kit/shared/grandslam/grandslam_session_store.dart';
import 'package:args/command_runner.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/cli/command_prompt.dart';
import 'package:xcross/src/shared/errors/errors.dart';

import 'auth_fixture.dart';

@internal
final class RecordingPrompt implements CommandPrompt {
  final written = StringBuffer();

  @override
  bool get isInteractive => false;
  @override
  void write(String value) => written.write(value);
  @override
  String? readLine(String prompt) => null;
  @override
  String? readSecret(String prompt, {required String valueName}) =>
      throw StateError('Status must not ask for anything');
}

void main() {
  late AuthNamespaceFixture fixture;
  late String keyPath;
  const sessionToken = 'secret-session-token';
  const keyContents = 'secret-private-key-contents';

  setUp(() {
    fixture = AuthNamespaceFixture(style: p.Style.posix);
    addTearDown(fixture.dispose);
    keyPath = fixture.path('AuthKey_KEY123.p8');
    fixture.fileSystem.file(keyPath).writeAsStringSync(keyContents);
  });

  /// The fixture's Apple clients throw, so any network use fails the test.
  Future<String> run(List<String> arguments) async {
    final prompt = RecordingPrompt();
    await (CommandRunner<void>('fixture', 'fixture')..addCommand(
          authFixture(services: fixture.services, commandPrompt: prompt),
        ))
        .run(['auth', ...arguments]);
    return prompt.written.toString();
  }

  Future<Map<String, Object?>> status() async =>
      jsonDecode(await run(['status', '--json'])) as Map<String, Object?>;

  GrandSlamSessionStore sessions() =>
      GrandSlamSessionStore(hostServices: fixture.services);

  Future<void> saveSession({DateTime? expiry}) => sessions().save(
    GrandSlamSession(
      username: 'me@example.invalid',
      teamId: 'TEAM123',
      anisetteUrl: 'https://anisette.example.invalid',
      token: DeveloperServicesLoginToken(
        adsid: 'adsid',
        token: sessionToken,
        expiry: expiry ?? DateTime.utc(2099, 1, 2),
      ),
    ),
  );

  Future<void> saveKey({AscKeyType type = AscKeyType.team}) => AscCredentials(
    hostServices: fixture.services,
    issuerId: type == AscKeyType.team ? 'issuer-uuid' : '',
    keyId: 'KEY123',
    privateKeyPath: keyPath,
    keyType: type,
  ).save();

  group('AC-026-1 the command', () {
    test('with nothing saved, says so', () async {
      expect(await status(), {
        'v': 1,
        'type': 'auth_status',
        'deviceBuilds': null,
        'appStoreBuilds': null,
        'appleId': null,
        'apiKey': null,
      });
      expect(await run(['status']), contains('Not signed in'));
    });

    test('prints a report without --json', () async {
      await saveSession();
      await saveKey();
      final report = await run(['status']);
      expect(report, contains('Apple ID: me@example.invalid'));
      expect(report, contains('Team ID: TEAM123'));
      expect(report, contains('Issuer ID: issuer-uuid'));
      expect(report, contains('Device builds use: Apple ID'));
      expect(report, contains('App Store builds use: App Store Connect'));
    });

    test('takes no other option, and --json is for status only', () async {
      await expectLater(
        run(['status', '--key-id', 'X']),
        throwsA(isA<XcrossError>()),
      );
      await expectLater(run(['--json']), throwsA(isA<XcrossError>()));
      await expectLater(run(['clean', '--json']), throwsA(isA<XcrossError>()));
    });
  });

  group('AC-026-2 what it reports', () {
    test('an Apple ID session', () async {
      await saveSession();
      expect((await status())['appleId'], {
        'email': 'me@example.invalid',
        'teamId': 'TEAM123',
        'anisetteUrl': 'https://anisette.example.invalid',
        'expires': '2099-01-02T00:00:00.000Z',
        'expired': false,
      });
    });

    test('an expired session says so', () async {
      await saveSession(expiry: DateTime.utc(2001));
      final appleId = (await status())['appleId']! as Map<String, Object?>;
      expect(appleId['expired'], isTrue);
    });

    test('a team key', () async {
      await saveKey();
      expect((await status())['apiKey'], {
        'keyType': 'team',
        'issuerId': 'issuer-uuid',
        'keyId': 'KEY123',
        'privateKeyPath': keyPath,
        'privateKeyFound': true,
      });
    });

    test(
      'an individual key has no issuer, and a missing file is noticed',
      () async {
        await saveKey(type: AscKeyType.individual);
        fixture.fileSystem.file(keyPath).deleteSync();
        final apiKey = (await status())['apiKey']! as Map<String, Object?>;
        expect(apiKey['keyType'], 'individual');
        expect(apiKey['issuerId'], isNull);
        expect(apiKey['privateKeyFound'], isFalse);
      },
    );

    test(
      'a key file that cannot be read is a problem, not a failure',
      () async {
        fixture.fileSystem.file(
            AscCredentials.defaultConfigPath(hostServices: fixture.services),
          )
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('{broken');
        final apiKey = (await status())['apiKey']! as Map<String, Object?>;
        expect(apiKey['problem'], contains('invalid JSON'));
      },
    );
  });

  test('AC-026-3 no token, password or key contents, in either form', () async {
    await saveSession();
    await saveKey();
    for (final output in [
      await run(['status', '--json']),
      await run(['status']),
    ]) {
      expect(output, isNot(contains(sessionToken)));
      expect(output, isNot(contains(keyContents)));
      expect(output, isNot(contains('adsid')));
    }
  });

  group('AC-026-4 what each kind of build uses', () {
    Future<(Object?, Object?)> uses() async {
      final json = await status();
      return (json['deviceBuilds'], json['appStoreBuilds']);
    }

    test(
      'both saved: Apple ID for devices, the team key for the store',
      () async {
        await saveSession();
        await saveKey();
        expect(await uses(), ('apple-id', 'api-key'));
      },
    );

    test('an expired session still comes first for devices', () async {
      await saveSession(expiry: DateTime.utc(2001));
      await saveKey();
      expect((await uses()).$1, 'apple-id');
    });

    test('only a team key: both use it', () async {
      await saveKey();
      expect(await uses(), ('api-key', 'api-key'));
    });

    test('an individual key does not serve the App Store', () async {
      await saveKey(type: AscKeyType.individual);
      expect(await uses(), ('api-key', null));
    });

    test('a session sealed elsewhere falls through to the key', () async {
      await saveSession();
      await saveKey();
      // Without the key file that sealed it, the session cannot be opened.
      fixture.fileSystem
          .file(
            fixture.paths.context.join(
              fixture.services.configDirectory,
              'local.key',
            ),
          )
          .deleteSync();
      final json = await status();
      expect(json['deviceBuilds'], 'api-key');
      expect((json['appleId']! as Map)['problem'], contains('cannot be read'));
    });

    test('a broken session stops signing rather than use the key', () async {
      await saveKey();
      fixture.fileSystem.file(sessions().path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"not":"a session"}');
      final json = await status();
      expect(json['deviceBuilds'], isNull);
      expect(json['appStoreBuilds'], 'api-key');
      expect((json['appleId']! as Map)['problem'], isNotNull);
    });
  });
}
