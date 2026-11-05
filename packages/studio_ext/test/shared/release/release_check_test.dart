// studio: 018 — `xcross release check` (specs/018-app-store-build).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/release/release_check_command.dart';
import 'package:studio_ext/src/shared/inspect/inspect_source.dart';
import 'package:studio_ext/src/shared/release/macho_build_version.dart';
import 'package:studio_ext/src/shared/release/release_checks.dart';
import 'package:test/test.dart';

import '../../support/fixture_builder.dart';
import '../../support/test_file_system.dart';

const _bundleId = 'com.example.store';

/// A thin arm64 executable with `LC_BUILD_VERSION` (iOS, [minos], [sdk]),
/// an optional code signature and extra [body] bytes (symbol names).
Uint8List _executable({
  String sdk = '26.1',
  String minos = '13.0',
  Uint8List? signature,
  String body = '',
}) {
  int encode(String version) {
    final parts = [...version.split('.').map(int.parse), 0, 0];
    return parts[0] << 16 | parts[1] << 8 | parts[2];
  }

  const le = Endian.little;
  final bodyBytes = Uint8List.fromList([...utf8.encode(body), 0, 0, 0, 0]);
  final commands = signature == null ? 1 : 2;
  final commandsSize = 24 + (signature == null ? 0 : 16);
  final bodyStart = 32 + commandsSize;
  final signatureOffset = (bodyStart + bodyBytes.length + 15) ~/ 16 * 16;
  final total = signature == null
      ? bodyStart + bodyBytes.length
      : signatureOffset + signature.length;
  final bytes = Uint8List(total);
  final data = ByteData.sublistView(bytes)
    ..setUint32(0, 0xfeedfacf, le)
    ..setInt32(4, 0x0100000c, le)
    ..setUint32(12, 2, le)
    ..setUint32(16, commands, le)
    ..setUint32(20, commandsSize, le)
    ..setUint32(32, 0x32, le)
    ..setUint32(36, 24, le)
    ..setUint32(40, 2, le)
    ..setUint32(44, encode(minos), le)
    ..setUint32(48, encode(sdk), le);
  if (signature != null) {
    data
      ..setUint32(56, 0x1d, le)
      ..setUint32(60, 16, le)
      ..setUint32(64, signatureOffset, le)
      ..setUint32(68, signature.length, le);
    bytes.setRange(signatureOffset, total, signature);
  }
  bytes.setRange(bodyStart, bodyStart + bodyBytes.length, bodyBytes);
  return bytes;
}

Uint8List _signature(Map<String, Object> entitlements) => codeSignature(
  identifier: _bundleId,
  teamId: 'TEAMID1234',
  entitlements: entitlements,
  cms: CmsBlob.signed,
);

Uint8List _appStoreProfile({DateTime? expires, bool development = false}) =>
    mobileProvision(
      profilePlist(
        bundleId: _bundleId,
        getTaskAllow: development,
        devices: development,
        expires: expires ?? DateTime.utc(2099),
      ),
    );

/// Minimal PNG: signature, IHDR (no CRC check needed), IEND.
Uint8List _png({int size = 1024, int colorType = 2}) {
  final ihdr = ByteData(13)
    ..setUint32(0, size)
    ..setUint32(4, size)
    ..setUint8(8, 8)
    ..setUint8(9, colorType);
  return Uint8List.fromList([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
    0, 0, 0, 13, ...ascii.encode('IHDR'),
    ...ihdr.buffer.asUint8List(), 0, 0, 0, 0, //
    0, 0, 0, 0, ...ascii.encode('IEND'), 0, 0, 0, 0,
  ]);
}

Map<String, Object> _infoPlist([Map<String, Object> extra = const {}]) => {
  ...baseInfoPlist(bundleId: _bundleId),
  'DTCompiler': 'com.apple.compilers.llvm.clang.1_0',
  'DTPlatformBuild': '24A94232',
  'DTPlatformName': 'iphoneos',
  'DTPlatformVersion': '26.1',
  'DTSDKBuild': '24A94232',
  'DTSDKName': 'iphoneos26.1',
  'DTXcode': '2610',
  'DTXcodeBuild': '17B55',
  'ITSAppUsesNonExemptEncryption': false,
  'UILaunchScreen': <String, Object>{'UIColorName': 'LaunchBackground'},
  'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait'],
  ...extra,
};

