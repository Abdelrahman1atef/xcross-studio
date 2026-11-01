import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:studio_ext/src/shared/inspect/inspect_report.dart';
import 'package:studio_ext/src/shared/inspect/report_json.dart';
import 'package:test/test.dart';

import '../../support/fixture_builder.dart';
import '../../support/inspect_helpers.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('inspector_'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('AC-001-1 unsigned v2.0.9-style IPA', () {
    final report = inspectPath(
      unsignedV209().writeIpa(temp, 'unsigned_v209.ipa'),
    );
    expect(report.input.kind, InputKind.ipa);
    expect(report.input.name, 'unsigned_v209.ipa');
    expect(report.signature.present, isFalse);
    expect(report.signature.kind, SignatureKind.none);
    expect(report.profile, isNull);
    expect(report.bundle.path, 'Payload/Runner.app');
    expect(report.bundle.bundleId, 'com.example.fixture');
    expect(report.bundle.shortVersion, '1.0.0');
    expect(report.bundle.buildNumber, '1');
    expect(report.bundle.minimumOSVersion, '13.0');
    expect(report.bundle.infoPlistFormat, 'xml');
    expect(report.frameworks.map((f) => f.path), [
      'Frameworks/App.framework',
      'Frameworks/Flutter.framework',
      'Frameworks/libpath_provider_foundation.dylib',
    ]);
    expect(report.frameworks.first.bundleId, 'io.flutter.flutter.app');
    expect(report.frameworks.last.kind, FrameworkKind.dylib);

    final main = executableAt(report, 'Runner');
    expect(main.role, ExecutableRole.main);
    expect(main.architectures, ['arm64']);
    expect(main.signature.kind, SignatureKind.none);
    final app = executableAt(report, 'Frameworks/App.framework/App');
    expect(app.signature.kind, SignatureKind.adhoc);
    expect(app.signature.linkerSigned, isTrue);
    final flutter = executableAt(
      report,
      'Frameworks/Flutter.framework/Flutter',
    );
    expect(flutter.signature.kind, SignatureKind.certificate);
    expect(flutter.signature.teamId, 'FLTTEAM001');
    expect(
      executableAt(report, 'Frameworks/libpath_provider_foundation.dylib').role,
      ExecutableRole.dylib,
    );

    expect(report.resources.launchScreen.kind, LaunchScreenKind.uiLaunchScreen);
    expect(report.resources.launchScreen.keys, isEmpty);
    expect(issueCodes(report), [
      'inspect.launch_screen_empty',
      'inspect.no_icon',
    ]);
  });

  test('AC-001-2 ad-hoc main executable exposes aps-environment', () {
    final report = inspectPath(
      adhocPush().writeApp(temp, directoryName: 'adhoc_push.app'),
    );
    expect(report.input.kind, InputKind.app);
    expect(report.bundle.path, '.');
    expect(report.bundle.infoPlistFormat, 'binary');
    expect(report.signature.present, isTrue);
    expect(report.signature.kind, SignatureKind.adhoc);
    final main = report.mainExecutable!;
    expect(main.signature.kind, SignatureKind.adhoc);
    expect(main.entitlements!['aps-environment'], 'development');
    expect(main.entitlements!['com.apple.developer.associated-domains'], [
      'applinks:example.com',
      'webcredentials:example.com',
    ]);
    expect(main.derEntitlementsPresent, isTrue);
    expect(report.bundle.plist['UIBackgroundModes'], ['remote-notification']);
  });

  test('AC-001-3 profile summary without UDIDs', () {
    final report = inspectPath(
      profileAppex().writeIpa(temp, 'profile_appex.ipa'),
    );
    final profile = report.profile!;
    expect(profile.kind, ProfileKind.development);
    expect(profile.teamId, 'TEAMID1234');
    expect(profile.expirationDate, '2027-01-01T00:00:00Z');
    expect(profile.deviceCount, plantedUdids.length);
    expect(profile.certificateCount, 1);
    expect(profile.entitlements['aps-environment'], 'development');

    final main = report.mainExecutable!;
    expect(main.architectures, ['arm64', 'armv7']);
    expect(main.signature.kind, SignatureKind.certificate);
    expect(report.signature.teamId, 'TEAMID1234');

    final extension = report.extensions.single;
    expect(extension.path, 'PlugIns/Share.appex');
    expect(extension.bundleId, 'com.example.profile.Share');
    expect(extension.extensionPoint, 'com.apple.share-services');
    expect(extension.executable, 'PlugIns/Share.appex/Share');
    expect(extension.profile!.kind, ProfileKind.adHoc);
    final share = executableAt(report, 'PlugIns/Share.appex/Share');
    expect(share.role, ExecutableRole.extension);
    expect(share.entitlements!['com.apple.security.application-groups'], [
      'group.com.example.profile',
    ]);

    final json = encodeReportJson(report.toJson());
    for (final udid in plantedUdids) {
      expect(json, isNot(contains(udid)));
    }
    expect(json, isNot(contains(base64.encode(plantedCertificate))));
    expect(json, isNot(contains(plantedApiKey)));
    expect(report.bundle.infoPlistKeys, contains('GMSApiKey'));
  });

  test('AC-001-4 icons, Assets.car, launch screen', () {
    final push = inspectPath(
      adhocPush().writeApp(temp, directoryName: 'adhoc_push.app'),
    );
    final pushIcon = push.resources.icons.declared.single;
    expect(pushIcon.set, 'CFBundleIcons');
    expect(pushIcon.name, 'AppIcon60x60');
    expect(pushIcon.files, ['AppIcon60x60@2x.png', 'AppIcon60x60@3x.png']);
    expect(pushIcon.resolved, isTrue);
    expect(push.resources.icons.iconName, 'AppIcon');
    expect(push.resources.assetsCar.present, isFalse);
    expect(push.resources.launchScreen.keys, ['UIColorName', 'UIImageName']);
    expect(
      push.resources.launchScreen.image!.source,
      LaunchImageSource.looseFile,
    );
    expect(issueCodes(push), ['inspect.launch_image_not_in_catalog']);

    final profile = inspectPath(
      profileAppex().writeIpa(temp, 'profile_appex.ipa'),
    );
    final icons = profile.resources.icons.declared;
    expect(icons.map((i) => '${i.name}:${i.files}:${i.resolved}'), [
      'AppIcon60x60:[AppIcon60x60@2x.png, AppIcon60x60~ipad.png]:true',
      'AppIconMissing:[]:false',
    ]);
    expect(profile.resources.assetsCar.present, isTrue);
    expect(profile.resources.assetsCar.sizeBytes, 64);
    expect(
      profile.resources.launchScreen.image!.source,
      LaunchImageSource.assetCatalog,
    );
    expect(profile.resources.launchScreen.storyboard!.name, 'LaunchScreen');
    expect(profile.resources.launchScreen.storyboard!.compiledPresent, isFalse);
    expect(issueCodes(profile), [
      'inspect.icon_file_missing',
      'inspect.launch_storyboard_missing',
      'inspect.xcross_private_keys_in_signed_bundle',
    ]);
    expect(profile.bundle.xcrossPrivateKeys['XCrossEntitlements'], isTrue);
  });

  group('per-file problems become issues, not failures', () {
    test('truncated main executable', () {
      final report = inspectPath(
        unsignedV209(
          runner: machO().sublist(0, 20),
        ).writeIpa(temp, 'truncated.ipa'),
      );
      expect(issueCodes(report), contains('inspect.macho_invalid'));
      expect(report.mainExecutable!.architectures, isEmpty);
    });

    test('missing executable and unreadable Info.plist', () {
      final files = Map.of(unsignedV209().files)
        ..remove('Runner')
        ..['Info.plist'] = Uint8List.fromList(utf8.encode('garbage'));
      final report = inspectPath(
        FixtureBundle('Runner.app', files).writeIpa(temp, 'broken.ipa'),
      );
      expect(issueCodes(report), contains('inspect.info_plist_unreadable'));
      expect(issueCodes(report), contains('inspect.executable_missing'));
      expect(report.bundle.bundleId, isNull);
      expect(report.bundle.infoPlistFormat, isNull);
      expect(report.issues.first.severity, IssueSeverity.error);
    });

    test('no launch screen at all', () {
      final files = Map.of(unsignedV209().files)
        ..['Info.plist'] = xmlPlist(baseInfoPlist(bundleId: 'a.b'));
      final report = inspectPath(
        FixtureBundle('Runner.app', files).writeIpa(temp, 'plain.ipa'),
      );
      expect(report.resources.launchScreen.kind, LaunchScreenKind.none);
      expect(issueCodes(report), contains('inspect.no_launch_screen'));
    });
  });
}
