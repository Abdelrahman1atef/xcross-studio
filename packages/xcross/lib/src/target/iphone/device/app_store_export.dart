// studio: 018 — `--export-method app-store`: distribution-signed IPA and
// `.xcarchive` (specs/018-app-store-build, AC-018-1…AC-018-5).
import 'package:apple_developer_kit/host/shared/apple_host_services.dart';
import 'package:apple_developer_kit/shared/appstoreconnect/appstoreconnect.dart';
import 'package:apple_developer_kit/shared/appstoreconnect/asc_client.dart';
import 'package:apple_developer_kit/shared/appstoreconnect/asc_config.dart';
import 'package:apple_developer_kit/shared/errors/errors.dart';
import 'package:apple_developer_kit/shared/signing/bundle_signer.dart';
import 'package:apple_developer_kit/shared/signing/signing_asset.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:cli_kit/shared/process/process.dart';
import 'package:meta/meta.dart';
import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:xcross/src/shared/artifact/app_capabilities.dart';
import 'package:xcross/src/shared/artifact/app_entitlements.dart';
import 'package:xcross/src/shared/artifact/plist_mutations.dart';
import 'package:xcross/src/shared/auth/signing_session.dart';
import 'package:xcross/src/shared/cli/shared/ipa_packager.dart';
import 'package:xcross/src/shared/device/signing_http_client_factory.dart';
import 'package:xcross/src/shared/diagnostics/xcross_diagnostics.dart';
import 'package:xcross/src/shared/errors/errors.dart';
import 'package:xcross/src/target/iphone/device/signed_bundle_preparer.dart';
import 'package:xcross/src/target/iphone/device/xcode_archive.dart';

/// Where an App Store export left its outputs.
@internal
@immutable
final class AppStoreExportResult {
  const AppStoreExportResult({
    required this.ipaPath,
    required this.archivePath,
    required this.bundleId,
    required this.missingDsyms,
  });

  final String ipaPath;
  final String archivePath;
  final String bundleId;

  /// Binaries no dSYM could be made for.
  final List<String> missingDsyms;
}

/// Signs a built `.app` for App Store distribution and writes the IPA and the
/// archive under the build folder (`ipa/`, `archive/`).
@internal
final class AppStoreExport<T extends PlatformHostInterface> {
  AppStoreExport({
    required this.runner,
    required this.hostServices,
    required this.httpClients,
    required this.environment,
    Future<AscCredentials> Function()? loadCredentials,
  }) : _loadCredentials =
           loadCredentials ??
           (() => AscCredentialsLoader(hostServices: hostServices).load());

  /// Environment variable holding the PEM private key of the distribution
  /// certificate (CI); otherwise the key saved under the signing identity.
  static const certificateKeyVariable = 'XCROSS_CERTIFICATE_PRIVATE_KEY';

  final ProcessRunner<T> runner;
  final AppleHostServices hostServices;
  final SigningHttpClientFactory httpClients;
  final Map<String, String> environment;
  final Future<AscCredentials> Function() _loadCredentials;

  static const _roleHint =
      'App Store signing needs an App Store Connect team API key with the '
      'Admin or App Manager role: run `xcross auth --issuer-id <id> --key-id '
      '<id> --private-key <AuthKey.p8>` (an Apple ID or an individual key '
      'cannot create distribution certificates).';

  HostFileSystemInterface get _files => runner.host.fileSystem;

