import 'dart:io';

import 'package:darwin_sdk_kit/target/iphone/iphone_build_platform.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:studio_ext/shared/events/ndjson_events.dart';
import 'package:test/test.dart';
import 'package:xcross/src/shared/errors/errors.dart';
import 'package:xcross/src/shared/flutter/build/ios_deployment_target.dart';
import 'package:xcross/src/shared/flutter/build/ios_plugins.dart';
import 'package:xcross/src/shared/flutter/swiftpm/pin_conflicts.dart';

import 'swiftpm_test_context.dart';

/// firebase_messaging 17.0.0's ios/firebase_messaging/Package.swift, trimmed:
/// the firebase-ios-sdk pin comes from a typed `let` constant.
@internal
String messagingManifest(String sdkVersion) =>
    '''
// swift-tools-version: 5.9
import PackageDescription

let libraryVersion = "17.0.0"
let firebaseSdkVersion: Version = "$sdkVersion"

let package = Package(
  name: "firebase_messaging",
  platforms: [
    .iOS("15.0")
  ],
  products: [
    .library(name: "firebase-messaging", targets: ["firebase_messaging"])
  ],
  dependencies: [
    .package(url: "https://github.com/firebase/firebase-ios-sdk", exact: firebaseSdkVersion),
    .package(name: "firebase_core", path: "../firebase_core"),
    .package(name: "FlutterFramework", path: "../FlutterFramework"),
  ],
  targets: [
    .target(
      name: "firebase_messaging",
      dependencies: [
        .product(name: "FirebaseMessaging", package: "firebase-ios-sdk"),
        .product(name: "firebase-core", package: "firebase_core"),
        .product(name: "FlutterFramework", package: "FlutterFramework"),
      ]
    )
  ]
)
''';

/// firebase_core 5.1.0's ios/firebase_core/Package.swift, trimmed.
@internal
String coreManifest(String sdkVersion) =>
    '''
// swift-tools-version: 5.9
import PackageDescription

let libraryVersionString = "5.1.0"
let firebaseSdkVersion: Version = "$sdkVersion"

let package = Package(
  name: "firebase_core",
  platforms: [
    .iOS("15.0")
  ],
  products: [
    .library(name: "firebase-core", targets: ["firebase_core", "firebase_core_objc"])
  ],
  dependencies: [
    .package(url: "https://github.com/firebase/firebase-ios-sdk", exact: firebaseSdkVersion),
    .package(name: "FlutterFramework", path: "../FlutterFramework"),
  ],
  targets: [
    .target(
      name: "firebase_core",
      dependencies: [
        .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
        .product(name: "FlutterFramework", package: "FlutterFramework"),
      ]
    ),
  ]
)
''';

@internal
String urlManifest(String name, String requirement) =>
    '''
let package = Package(
  name: "$name",
  dependencies: [
    .package(url: "https://github.com/example/shared-kit.git", $requirement),
  ]
)
''';

@internal
const message =
    'firebase_messaging 17.0.0 pins firebase-ios-sdk 13.0.0; firebase_core '
    '5.1.0 pins 13.1.1. Run "flutter pub upgrade firebase_messaging" so they '
    'agree.';

