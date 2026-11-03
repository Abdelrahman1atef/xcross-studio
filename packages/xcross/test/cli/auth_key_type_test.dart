// studio: 015 — team vs individual App Store Connect API keys in xcross auth.
import 'dart:convert';

import 'package:apple_developer_kit/shared/appstoreconnect/asc_config.dart';
import 'package:apple_developer_kit/shared/grandslam/app_token_exchange.dart';
import 'package:apple_developer_kit/shared/grandslam/grandslam_session_store.dart';
import 'package:args/command_runner.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/errors/errors.dart';

import 'auth_fixture.dart';

/// Apple as seen on 2026-11-02 for an individual key: a team-signed token
/// gets 401; an individual one may read apps but not devices.
http.Client _individualKeyApple(List<String> seen) =>
    MockClient((request) async {
      final token = request.headers['Authorization']!.split(' ').last;
      final payload =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(base64Url.normalize(token.split('.')[1])),
                ),
              )
              as Map<String, dynamic>;
      final kind = payload.containsKey('iss') ? 'team' : 'individual';
      seen.add('$kind ${request.url.path}');
      if (kind == 'individual' && request.url.path == '/v1/apps') {
        return http.Response('{"data":[]}', 200);
      }
      return http.Response(
        '{"errors":[{"status":"401","code":"NOT_AUTHORIZED",'
        '"title":"Authentication credentials are missing or invalid."}]}',
        401,
      );
    });

void main() {
  late AuthNamespaceFixture fixture;
  late String keyPath;

  setUp(() {
    fixture = AuthNamespaceFixture(style: p.Style.posix);
    keyPath = fixture.path('ApiKey_KEY123.p8');
    final pair = CryptoUtils.generateEcKeyPair();
    fixture.fileSystem
        .file(keyPath)
        .writeAsStringSync(
          CryptoUtils.encodeEcPrivateKeyToPem(pair.privateKey as ECPrivateKey),
        );
  });
  tearDown(() => fixture.dispose());

  Future<AscCredentials> run(List<String> args, List<String> seen) async {
    final runner = CommandRunner<void>('fixture', 'fixture')
      ..addCommand(
        authFixture(
          services: fixture.services,
          createHttpClient: () => _individualKeyApple(seen),
        ),
      );
    await runner.run(['auth', ...args]);
    final saved = await AscCredentialsLoader(
      hostServices: fixture.services,
    ).load();
    return saved;
  }

  test('AC-015-3 without --issuer-id the key is saved as individual', () async {
    final seen = <String>[];
    final saved = await run([
      '--key-id',
      'KEY123',
      '--private-key',
      'ApiKey_KEY123.p8',
    ], seen);
    expect(saved.keyType, AscKeyType.individual);
    expect(saved.issuerId, '');
    expect(seen, ['individual /v1/devices'], reason: 'provisioning probe');
  });

  test('AC-015-4 a key Apple refuses as team but accepts as individual is '
      'saved as individual', () async {
    final seen = <String>[];
    final saved = await run([
      '--issuer-id',
      'issuer-uuid',
      '--key-id',
      'KEY123',
      '--private-key',
      'ApiKey_KEY123.p8',
    ], seen);
    expect(saved.keyType, AscKeyType.individual);
    expect(seen, [
      'team /v1/apps',
      'individual /v1/apps',
      'individual /v1/devices',
    ]);
  });

  test('AC-015-8 an individual key that cannot sign keeps the Apple ID '
      'session', () async {
    final sessions = GrandSlamSessionStore(hostServices: fixture.services);
    await sessions.save(
      GrandSlamSession(
        username: 'fixture@example.invalid',
        token: DeveloperServicesLoginToken(
          adsid: 'fixture',
          token: 'not-a-real-token',
          expiry: DateTime.utc(2099),
        ),
        teamId: 'FIXTURE',
      ),
    );
    final saved = await run([
      '--key-id',
      'KEY123',
      '--private-key',
      'ApiKey_KEY123.p8',
    ], []);
    expect(saved.keyType, AscKeyType.individual);
    expect((await sessions.load())?.username, 'fixture@example.invalid');
  });

  // Seen 2026-11-03: a Key ID copied from another row with an AuthKey file
  // Apple refused both ways was saved as a team key and cleared the Apple ID
  // session, so device signing stopped working too.
  test('AC-015-9 a key Apple refuses both ways is not saved and keeps the '
      'Apple ID session; the error names a file and Key ID mismatch', () async {
    final sessions = GrandSlamSessionStore(hostServices: fixture.services);
    await sessions.save(
      GrandSlamSession(
        username: 'fixture@example.invalid',
        token: DeveloperServicesLoginToken(
          adsid: 'fixture',
          token: 'not-a-real-token',
          expiry: DateTime.utc(2099),
        ),
        teamId: 'FIXTURE',
      ),
    );
    final otherKey = fixture.path('AuthKey_OTHER99.p8');
    fixture.fileSystem
        .file(otherKey)
        .writeAsStringSync(fixture.fileSystem.file(keyPath).readAsStringSync());
    final seen = <String>[];
    final runner = CommandRunner<void>('fixture', 'fixture')
      ..addCommand(
        authFixture(
          services: fixture.services,
          createHttpClient: () => MockClient((request) async {
            seen.add(request.url.path);
            return http.Response('{"errors":[{"status":"401"}]}', 401);
          }),
        ),
      );
    await expectLater(
      runner.run([
        'auth',
        '--issuer-id',
        'issuer-uuid',
        '--key-id',
        'KEY123',
        '--private-key',
        'AuthKey_OTHER99.p8',
      ]),
      throwsA(
        isA<XcrossError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('was not saved'),
            contains('AuthKey_OTHER99.p8 but the Key ID is KEY123'),
          ),
        ),
      ),
    );
    expect(seen, ['/v1/apps', '/v1/apps']);
    expect(
      fixture.fileSystem
          .file(
            AscCredentials.defaultConfigPath(hostServices: fixture.services),
          )
          .existsSync(),
      isFalse,
    );
    expect((await sessions.load())?.username, 'fixture@example.invalid');
  });

  test('AC-015-5 offline: a team key stays a team key', () async {
    final runner = CommandRunner<void>('fixture', 'fixture')
      ..addCommand(authFixture(services: fixture.services));
    await runner.run([
      'auth',
      '--issuer-id',
      'issuer-uuid',
      '--key-id',
      'KEY123',
      '--private-key',
      'ApiKey_KEY123.p8',
    ]);
    final saved = await AscCredentialsLoader(
      hostServices: fixture.services,
    ).load();
    expect(saved.keyType, AscKeyType.team);
    expect(saved.issuerId, 'issuer-uuid');
  });
}