  /// Signs [appPath] in place, then writes `<outputRoot>/ipa/<name>.ipa` and
  /// `<outputRoot>/archive/Runner.xcarchive`.
  Future<AppStoreExportResult> export({
    required String appPath,
    required String outputRoot,
  }) async {
    final AscCredentials credentials;
    try {
      credentials = await _loadCredentials();
    } on AppleError catch (error) {
      throw XcrossError('${error.message}\n$_roleHint');
    }
    if (credentials.keyType == AscKeyType.individual) {
      throw XcrossError(
        'The saved App Store Connect key is an individual key. $_roleHint',
      );
    }
    final paths = runner.host.paths.context;
    final configDirectory = paths.dirname(
      AscCredentials.defaultConfigPath(hostServices: hostServices),
    );
    final identityDir = SigningSession.identityDirFor(
      configDirectory,
      'appstoreconnect-${credentials.identity}',
    );
    final preparer = SignedBundlePreparer(
      fileSystem: _files,
      paths: runner.host.paths,
    );
    final bundleId = PlistMutations.readBundleIdentifier(
      await _files.file(paths.join(appPath, 'Info.plist')).readAsString(),
    );
    if (bundleId == null) {
      throw XcrossError('$appPath/Info.plist has no CFBundleIdentifier.');
    }
    preparer.validateContainment(appPath);
    // The App ID is always the real one for the App Store.
    final extensions = await preparer.rewriteExtensionIdentifiers(
      appPath,
      hostBundleId: bundleId,
      signedHostBundleId: bundleId,
    );

    final client = AscClient(credentials, httpClient: httpClients.create());
    try {
      final provisioning = AscProvisioning(
        hostServices: hostServices,
        client: client,
      );
      final capabilities = AppCapabilities(
        fileSystem: _files,
        paths: runner.host.paths,
      );
      final entitlements = AppEntitlements(
        fileSystem: _files,
        paths: runner.host.paths,
      );
      Future<SigningAsset> provision(String id, String bundlePath) async {
        runner.log.logInfo('App Store', id);
        final identity = await provisioning.provisionDistributionIdentity(
          bundleId: id,
          outputDir: paths.join(identityDir, 'app-store', id),
          identityDir: identityDir,
          privateKeyPem: environment[certificateKeyVariable],
          capabilities: capabilities.of(bundlePath).toSet(),
          onProgress: (message) => runner.log.logInfo('Signing', message),
          onCapabilityRefused: (type, reason) => runner.log.logWarn(
            codedWarning(
              XcrossCodes.signCapabilityNotEnabled,
              'The $type capability is not enabled on $id, so the App Store '
              'profile does not grant it: $reason',
            ),
          ),
        );
        final asset = await SigningAssetLoader(hostServices: hostServices).load(
          privateKeyPemPath: identity.privateKeyPemPath,
          certificatePemPath: identity.certificatePemPath,
          provisioningProfilePath: identity.profilePath,
          declaredEntitlements: entitlements.of(bundlePath),
        );
        return asset;
      }

      final asset = await provision(bundleId, appPath);
      final extensionAssets = <String, SigningAsset>{
        for (final extension in extensions)
          if (extension.path case final String path)
            extension.bundleId: await provision(extension.bundleId, path),
      };
      await preparer.stripPrivateKeys(appPath);
      for (final extension in extensions) {
        if (extension.path case final String path) {
          await preparer.stripPrivateKeys(path);
        }
      }
      await runner.log.logStep(
        'Signing for the App Store',
        () => BundleSigner(
          asset,
          hostServices: hostServices,
          extensionAssets: extensionAssets,
        ).signApp(appPath),
      );
      final info = await _files
          .file(paths.join(appPath, 'Info.plist'))
          .readAsString();
      return await package(
        appPath: appPath,
        outputRoot: outputRoot,
        app: ArchivedApp(
          bundleId: bundleId,
          shortVersion: _plistString(info, 'CFBundleShortVersionString') ?? '',
          buildNumber: _plistString(info, 'CFBundleVersion') ?? '',
          signingIdentity: asset.certificateCommonName,
          teamId: asset.teamIdentifier,
        ),
      );
    } finally {
      client.close();
    }
  }

  static String? _plistString(String xml, String key) {
    try {
      final value =
          (PropertyListSerialization.propertyListWithString(xml) as Map)[key];
      return value is String ? value : null;
    } on Object {
      return null;
    }
  }

  /// Writes the IPA and the archive for the signed [appPath].
  @visibleForTesting
  Future<AppStoreExportResult> package({
    required String appPath,
    required String outputRoot,
    required ArchivedApp app,
  }) async {
    final paths = runner.host.paths.context;
    final packaged = await IpaPackager(host: runner.host).package(appPath);
    final ipaDir = paths.join(outputRoot, 'ipa');
    await _files.directory(ipaDir).create(recursive: true);
    final ipaPath = paths.join(ipaDir, paths.basename(packaged));
    if (_files.file(ipaPath).existsSync()) await _files.file(ipaPath).delete();
    await _files.file(packaged).rename(ipaPath);
    final archivePath = paths.join(outputRoot, 'archive', 'Runner.xcarchive');
    final missing = await XcodeArchiveWriter(
      runner: runner,
    ).write(appPath: appPath, archivePath: archivePath, app: app);
    return AppStoreExportResult(
      ipaPath: ipaPath,
      archivePath: archivePath,
      bundleId: app.bundleId,
      missingDsyms: missing,
    );
  }
}
