import 'dart:convert';
import 'dart:io';

import 'package:apple_developer_kit/shared/appstoreconnect/asc_config.dart';
import 'package:apple_developer_kit/shared/errors/errors.dart';
import 'package:apple_developer_kit/src/shared/appstoreconnect/asc_jwt.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:test/test.dart';

import '../support/host_services.dart';
import '../support/mapped_apple_fixture.dart';

void main() {
  test(
    'mapped filesystem owns credential save, load and private key reads',
    () async {
      final fixture = MappedAppleFixture();
      addTearDown(fixture.dispose);
      final keyPath = fixture.path('AuthKey_TEST.p8');
      final key = CryptoUtils.generateEcKeyPair();
      final pem = CryptoUtils.encodeEcPrivateKeyToPem(
        key.privateKey as ECPrivateKey,
      );
      fixture.fileSystem.file(keyPath).writeAsStringSync(pem);
      final credentials = AscCredentials(
        hostServices: fixture.services,
        issuerId: 'issuer',
        keyId: 'TEST',
        privateKeyPath: keyPath,
      );
      await credentials.save();
      final configPath = AscCredentials.defaultConfigPath(
        hostServices: fixture.services,
      );
      expect(File(configPath).existsSync(), isFalse);
      final loaded = await AscCredentialsLoader(
        hostServices: fixture.services,
      ).load();
      expect(loaded.issuerId, 'issuer');
      expect(await loaded.readPrivateKeyPem(), pem);
      expect((await AscJwt.generate(loaded)).split('.'), hasLength(3));
      expect(
        fixture.permissions.hardened.last,
        fixture.fileSystem.file(configPath).path,
      );
      fixture.fileSystem.file(configPath).writeAsStringSync('{broken');
      await expectLater(
        AscCredentialsLoader(hostServices: fixture.services).load(),
        throwsA(isA<AppleError>()),
      );
      await expectLater(
        AscCredentialsLoader(
          hostServices: fixture.services,
        ).load(path: fixture.path('missing')),
        throwsA(isA<AppleError>()),
      );
    },
  );

  group('AscJwt.generate', () {
    late Directory tmp;
    late AscCredentials credentials;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('xcross_asc_jwt-');
      // A throwaway EC keypair stands in for a real Apple .p8 key - no real
      // API key needed to test the JWT's structure/encoding.
      final keyPair = CryptoUtils.generateEcKeyPair();
      final pem = CryptoUtils.encodeEcPrivateKeyToPem(
        keyPair.privateKey as ECPrivateKey,
      );
      final keyFile = File('${tmp.path}/AuthKey_TESTKEY123.p8');
      await keyFile.writeAsString(pem);
      credentials = AscCredentials(
        hostServices: testHostServices,
        issuerId: 'issuer-1234',
        keyId: 'TESTKEY123',
        privateKeyPath: keyFile.path,
      );
    });

    tearDown(() => tmp.delete(recursive: true));

    test(
      'produces a 3-part base64url JWT with the right header/payload',
      () async {
        final token = await AscJwt.generate(credentials);
        final parts = token.split('.');
        expect(parts, hasLength(3));

        for (final part in parts) {
          // Unpadded, per JWS's base64url requirement (RFC 7515 §2).
          expect(part, isNot(contains('=')));
        }

        Map<String, dynamic> decodePart(String part) =>
            jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(part))))
                as Map<String, dynamic>;

        final header = decodePart(parts[0]);
        expect(header['alg'], 'ES256');
        expect(header['kid'], 'TESTKEY123');
        expect(header['typ'], 'JWT');

        final payload = decodePart(parts[1]);
        expect(payload['iss'], 'issuer-1234');
        expect(payload['aud'], 'appstoreconnect-v1');
        expect(payload['iat'], isA<int>());
        expect(payload['exp'], greaterThan(payload['iat'] as int));

        // JWS ES256 wants the raw r||s concatenation: 32 bytes each for P-256.
        final signatureBytes = base64Url.decode(base64Url.normalize(parts[2]));
        expect(signatureBytes, hasLength(64));
      },
    );

    test(
      'AC-015-1 an individual key is signed as the user, without iss',
      () async {
        final individual = AscCredentials(
          hostServices: testHostServices,
          issuerId: '',
          keyId: credentials.keyId,
          privateKeyPath: credentials.privateKeyPath,
          keyType: AscKeyType.individual,
        );
        final payload =
            jsonDecode(
                  utf8.decode(
                    base64Url.decode(
                      base64Url.normalize(
                        (await AscJwt.generate(individual)).split('.')[1],
                      ),
                    ),
                  ),
                )
                as Map<String, dynamic>;
        expect(payload['sub'], 'user');
        expect(payload.containsKey('iss'), isFalse);
        expect(payload['aud'], 'appstoreconnect-v1');
        expect(individual.identity, 'individual-TESTKEY123');
        expect(credentials.identity, 'issuer-1234');
      },
    );
  });

  test('AC-015-2 an individual key round-trips without an Issuer ID', () async {
    final fixture = MappedAppleFixture();
    addTearDown(fixture.dispose);
    final keyPath = fixture.path('ApiKey_TEST.p8');
    fixture.fileSystem.file(keyPath).writeAsStringSync('pem');
    await AscCredentials(
      hostServices: fixture.services,
      issuerId: '',
      keyId: 'TEST',
      privateKeyPath: keyPath,
      keyType: AscKeyType.individual,
    ).save();
    final configPath = AscCredentials.defaultConfigPath(
      hostServices: fixture.services,
    );
    final saved =
        jsonDecode(fixture.fileSystem.file(configPath).readAsStringSync())
            as Map<String, dynamic>;
    expect(saved.containsKey('issuerId'), isFalse);
    expect(saved['keyType'], 'individual');
    final loaded = await AscCredentialsLoader(
      hostServices: fixture.services,
    ).load();
    expect(loaded.keyType, AscKeyType.individual);
    expect(loaded.issuerId, '');
  });
}