Uint8List _manifest(List<String> categories) => xmlPlist({
  'NSPrivacyAccessedAPITypes': [
    for (final category in categories)
      <String, Object>{
        'NSPrivacyAccessedAPIType': category,
        'NSPrivacyAccessedAPITypeReasons': ['CA92.1'],
      },
  ],
  'NSPrivacyCollectedDataTypes': <Object>[],
  'NSPrivacyTracking': false,
});

/// A binary that loads [libraries] (`@rpath/libswiftCore.dylib`, …).
Uint8List _loading(List<String> libraries) {
  const le = Endian.little;
  final commands = <Uint8List>[];
  for (final library in libraries) {
    final name = utf8.encode(library);
    final size = (24 + name.length + 1 + 7) ~/ 8 * 8;
    final command = Uint8List(size);
    ByteData.sublistView(command)
      ..setUint32(0, 0xc, le)
      ..setUint32(4, size, le)
      ..setUint32(8, 24, le);
    command.setRange(24, 24 + name.length, name);
    commands.add(command);
  }
  final total = commands.fold<int>(0, (sum, c) => sum + c.length);
  final bytes = Uint8List(32 + total);
  ByteData.sublistView(bytes)
    ..setUint32(0, 0xfeedfacf, le)
    ..setInt32(4, 0x0100000c, le)
    ..setUint32(12, 2, le)
    ..setUint32(16, commands.length, le)
    ..setUint32(20, total, le);
  var offset = 32;
  for (final command in commands) {
    bytes.setRange(offset, offset + command.length, command);
    offset += command.length;
  }
  return bytes;
}