void main() {
  group('SwiftPmPinConflicts.find', () {
    test('names the plugin with the lower exact pin', () {
      final conflict = SwiftPmPinConflicts.find([
        (
          plugin: 'firebase_core',
          version: '5.1.0',
          manifest: coreManifest('13.1.1'),
        ),
        (
          plugin: 'firebase_messaging',
          version: '17.0.0',
          manifest: messagingManifest('13.0.0'),
        ),
      ]);
      expect(conflict, isNotNull);
      expect(conflict!.package, 'firebase-ios-sdk');
      expect(conflict.upgrade, ['firebase_messaging']);
      expect(conflict.message, message);
    });

    test('plugins that pin the same version agree', () {
      expect(
        SwiftPmPinConflicts.find([
          (
            plugin: 'firebase_core',
            version: '5.1.0',
            manifest: coreManifest('13.1.1'),
          ),
          (
            plugin: 'firebase_messaging',
            version: '17.0.1',
            manifest: messagingManifest('13.1.1'),
          ),
        ]),
        isNull,
      );
    });

    test('groups plugins with the same pin and works without versions', () {
      final conflict = SwiftPmPinConflicts.find([
        (
          plugin: 'a',
          version: null,
          manifest: urlManifest('a', 'exact: "1.0.0"'),
        ),
        (
          plugin: 'b',
          version: '2.0.0',
          manifest: urlManifest('b', 'exact: "1.0.0"'),
        ),
        (
          plugin: 'c',
          version: '3.0.0',
          manifest: urlManifest('c', 'exact: "1.2.0"'),
        ),
      ]);
      expect(
        conflict!.message,
        'a and b 2.0.0 pin shared-kit 1.0.0; c 3.0.0 pins 1.2.0. '
        'Run "flutter pub upgrade a b" so they agree.',
      );
    });

    test("an exact pin outside another plugin's range conflicts", () {
      final conflict = SwiftPmPinConflicts.find([
        (
          plugin: 'old',
          version: '1.0.0',
          manifest: urlManifest('old', 'exact: "1.4.0"'),
        ),
        (
          plugin: 'new',
          version: '2.0.0',
          manifest: urlManifest('new', 'from: "2.0.0"'),
        ),
      ]);
      expect(
        conflict!.message,
        'old 1.0.0 pins shared-kit 1.4.0; new 2.0.0 requires >=2.0.0 <3.0.0. '
        'Run "flutter pub upgrade old" so they agree.',
      );
    });

    test('overlapping ranges and unreadable requirements pass', () {
      expect(
        SwiftPmPinConflicts.find([
          (
            plugin: 'a',
            version: null,
            manifest: urlManifest('a', 'exact: "1.4.0"'),
          ),
          (
            plugin: 'b',
            version: null,
            manifest: urlManifest('b', 'from: "1.2.0"'),
          ),
          (
            plugin: 'c',
            version: null,
            manifest: urlManifest('c', '"1.0.0"..<"2.0.0"'),
          ),
          (
            plugin: 'd',
            version: null,
            manifest: urlManifest('d', 'branch: "main"'),
          ),
          (
            plugin: 'e',
            version: null,
            manifest: urlManifest('e', 'exact: computed()'),
          ),
        ]),
        isNull,
      );
    });

    test('package identity ignores case and .git', () {
      final conflict = SwiftPmPinConflicts.find([
        (
          plugin: 'a',
          version: null,
          manifest:
              '.package(url: "https://github.com/Example/Shared-Kit", exact: "1.0.0")',
        ),
        (
          plugin: 'b',
          version: null,
          manifest:
              '.package(url: "https://github.com/example/shared-kit.git", exact: "1.1.0")',
        ),
      ]);
      expect(conflict!.upgrade, ['a']);
    });
  });

  group('SwiftPmPinConflicts.requirement', () {
    ({VersionConstraint constraint, Version lowest, bool exact})? read(
      String requirement, [
      Map<String, String> constants = const {},
    ]) => SwiftPmPinConflicts.requirement(
      '.package(url: "https://example.com/kit", $requirement)',
      constants,
    );

    test('reads every SwiftPM requirement form', () {
      expect(read('exact: "13.1.1"')!.constraint, Version(13, 1, 1));
      expect(read('.exact("13.1")')!.constraint, Version(13, 1, 0));
      expect(read('exact: sdk', {'sdk': '13.0.0'})!.exact, isTrue);
      expect(
        read('from: "1.2.3"')!.constraint,
        VersionConstraint.parse('>=1.2.3 <2.0.0'),
      );
      expect(
        read('.upToNextMajor(from: "1.2.3")')!.constraint,
        VersionConstraint.parse('>=1.2.3 <2.0.0'),
      );
      expect(
        read('.upToNextMinor(from: "1.2.3")')!.constraint,
        VersionConstraint.parse('>=1.2.3 <1.3.0'),
      );
      expect(
        read('"1.0.0"..<"2.0.0"')!.constraint,
        VersionConstraint.parse('>=1.0.0 <2.0.0'),
      );
      expect(
        read('"1.0.0"..."2.0.0"')!.constraint,
        VersionConstraint.parse('>=1.0.0 <=2.0.0'),
      );
      expect(read('branch: "main"'), isNull);
      expect(read('revision: "abc123"'), isNull);
      expect(read('exact: missing'), isNull);
    });
  });

  group('workspace staging', () {
    late Directory temporary;
    setUp(
      () => temporary = Directory.systemTemp.createTempSync('xcross-pins-'),
    );
    tearDown(() => temporary.deleteSync(recursive: true));

    test('fails before resolve with build.plugin_pin_conflict', () async {
      final runtime = testSwiftPmRuntime();
      IosPlugin plugin(String name, String version, String manifest) {
        final root = p.join(temporary.path, 'pub', '$name-$version');
        File(p.join(root, 'ios', name, 'Package.swift'))
          ..createSync(recursive: true)
          ..writeAsStringSync(manifest);
        File(
          p.join(root, 'pubspec.yaml'),
        ).writeAsStringSync('name: $name\nversion: $version\n');
        return IosPlugin(
          name: name,
          fileSystem: runtime.host.fileSystem,
          packageRoot: root,
        );
      }

      final plugins = [
        plugin('firebase_core', '5.1.0', coreManifest('13.1.1')),
        plugin('firebase_messaging', '17.0.0', messagingManifest('13.0.0')),
      ];
      final staged = {
        for (final plugin in plugins) plugin.name: plugin.swiftPackageDir,
      };

      Object? failure;
      try {
        await runtime.workspaceStager.checkPinConflicts(plugins, staged);
      } on Object catch (error) {
        failure = error;
      }
      expect(failure, isA<XcrossError>());
      final issue = NdjsonEvents.parseCoded('error: $failure');
      expect(issue.code, 'build.plugin_pin_conflict');
      expect(issue.message, message);
      expect(issue.hint, contains('Upgrade the plugin(s) named'));

      // The pins are reported, never rewritten.
      expect(
        File(plugins.last.swiftPackageManifest).readAsStringSync(),
        messagingManifest('13.0.0'),
      );
      await runtime.workspaceStager.checkPinConflicts(plugins.sublist(0, 1), {
        'firebase_core': plugins.first.swiftPackageDir,
      });

      // Staging runs the check on the staged manifests.
      final flutterXcframework = p.join(temporary.path, 'Flutter.xcframework');
      Directory(flutterXcframework).createSync(recursive: true);
      await expectLater(
        runtime.workspaceStager.writeGeneratedPackages(
          outputDir: p.join(temporary.path, 'out'),
          plugins: plugins,
          flutterXcframework: flutterXcframework,
          copyFlutterXcframework: true,
          copyPluginPackages: {for (final plugin in plugins) plugin.name},
          deploymentTarget: const IosDeploymentTarget(
            '15.6',
            platform: IPhoneBuildPlatform(),
          ),
        ),
        throwsA(
          isA<XcrossError>().having(
            (error) => error.message,
            'message',
            startsWith('[build.plugin_pin_conflict] $message'),
          ),
        ),
      );
    });

    test(
      'AC-046-19 sees converted pods remote package dependencies in pin conflict check',
      () async {
        final runtime = testSwiftPmRuntime();
        final coreDir = p.join(temporary.path, 'firebase_core');
        final podDir = p.join(temporary.path, 'pod-custom_analytics');
        Directory(coreDir).createSync(recursive: true);
        Directory(podDir).createSync(recursive: true);

        File(
          p.join(coreDir, 'pubspec.yaml'),
        ).writeAsStringSync('version: 5.1.0\n');
        File(p.join(coreDir, 'Package.swift')).writeAsStringSync('''
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
  name: "firebase_core",
  dependencies: [
    .package(url: "https://github.com/firebase/firebase-ios-sdk", exact: "13.1.1"),
  ]
)
''');

        File(p.join(podDir, 'Package.swift')).writeAsStringSync('''
// swift-tools-version: 5.9
// xcross: pod-converter v1
import PackageDescription
let package = Package(
  name: "pod-custom_analytics",
  dependencies: [
    .package(url: "https://github.com/firebase/firebase-ios-sdk", exact: "13.0.0"),
  ]
)
''');

        final corePlugin = IosPlugin(
          name: 'firebase_core',
          fileSystem: runtime.host.fileSystem,
          packageRoot: coreDir,
        );

        final staged = {
          'firebase_core': coreDir,
          'pod-custom_analytics': podDir,
        };

        Object? failure;
        try {
          await runtime.workspaceStager.checkPinConflicts([corePlugin], staged);
        } on Object catch (error) {
          failure = error;
        }

        expect(failure, isA<XcrossError>());
        final issue = NdjsonEvents.parseCoded('error: $failure');
        expect(issue.code, 'build.plugin_pin_conflict');
        expect(issue.message, contains('firebase-ios-sdk'));
        expect(
          issue.message,
          contains('pod-custom_analytics pins firebase-ios-sdk 13.0.0'),
        );
        expect(issue.message, contains('firebase_core 5.1.0 pins 13.1.1'));
      },
    );
  });
}
