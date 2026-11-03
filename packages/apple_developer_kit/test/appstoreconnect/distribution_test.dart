// studio: 018 — App Store distribution provisioning (specs/018-app-store-build).
import 'dart:convert';
import 'dart:io';

import 'package:apple_developer_kit/shared/appstoreconnect/appstoreconnect.dart';
import 'package:apple_developer_kit/shared/appstoreconnect/asc_client.dart';
import 'package:apple_developer_kit/shared/appstoreconnect/asc_models.dart';
import 'package:apple_developer_kit/shared/errors/errors.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/host_services.dart';
import '../support/signing_fixture.dart';
import 'appstoreconnect_test.dart';

/// A fake App Store Connect client that can also issue distribution assets.
@internal
final class FakeDistributionClient extends FakeProvisioningClient
    implements DistributionProvisioningClient {
  FakeDistributionClient({super.existingProfiles});

  final List<AscCertificate> teamCertificates = [];
  final List<String> createdCsrs = [];
  AppleApiError? createError;
  String? appStoreProfileName;
  List<String>? appStoreCertificateIds;

  @override
  Future<List<AscCertificate>> listDistributionCertificates() async =>
      List.of(teamCertificates);

  @override
  Future<AscCertificate> createDistributionCertificate({
    required String csrPem,
  }) async {
    if (createError case final error?) throw error;
    createdCsrs.add(csrPem);
    final csr = X509Utils.csrFromPem(csrPem);
    final der = _selfSigned(
      csr.certificationRequestInfo!.publicKeyInfo!,
      csrPem,
    );
    return AscCertificate(
      id: 'new-cert',
      certificateContentBase64: base64Encode(der),
      expirationDate: null,
      serialNumber: '0A',
    );
  }

  @override
  Future<AscProfile> createAppStoreProfile({
    required String name,
    required String bundleIdResourceId,
    required List<String> certificateResourceIds,
  }) async {
    appStoreProfileName = name;
    appStoreCertificateIds = List.of(certificateResourceIds);
    return AscProfile(
      id: 'app-store-$bundleIdResourceId',
      profileContentBase64: base64Encode(testProfileCms(profileEntitlements)),
      uuid: 'uuid',
      profileState: 'ACTIVE',
      expirationDate: null,
    );
  }

  /// A certificate over the CSR's key, signed by a throwaway key (the
  /// provisioning code only reads its public key).
  static List<int> _selfSigned(Object _, String csrPem) {
    final signer = CryptoUtils.generateRSAKeyPair(keySize: 1024);
    final pem = X509Utils.generateSelfSignedCertificate(
      signer.privateKey as RSAPrivateKey,
      csrPem,
      365,
    );
    return CryptoUtils.getBytesFromPEMString(pem);
  }
}

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('xcross_dist_'));
  tearDown(() => temp.deleteSync(recursive: true));

  Future<DevelopmentIdentityPaths> provision(
    DevelopmentProvisioningClient client, {
    String? privateKeyPem,
    List<String>? progress,
  }) => AscProvisioning(hostServices: testHostServices, client: client)
      .provisionDistributionIdentity(
        bundleId: 'com.example.app',
        outputDir: p.join(temp.path, 'profiles'),
        identityDir: p.join(temp.path, 'identity'),
        privateKeyPem: privateKeyPem,
        capabilities: const {'PUSH_NOTIFICATIONS'},
        onProgress: progress?.add,
      );

  group('AC-018-2 distribution identity', () {
    test('creates a certificate from a saved key and an App Store profile; '
        'deletes only xcross App Store profiles', () async {
      final client = FakeDistributionClient(
        existingProfiles: const [
          AscProfileRef(id: 'old-xcross', name: 'xcross App Store 1'),
          AscProfileRef(id: 'theirs', name: 'Codemagic App Store'),
        ],
      )..profileEntitlements['aps-environment'] = 'production';
      final progress = <String>[];
      final result = await provision(client, progress: progress);

      expect(client.createdCsrs, hasLength(1));
      expect(File(result.privateKeyPemPath).existsSync(), isTrue);
      expect(
        File(result.certificatePemPath).readAsStringSync(),
        startsWith('-----BEGIN CERTIFICATE-----'),
      );
      expect(client.appStoreProfileName, startsWith('xcross App Store '));
      expect(client.appStoreCertificateIds, ['new-cert']);
      expect(client.deletedProfiles, ['old-xcross']);
      expect(progress, contains('Created an Apple Distribution certificate'));

      // A second run reuses the saved key and the team certificate.
      final reuse = FakeDistributionClient();
      reuse.teamCertificates.add(
        AscCertificate(
          id: 'team-cert',
          certificateContentBase64: base64Encode(
            CryptoUtils.getBytesFromPEMString(
              File(result.certificatePemPath).readAsStringSync(),
            ),
          ),
          expirationDate: null,
          serialNumber: '0A',
        ),
      );
      await provision(reuse);
      expect(reuse.createdCsrs, isEmpty);
      expect(reuse.appStoreCertificateIds, ['team-cert']);
    });

    test('XCROSS_CERTIFICATE_PRIVATE_KEY selects the key', () async {
      final pair = CryptoUtils.generateRSAKeyPair(keySize: 1024);
      final pem = CryptoUtils.encodeRSAPrivateKeyToPem(
        pair.privateKey as RSAPrivateKey,
      );
      final client = FakeDistributionClient();
      final result = await provision(client, privateKeyPem: pem);
      expect(
        File(result.privateKeyPemPath).readAsStringSync().trim(),
        pem.trim(),
      );
      final csr = X509Utils.csrFromPem(client.createdCsrs.single);
      expect(csr.certificationRequestInfo, isNotNull);
    });

    test('a certificate limit is reported, nothing is revoked', () async {
      final client = FakeDistributionClient()
        ..createError = const AppleApiError(409, 'limit reached');
      await expectLater(
        provision(client),
        throwsA(
          isA<AppleError>().having(
            (e) => e.message,
            'message',
            contains('XCROSS_CERTIFICATE_PRIVATE_KEY'),
          ),
        ),
      );
      expect(client.revoked, isEmpty);
    });
  });

  test(
    'AC-018-4 an Apple ID (development-only) client names the role needed',
    () {
      expect(
        provision(FakeProvisioningClient()),
        throwsA(
          isA<AppleError>().having(
            (e) => e.message,
            'message',
            contains('Admin or App Manager'),
          ),
        ),
      );
    },
  );
}