/// A clean App Store build; tests change one thing at a time.
Map<String, Uint8List> _appStoreApp({
  Map<String, Object> info = const {},
  Map<String, Object>? entitlements,
  String runnerBody = '',
  String sdk = '26.1',
}) => {
  'Info.plist': xmlPlist(_infoPlist(info)),
  'Runner': _executable(
    sdk: sdk,
    body: runnerBody,
    signature: _signature(
      entitlements ??
          {
            'application-identifier': 'TEAMID1234.$_bundleId',
            'aps-environment': 'production',
          },
    ),
  ),
  '_CodeSignature/CodeResources': xmlPlist({'files': <String, Object>{}}),
  'embedded.mobileprovision': _appStoreProfile(),
  'PrivacyInfo.xcprivacy': _manifest([
    'NSPrivacyAccessedAPICategoryUserDefaults',
  ]),
  'Frameworks/Flutter.framework/Flutter': machO(seed: 3),
  'Frameworks/Flutter.framework/Info.plist': xmlPlist({
    'CFBundleExecutable': 'Flutter',
    'CFBundleIdentifier': 'io.flutter.flutter',
  }),
  'Frameworks/Flutter.framework/PrivacyInfo.xcprivacy': _manifest(const []),
};

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('release-check-'));
  tearDown(() => temp.deleteSync(recursive: true));

  String writeApp(Map<String, Uint8List> files, {String name = 'Runner.app'}) =>
      FixtureBundle(name, files).writeApp(temp);

  String writeProject({
    List<String> plugins = const [],
    String bundleId = _bundleId,
    Uint8List? icon,
    bool iconEntry = true,
  }) {
    final root = Directory(p.join(temp.path, 'project'))..createSync();
    void write(String relative, List<int> bytes) =>
        File(p.joinAll([root.path, ...relative.split('/')]))
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(bytes);
    write(
      'pubspec.yaml',
      utf8.encode(
        'name: app\ndependencies:\n  flutter:\n    sdk: flutter\n'
        '${plugins.map((name) => '  $name: any\n').join()}'
        'dev_dependencies:\n  lints: any\n',
      ),
    );
    write(
      'ios/Runner.xcodeproj/project.pbxproj',
      utf8.encode(
        '{\n  PRODUCT_BUNDLE_IDENTIFIER = $bundleId;\n'
        '  PRODUCT_BUNDLE_IDENTIFIER = $bundleId.RunnerTests;\n}\n',
      ),
    );
    write(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json',
      utf8.encode(
        jsonEncode({
          'images': [
            if (iconEntry)
              {
                'filename': 'Icon-1024.png',
                'idiom': 'universal',
                'platform': 'ios',
                'size': '1024x1024',
              },
          ],
        }),
      ),
    );
    write(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-1024.png',
      icon ?? _png(),
    );
    return root.path;
  }

  ReleaseReport check(String appPath, {String? project}) {
    final source = InspectSource.open(const IoFileSystem(), appPath);
    try {
      return runReleaseChecks(
        source,
        now: DateTime.utc(2026, 11, 3),
        project: project == null
            ? null
            : ReleaseProject(
                fileSystem: const IoFileSystem(),
                paths: p.context,
                root: project,
              ),
      );
    } finally {
      source.close();
    }
  }

  List<String> codes(ReleaseReport report, [ReleaseSeverity? severity]) => [
    for (final issue in report.issues)
      if (severity == null || issue.severity == severity) issue.code,
  ];

  test('a clean App Store build has no errors or warnings', () {
    final report = check(writeApp(_appStoreApp()), project: writeProject());
    expect(codes(report, ReleaseSeverity.error), isEmpty);
    expect(codes(report, ReleaseSeverity.warning), isEmpty);
    expect(report.configuration['bundleId'], _bundleId);
    expect(report.configuration['sdk'], '26.1');
    expect((report.configuration['profile']! as Map)['kind'], 'app-store');
  });

  group('AC-018-16 SwiftSupport', () {
    String ipa(
      Map<String, Uint8List> app, {
      Map<String, Uint8List> outside = const {},
    }) => FixtureBundle(
      'Runner.app',
      app,
    ).writeIpa(temp, 'a.ipa', outside: outside);

    ReleaseReport checkIpa(String path) {
      final source = InspectSource.open(const IoFileSystem(), path);
      try {
        return runReleaseChecks(source, now: DateTime.utc(2026, 11, 3));
      } finally {
        source.close();
      }
    }

    final swiftApp = {
      ..._appStoreApp(),
      'Frameworks/Facebook.framework/Facebook': _loading([
        '@rpath/libswiftCore.dylib',
        '/usr/lib/swift/libswiftFoundation.dylib',
        '@rpath/libswiftDispatch.dylib',
      ]),
      'Frameworks/Facebook.framework/Info.plist': xmlPlist({
        'CFBundleExecutable': 'Facebook',
        'CFBundleIdentifier': 'com.facebook.sdk',
      }),
    };

    test('Swift libraries but no SwiftSupport: Apple refuses it (90426)', () {
      final report = checkIpa(ipa(swiftApp));
      expect(codes(report, ReleaseSeverity.error), [
        'release.swift_support_missing',
      ]);
      expect(
        report.issues
            .firstWhere((i) => i.severity != ReleaseSeverity.info)
            .message,
        allOf(contains('libswiftCore.dylib'), contains('90426')),
      );
    });

    test('SwiftSupport with every library the app loads through the rpath', () {
      final report = checkIpa(
        ipa(
          swiftApp,
          outside: {
            'SwiftSupport/iphoneos/libswiftCore.dylib': machO(),
            'SwiftSupport/iphoneos/libswiftDispatch.dylib': machO(seed: 2),
          },
        ),
      );
      expect(codes(report), isNot(contains('release.swift_support_missing')));
    });

    test('a library left out of SwiftSupport is named', () {
      final report = checkIpa(
        ipa(
          swiftApp,
          outside: {'SwiftSupport/iphoneos/libswiftCore.dylib': machO()},
        ),
      );
      expect(codes(report, ReleaseSeverity.error), [
        'release.swift_support_missing',
      ]);
      expect(
        report.issues
            .firstWhere((i) => i.severity != ReleaseSeverity.info)
            .message,
        contains('libswiftDispatch.dylib'),
      );
    });

    test('an app that loads no Swift library needs no SwiftSupport', () {
      expect(
        codes(checkIpa(ipa(_appStoreApp()))),
        isNot(contains('release.swift_support_missing')),
      );
    });

    test('a .app directory has no archive root to look in', () {
      expect(
        codes(check(writeApp(swiftApp))),
        isNot(contains('release.swift_support_missing')),
      );
    });
  });

  group('AC-018-17 purpose strings found in the code', () {
    test(
      'requestAlwaysAuthorization needs the always-and-when-in-use key (90683)',
      () {
        final files = _appStoreApp(
          info: {
            'NSLocationWhenInUseUsageDescription': 'To show nearby clinics.',
          },
          runnerBody: 'requestAlwaysAuthorization',
        );
        final report = check(writeApp(files));
        expect(codes(report, ReleaseSeverity.warning), [
          'release.permission_missing_for_call',
        ]);
        expect(
          report.issues
              .firstWhere((i) => i.severity != ReleaseSeverity.info)
              .message,
          allOf(
            contains('NSLocationAlwaysAndWhenInUseUsageDescription'),
            contains('90683'),
          ),
        );
      },
    );

    test('with both keys there is nothing to say', () {
      final files = _appStoreApp(
        info: {
          'NSLocationWhenInUseUsageDescription': 'To show nearby clinics.',
          'NSLocationAlwaysAndWhenInUseUsageDescription':
              'To remind you near a clinic.',
        },
        runnerBody: 'requestAlwaysAuthorization',
      );
      expect(
        codes(check(writeApp(files))),
        isNot(contains('release.permission_missing_for_call')),
      );
    });

    test('a call in a framework counts the same', () {
      final files = _appStoreApp()
        ..['Frameworks/Geo.framework/Geo'] = _executable(
          body: 'requestWhenInUseAuthorization',
        )
        ..['Frameworks/Geo.framework/Info.plist'] = xmlPlist({
          'CFBundleExecutable': 'Geo',
          'CFBundleIdentifier': 'com.example.geo',
        });
      final report = check(writeApp(files));
      expect(
        report.issues
            .where((i) => i.code == 'release.permission_missing_for_call')
            .single
            .message,
        contains('Frameworks/Geo.framework/Geo'),
      );
    });
  });

  group('AC-018-9 signing', () {
    test('an unsigned app', () {
      final files = _appStoreApp()
        ..remove('_CodeSignature/CodeResources')
        ..['Runner'] = _executable();
      expect(codes(check(writeApp(files))), contains('release.not_signed'));
    });

    test('a development profile with get-task-allow and development push', () {
      final files = _appStoreApp(
        entitlements: {
          'application-identifier': 'TEAMID1234.$_bundleId',
          'aps-environment': 'development',
          'get-task-allow': true,
        },
      )..['embedded.mobileprovision'] = _appStoreProfile(development: true);
      expect(
        codes(check(writeApp(files)), ReleaseSeverity.error),
        containsAll([
          'release.profile_not_app_store',
          'release.get_task_allow',
          'release.aps_development',
        ]),
      );
    });

    test('an expired profile', () {
      final files = _appStoreApp()
        ..['embedded.mobileprovision'] = _appStoreProfile(
          expires: DateTime.utc(2025),
        );
      expect(
        codes(check(writeApp(files))),
        contains('release.profile_expired'),
      );
    });

    test('an extension with a development profile', () {
      final files = {
        ..._appStoreApp(),
        'PlugIns/Share.appex/Info.plist': xmlPlist({
          'CFBundleExecutable': 'Share',
          'CFBundleIdentifier': '$_bundleId.Share',
          'NSExtension': <String, Object>{
            'NSExtensionPointIdentifier': 'com.apple.share-services',
          },
        }),
        'PlugIns/Share.appex/Share': _executable(
          signature: _signature({'get-task-allow': true}),
        ),
        'PlugIns/Share.appex/embedded.mobileprovision': _appStoreProfile(
          development: true,
        ),
      };
      final issue = check(
        writeApp(files),
      ).issues.firstWhere((i) => i.code == 'release.extension_profile');
      expect(issue.path, 'PlugIns/Share.appex');
      expect(issue.severity, ReleaseSeverity.error);
    });
  });

  group('AC-018-10 toolchain and identity', () {
    test('LC_BUILD_VERSION is read; an SDK below 26 is an error', () {
      expect(
        MachOBuildVersion.read(_executable(sdk: '18.5', minos: '12.0'))!.sdk,
        '18.5',
      );
      expect(MachOBuildVersion.format(26 << 16 | 1 << 8 | 2), '26.1.2');
      final report = check(writeApp(_appStoreApp(sdk: '18.5')));
      expect(
        codes(report, ReleaseSeverity.error),
        contains('release.sdk_too_old'),
      );
    });

    test('missing DT keys, an old deployment target, a bad version', () {
      final info = _infoPlist({
        'MinimumOSVersion': '12.0',
        'CFBundleShortVersionString': '1.0.0.1',
      })..remove('DTXcodeBuild');
      final files = _appStoreApp()..['Info.plist'] = xmlPlist(info);
      final report = check(writeApp(files));
      expect(
        codes(report),
        containsAll([
          'release.dt_keys_missing',
          'release.deployment_target',
          'release.version_invalid',
        ]),
      );
      expect(
        report.issues
            .firstWhere((i) => i.code == 'release.dt_keys_missing')
            .message,
        contains('DTXcodeBuild'),
      );
    });

    test('the signed ID differs from the project', () {
      final report = check(
        writeApp(_appStoreApp()),
        project: writeProject(bundleId: 'com.example.other'),
      );
      expect(codes(report), contains('release.bundle_id_mismatch'));
    });

    test('without a project, project checks are skipped with an info line', () {
      final report = check(writeApp(_appStoreApp()));
      expect(
        codes(report, ReleaseSeverity.info),
        contains('release.project_unknown'),
      );
    });
  });

  group('AC-018-11 permissions', () {
    test('a plugin without its usage description', () {
      final report = check(
        writeApp(_appStoreApp()),
        project: writeProject(plugins: ['image_picker']),
      );
      final missing = [
        for (final issue in report.issues)
          if (issue.code == 'release.permission_missing') issue.message,
      ];
      expect(missing, hasLength(2));
      expect(missing.join(), contains('NSCameraUsageDescription'));
    });

    test('placeholders, ATS and background modes', () {
      final report = check(
        writeApp(
          _appStoreApp(
            info: {
              'NSCameraUsageDescription': 'TODO',
              'NSPhotoLibraryUsageDescription':
                  'Choose a photo to attach to your order.',
              'NSAppTransportSecurity': <String, Object>{
                'NSAllowsArbitraryLoads': true,
              },
              'UIBackgroundModes': ['remote-notification', 'audio'],
            },
          ),
        ),
        project: writeProject(plugins: ['image_picker', 'firebase_messaging']),
      );
      expect(codes(report), isNot(contains('release.permission_missing')));
      expect(
        codes(report, ReleaseSeverity.warning),
        containsAll([
          'release.permission_placeholder',
          'release.ats_arbitrary_loads',
          'release.background_mode',
        ]),
      );
      final modes = report.issues.where(
        (i) => i.code == 'release.background_mode',
      );
      expect(
        modes.firstWhere((i) => i.message.contains('remote-notification')),
        isA<ReleaseIssue>().having(
          (i) => i.severity,
          'severity',
          ReleaseSeverity.info,
        ),
      );
    });

    test('pubspec dependencies are read without a YAML parser', () {
      expect(
        ReleaseProject.directDependencies(
          'name: a\ndependencies:\n  flutter:\n    sdk: flutter\n'
          '  camera: ^1.0.0 # comment\ndev_dependencies:\n  test: any\n',
        ),
        {'flutter', 'camera'},
      );
    });
  });

  group('AC-018-12 privacy', () {
    test('missing manifests, an undeclared required-reason API', () {
      final files = _appStoreApp(runnerBody: 'NSFileCreationDate')
        ..remove('PrivacyInfo.xcprivacy')
        ..remove('Frameworks/Flutter.framework/PrivacyInfo.xcprivacy');
      final report = check(writeApp(files));
      final manifests = report.issues
          .where((i) => i.code == 'release.privacy_manifest_missing')
          .map((i) => i.path)
          .toList();
      expect(
        manifests,
        containsAll(['PrivacyInfo.xcprivacy', 'Frameworks/Flutter.framework']),
      );
      final reason = report.issues.firstWhere(
        (i) => i.code == 'release.required_reason_undeclared',
      );
      expect(reason.message, contains('FileTimestamp'));
      expect(reason.path, 'Runner');
    });

    // fluttertoast 8.2.14 ships a manifest and an older draft left it out, so
    // "update the plugin" sent the developer the wrong way (2026-11-05).
    test('AC-018-12 a listed plugin without a manifest: with an override the '
        'hint asks for a new draft, without one for an update', () {
      String hint(String project) =>
          check(writeApp(_appStoreApp()), project: project).issues
              .firstWhere(
                (i) =>
                    i.code == 'release.privacy_manifest_missing' &&
                    i.message.contains('fluttertoast'),
              )
              .hint!;

      final project = writeProject(plugins: ['fluttertoast']);
      expect(hint(project), startsWith('Update fluttertoast'));

      Directory(
        p.join(project, 'xcross_overrides', 'fluttertoast', '8.2.14'),
      ).createSync(recursive: true);
      expect(
        hint(project),
        contains('xcross plugin shim fluttertoast --force'),
      );
    });

    test('a declared category is not reported', () {
      final files = _appStoreApp(runnerBody: 'NSFileCreationDate')
        ..['PrivacyInfo.xcprivacy'] = _manifest([
          'NSPrivacyAccessedAPICategoryFileTimestamp',
        ]);
      expect(
        codes(check(writeApp(files))),
        isNot(contains('release.required_reason_undeclared')),
      );
    });

    test('export compliance unset; secrets in the bundle', () {
      final info = _infoPlist()..remove('ITSAppUsesNonExemptEncryption');
      final files = _appStoreApp()
        ..['Info.plist'] = xmlPlist(info)
        ..['flutter_assets/config.json'] = utf8.encode(
          r'{"key": "-----BEGIN PRIVATE KEY-----\nMIIB"}',
        )
        ..['flutter_assets/firebase.json'] = utf8.encode(
          '{"apiKey": "$plantedApiKey"}',
        )
        ..['AuthKey_ABC.p8'] = utf8.encode('secret');
      final report = check(writeApp(files));
      expect(codes(report), contains('release.encryption_unset'));
      final secrets = report.issues
          .where((i) => i.code == 'release.secret_in_bundle')
          .map((i) => i.path)
          .toList();
      expect(
        secrets,
        unorderedEquals(['AuthKey_ABC.p8', 'flutter_assets/config.json']),
      );
      expect(jsonEncode(report.toJson()), isNot(contains('MIIB')));
    });
  });

  group('AC-018-13 store assets', () {
    test('an icon with alpha, or none at 1024 px', () {
      final app = writeApp(_appStoreApp());
      expect(
        check(
          app,
          project: writeProject(icon: _png(colorType: 6)),
        ).issues.firstWhere((i) => i.code == 'release.marketing_icon').message,
        contains('alpha'),
      );
      Directory(p.join(temp.path, 'project')).deleteSync(recursive: true);
      expect(
        codes(check(app, project: writeProject(iconEntry: false))),
        contains('release.marketing_icon'),
      );
      expect(ReleaseChecker.pngProblem(_png(size: 512)), contains('512'));
    });

    test('no launch screen; iPad without every orientation', () {
      final info = _infoPlist({
        'UIDeviceFamily': [1, 2],
      })..remove('UILaunchScreen');
      final report = check(
        writeApp(_appStoreApp()..['Info.plist'] = xmlPlist(info)),
      );
      expect(
        codes(report, ReleaseSeverity.error),
        containsAll([
          'release.launch_screen_missing',
          'release.ipad_multitasking',
        ]),
      );
      final fullScreen = check(
        writeApp(
          _appStoreApp(
            info: {
              'UIDeviceFamily': [1, 2],
              'UIRequiresFullScreen': true,
            },
          ),
          name: 'Full.app',
        ),
      );
      expect(codes(fullScreen), isNot(contains('release.ipad_multitasking')));
    });
  });

  group('AC-018-14 the command', () {
    late StringBuffer out;
    setUp(() => out = StringBuffer());

    Future<void> run(List<String> args, {required String cwd}) =>
        (CommandRunner<void>('xcross', 'test')..addCommand(
              ReleaseCommand(
                fileSystem: const IoFileSystem(),
                paths: p.context,
                currentDirectory: () => cwd,
                write: out.write,
                now: () => DateTime.utc(2026, 11, 3),
              ),
            ))
            .run(['release', 'check', ...args]);

    test('--json prints one release_check object', () async {
      final project = writeProject();
      final ipa = FixtureBundle(
        'Runner.app',
        _appStoreApp(),
      ).writeIpa(Directory(project), 'app.ipa');
      await run([ipa, '--json'], cwd: project);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(json['v'], 1);
      expect(json['type'], 'release_check');
      expect(json['input'], 'app.ipa');
      expect(json['errors'], 0);
      expect(json['issues'], isA<List<Object?>>());
      expect((json['configuration']! as Map)['bundleId'], _bundleId);
    });

    test(
      '--online without a key is one warning and says it was not asked',
      () async {
        final project = writeProject();
        final ipa = FixtureBundle(
          'Runner.app',
          _appStoreApp(),
        ).writeIpa(Directory(project), 'app.ipa');
        await run([ipa, '--online', '--json'], cwd: project);
        final json = jsonDecode(out.toString()) as Map<String, Object?>;
        expect(json['errors'], 0);
        expect((json['configuration']! as Map)['online'], isFalse);
        expect([
          for (final i in json['issues']! as List) (i as Map)['code'],
        ], contains('release.asc_unavailable'));
      },
    );

    test('the newest IPA under build/xcross-ios/ipa is the default; errors '
        'exit 1 after the report', () async {
      final project = writeProject();
      final ipaDir = Directory(p.join(project, 'build', 'xcross-ios', 'ipa'))
        ..createSync(recursive: true);
      FixtureBundle(
        'Runner.app',
        _appStoreApp(sdk: '18.0'),
      ).writeIpa(ipaDir, 'app.ipa');
      await expectLater(
        run([], cwd: project),
        throwsA(
          isA<CliError>().having(
            (e) => e.message,
            'message',
            contains('[release.check_failed]'),
          ),
        ),
      );
      expect(out.toString(), contains('Release check: app.ipa'));
      expect(out.toString(), contains('error [release.sdk_too_old]'));
      expect(out.toString(), contains('  hint: '));
    });

    test('a clean build says so', () async {
      final project = writeProject();
      final app = writeApp(_appStoreApp());
      await run([app, '--project', project], cwd: temp.path);
      expect(out.toString(), contains('Bundle ID     $_bundleId'));
      expect(out.toString(), contains('No problems found.'));
    });

    test('no IPA to check is a coded error', () {
      expect(
        run([], cwd: temp.path),
        throwsA(
          isA<CliError>().having(
            (e) => e.message,
            'message',
            contains('[release.no_input]'),
          ),
        ),
      );
    });
  });
}
