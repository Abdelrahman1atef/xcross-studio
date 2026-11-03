// studio: 018 — App Store export (specs/018-app-store-build).
import 'dart:io';

import 'package:apple_developer_kit/shared/appstoreconnect/asc_config.dart';
import 'package:apple_developer_kit/shared/errors/errors.dart';
import 'package:archive/archive.dart';
import 'package:cli_kit/composition/native_host.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:cli_kit/shared/process/process.dart';
import 'package:path/path.dart' as p;
import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:test/test.dart';
import 'package:xcross/src/shared/errors/errors.dart';
import 'package:xcross/src/target/iphone/device/app_store_export.dart';
import 'package:xcross/src/target/iphone/device/xcode_archive.dart';

import '../../cli/runtime_fixture.dart';
import '../../log_fixture.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('app-store-export-'));
  tearDown(() => root.deleteSync(recursive: true));

  String app() {
    final appDir = Directory(p.join(root.path, 'xcross-ios', 'Runner.app'))
      ..createSync(recursive: true);
    File(p.join(appDir.path, 'Info.plist')).writeAsStringSync(
      PropertyListSerialization.stringWithPropertyList(<String, Object>{
        'CFBundleIdentifier': 'com.example.app',
        'CFBundleExecutable': 'Runner',
        'CFBundleShortVersionString': '1.2.3',
        'CFBundleVersion': '7',
      }),
    );
    File(
      p.join(appDir.path, 'Runner'),
    ).writeAsBytesSync([0xcf, 0xfa, 0xed, 0xfe]);
    final framework = Directory(
      p.join(appDir.path, 'Frameworks', 'App.framework'),
    )..createSync(recursive: true);
    File(p.join(framework.path, 'App')).writeAsBytesSync([1, 2, 3]);
    File(
      p.join(appDir.path, 'Frameworks', 'libFlutterPluginsGenerated.dylib'),
    ).writeAsBytesSync([4]);
    return appDir.path;
  }

  ProcessRunner<PlatformHostInterface> nativeRunner() => ProcessRunner(
    detectPlatformHost(),
    log: testLog(),
    stdinStream: const Stream.empty(),
    stdoutSink: testByteSink(),
    stderrSink: testByteSink(),
  );

  AppStoreExport export({Future<AscCredentials> Function()? credentials}) {
    final runtime = testRuntime();
    return AppStoreExport(
      runner: nativeRunner(),
      hostServices: runtime.appleHostServices,
      httpClients: runtime.signingHttpClients,
      environment: const {},
      loadCredentials: credentials,
    );
  }

  const archived = ArchivedApp(
    bundleId: 'com.example.app',
    shortVersion: '1.2.3',
    buildNumber: '7',
    signingIdentity: 'Apple Distribution: Example (TEAM123456)',
    teamId: 'TEAM123456',
  );

  test(
    "AC-018-1 the IPA goes to ipa/ and the archive has Xcode's layout",
    () async {
      final appPath = app();
      final outputRoot = p.dirname(appPath);
      final result = await export().package(
        appPath: appPath,
        outputRoot: outputRoot,
        app: archived,
      );
      expect(result.ipaPath, p.join(outputRoot, 'ipa', 'Runner.ipa'));
      final zip = ZipDecoder().decodeBytes(
        File(result.ipaPath).readAsBytesSync(),
      );
      expect(
        zip.files.map((f) => f.name),
        contains('Payload/Runner.app/Info.plist'),
      );
      expect(File(p.join(outputRoot, 'Runner.ipa')).existsSync(), isFalse);

      final archive = result.archivePath;
      expect(archive, p.join(outputRoot, 'archive', 'Runner.xcarchive'));
      expect(
        File(
          p.join(archive, 'Products', 'Applications', 'Runner.app', 'Runner'),
        ).existsSync(),
        isTrue,
      );
      expect(Directory(p.join(archive, 'dSYMs')).existsSync(), isTrue);
      final info =
          PropertyListSerialization.propertyListWithString(
                File(p.join(archive, 'Info.plist')).readAsStringSync(),
              )
              as Map;
      expect(info['ArchiveVersion'], 2);
      expect(info['SchemeName'], 'Runner');
      final properties = info['ApplicationProperties'] as Map;
      expect(properties['ApplicationPath'], 'Applications/Runner.app');
      expect(properties['CFBundleIdentifier'], 'com.example.app');
      expect(properties['CFBundleVersion'], '7');
      expect(properties['Team'], 'TEAM123456');
    },
  );

  test('AC-018-5 dSYMs are attempted for the app, App.framework and dylibs; '
      'failures are listed, not fatal', () async {
    final appPath = app();
    final writer = XcodeArchiveWriter(runner: nativeRunner());
    expect(writer.binariesOf(appPath).map(p.basename), [
      'Runner',
      'App',
      'libFlutterPluginsGenerated.dylib',
    ]);
    final missing = await writer.write(
      appPath: appPath,
      archivePath: p.join(root.path, 'Runner.xcarchive'),
      app: archived,
    );
    // The fixture binaries are not real Mach-O files, so either there is no
    // dsymutil or it rejects them: every binary is reported, nothing throws.
    expect(missing, ['Runner', 'App', 'libFlutterPluginsGenerated.dylib']);
  });

  group('AC-018-4 the export names the role it needs', () {
    test('no App Store Connect key', () {
      expect(
        export(
          credentials: () async => throw const AppleError('not found'),
        ).export(appPath: app(), outputRoot: root.path),
        throwsA(
          isA<XcrossError>().having(
            (e) => e.message,
            'message',
            contains('Admin or App Manager'),
          ),
        ),
      );
    });

    test('an individual key', () {
      final runtime = testRuntime();
      expect(
        export(
          credentials: () async => AscCredentials(
            hostServices: runtime.appleHostServices,
            issuerId: '',
            keyId: 'KEY',
            privateKeyPath: 'AuthKey_KEY.p8',
            keyType: AscKeyType.individual,
          ),
        ).export(appPath: app(), outputRoot: root.path),
        throwsA(
          isA<XcrossError>().having(
            (e) => e.message,
            'message',
            contains('individual key'),
          ),
        ),
      );
    });
  });
}
