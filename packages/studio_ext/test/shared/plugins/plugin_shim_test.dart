// studio: 006 — `xcross plugin list|shim`: podspec → Package.swift draft.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/plugins/plugin_command.dart';
import 'package:studio_ext/src/shared/plugins/package_swift_draft.dart';
import 'package:studio_ext/src/shared/plugins/podspec.dart';
import 'package:test/test.dart';

import '../../support/test_file_system.dart';

const _objcPodspec = '''
#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'legacy_maps'
  s.version          = '0.0.1'
  s.summary          = 'A plugin # with a hash in a string'
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.dependency 'GoogleMaps', '~> 8.4'
  s.dependency 'Google-Maps-iOS-Utils', '~> 5.0.0'
  s.dependency 'SomeVendorSDK'
  s.frameworks = 'CoreLocation', 'UIKit'
  s.libraries = 'z'
  s.platform = :ios, '12.0'
  s.osx.dependency 'FlutterMacOS'
  s.resource_bundles = {'legacy_maps_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
''';

const _mixedPodspec = '''
Pod::Spec.new do |spec|
  spec.name = "old_swift_plugin"
  spec.version = "1.2.0"
  spec.source_files = ['Classes/**/*.{h,m}', 'Classes/**/*.swift']
  spec.dependency "Flutter"
  spec.dependency "PusherSwift", ">= 10.1"
  spec.ios.deployment_target = "11.0"
  spec.swift_version = "5.0"
end
''';

void main() {
  group('AC-006-8 podspec parsing', () {
    test('declarative forms are read; macOS lines and comments ignored', () {
      final spec = Podspec.parse(_objcPodspec);
      expect(spec.name, 'legacy_maps');
      expect(spec.version, '0.0.1');
      expect(spec.sourceFiles, ['Classes/**/*']);
      expect(spec.publicHeaderFiles, ['Classes/**/*.h']);
      expect(spec.dependencies.map((d) => '$d'), [
        'Flutter',
        'GoogleMaps (~> 8.4)',
        'Google-Maps-iOS-Utils (~> 5.0.0)',
        'SomeVendorSDK',
      ]);
      expect(spec.frameworks, ['CoreLocation', 'UIKit']);
      expect(spec.libraries, ['z']);
      expect(spec.deploymentTarget, '12.0');
      expect(spec.resourceBundles, {
        'legacy_maps_privacy': ['Resources/PrivacyInfo.xcprivacy'],
      });

      final mixed = Podspec.parse(_mixedPodspec);
      expect(mixed.name, 'old_swift_plugin');
      expect(mixed.version, '1.2.0', reason: 'swift_version is not version');
      expect(mixed.sourceFiles, ['Classes/**/*.{h,m}', 'Classes/**/*.swift']);
      expect(mixed.deploymentTarget, '11.0');
      expect(mixed.dependencies.last.requirement, '>= 10.1');
    });

    test('CocoaPods requirements map to SwiftPM requirements', () {
      expect(swiftRequirement('~> 8.4'), '.upToNextMajor(from: "8.4.0")');
      expect(swiftRequirement('~> 5.0.0'), '.upToNextMinor(from: "5.0.0")');
      expect(swiftRequirement('>= 10.1'), 'from: "10.1.0"');
      expect(swiftRequirement('2.3'), 'exact: "2.3.0"');
      expect(swiftRequirement(null), contains('TODO'));
      expect(
        knownPackageFor('Firebase/Messaging')?.product,
        'FirebaseMessaging',
      );
      expect(knownPackageFor('FirebaseCore')?.package, 'firebase-ios-sdk');
      expect(knownPackageFor('SomeVendorSDK'), isNull);
    });
  });

  group('AC-006-9 Package.swift draft', () {
    test('Objective-C plugin: one target, headers, pods, linker, notes', () {
      final draft = draftPackageSwift(
        plugin: 'legacy_maps',
        spec: Podspec.parse(_objcPodspec),
        files: const [
          'Classes/LegacyMapsPlugin.h',
          'Classes/LegacyMapsPlugin.m',
          'Resources/PrivacyInfo.xcprivacy',
          'legacy_maps.podspec',
        ],
        pluginVersion: '0.0.1',
      );
      final text = draft.text;
      expect(text, startsWith('// swift-tools-version: 5.9\n'));
      expect(text, contains('platforms: [.iOS("12.0")]'));
      expect(
        text,
        contains('.library(name: "legacy-maps", targets: ["legacy_maps"])'),
      );
      expect(
        text,
        contains(
          '.package(url: "https://github.com/googlemaps/ios-maps-sdk", '
          '.upToNextMajor(from: "8.4.0"))',
        ),
      );
      expect(
        text,
        contains(
          '.product(name: "GoogleMapsUtils", '
          'package: "google-maps-ios-utils")',
        ),
      );
      expect(text, contains("// TODO: pod 'SomeVendorSDK'"));
      expect(text, contains('path: "Classes"'));
      expect(text, contains('publicHeadersPath: "."'));
      expect(text, contains('.linkedFramework("CoreLocation")'));
      expect(text, contains('.linkedLibrary("z")'));
      expect(
        RegExp(r',\s*\n\s*\),').hasMatch(text),
        isFalse,
        reason: 'no trailing comma before a closing parenthesis',
      );
      expect(text, isNot(contains('FlutterMacOS')));
      expect(text, isNot(contains('"legacy_maps_swift"')));
      expect(draft.notes, hasLength(2));
      expect(draft.notes.join(), contains('SomeVendorSDK'));
      expect(draft.notes.join(), contains('Resources/PrivacyInfo.xcprivacy'));
    });

    test('Swift + Objective-C plugin: split targets with excludes', () {
      final draft = draftPackageSwift(
        plugin: 'old_swift_plugin',
        spec: Podspec.parse(_mixedPodspec),
        files: const [
          'Classes/OldSwiftPlugin.h',
          'Classes/OldSwiftPlugin.m',
          'Classes/SwiftOldSwiftPlugin.swift',
        ],
      );
      final text = draft.text;
      expect(text, contains('name: "old_swift_plugin_swift"'));
      expect(text, contains('"old_swift_plugin_swift",'));
      expect(text, contains('"SwiftOldSwiftPlugin.swift"'));
      expect(text, contains('"OldSwiftPlugin.m"'));
      expect(text, contains('pusher-websocket-swift'));
      expect(text, contains('from: "10.1.0"'));
      expect(draft.notes.single, contains('@import old_swift_plugin_swift;'));
    });
  });

  test('AC-006-9 public headers in include/ set publicHeadersPath', () {
    final draft = draftPackageSwift(
      plugin: 'spm_layout',
      spec: Podspec.parse('''
Pod::Spec.new do |s|
  s.name = 'spm_layout'
  s.source_files = 'spm_layout/Sources/spm_layout/**/*.{h,m}'
  s.public_header_files = 'spm_layout/Sources/spm_layout/include/**/*.h'
  s.dependency 'Flutter'
end
'''),
      files: const [
        'spm_layout/Sources/spm_layout/Plugin.m',
        'spm_layout/Sources/spm_layout/include/spm_layout/Plugin.h',
      ],
    );
    expect(draft.text, contains('path: "spm_layout/Sources/spm_layout"'));
    expect(draft.text, contains('publicHeadersPath: "include"'));
    expect(draft.notes, isEmpty);
  });

  group('AC-006-10 xcross plugin list / shim', () {
    late Directory temp;
    late String project;
    late List<String> out;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('xcross_plugin_shim_');
      project = p.join(temp.path, 'app');
      out = [];
      final pub = p.join(temp.path, 'pub');
      void plugin(String name, String version, Map<String, String> files) {
        final root = p.join(pub, name);
        File(p.join(root, 'pubspec.yaml'))
          ..createSync(recursive: true)
          ..writeAsStringSync('name: $name\nversion: $version\n');
        for (final MapEntry(:key, :value) in files.entries) {
          File(p.join(root, 'ios', key))
            ..createSync(recursive: true)
            ..writeAsStringSync(value);
        }
      }

      plugin('legacy_maps', '0.0.1', {
        'legacy_maps.podspec': _objcPodspec,
        'Classes/LegacyMapsPlugin.h': '',
        'Classes/LegacyMapsPlugin.m': '',
      });
      plugin('modern_plugin', '2.0.0', {
        'modern_plugin.podspec': _objcPodspec,
        'modern_plugin/Package.swift': '// swift-tools-version: 5.9',
      });
      File(p.join(project, '.flutter-plugins-dependencies'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'plugins': {
              'ios': [
                {'name': 'modern_plugin', 'path': p.join(pub, 'modern_plugin')},
                {'name': 'legacy_maps', 'path': p.join(pub, 'legacy_maps')},
              ],
            },
          }),
        );
    });
    tearDown(() => temp.deleteSync(recursive: true));

    CommandRunner<void> runner() =>
        CommandRunner<void>('xcross', 'test')..addCommand(
          PluginCommand(
            fileSystem: const IoFileSystem(),
            paths: p.context,
            write: out.add,
            home: p.join(temp.path, 'home'),
          ),
        );

    test('list shows how each plugin is built', () async {
      await runner().run(['plugin', 'list', '--project', project]);
      final text = out.join();
      expect(text, contains('✖ legacy_maps 0.0.1  (podspec only)'));
      expect(text, contains('✔ modern_plugin 2.0.0  (swiftpm)'));
      expect(text, contains('xcross plugin shim <plugin>'));
    });

    test('shim writes the versioned draft and refuses to overwrite', () async {
      await runner().run([
        'plugin',
        'shim',
        'legacy_maps',
        '--project',
        project,
      ]);
      final draft = File(
        p.join(
          project,
          'xcross_overrides',
          'legacy_maps',
          '0.0.1',
          'Package.swift',
        ),
      );
      expect(draft.existsSync(), isTrue);
      expect(draft.readAsStringSync(), contains('DRAFT generated'));
      expect(out.join(), contains('Review before building:'));
      expect(out.join(), contains('SomeVendorSDK'));

      await expectLater(
        runner().run(['plugin', 'shim', 'legacy_maps', '--project', project]),
        throwsA(
          isA<CliError>().having(
            (e) => e.message,
            'message',
            startsWith('[plugin.override_exists]'),
          ),
        ),
      );
      await runner().run([
        'plugin',
        'shim',
        'legacy_maps',
        '--project',
        project,
        '--force',
      ]);

      out.clear();
      await runner().run(['plugin', 'list', '--project', project]);
      expect(out.join(), contains('✔ legacy_maps 0.0.1  (override)'));
    });

    test('--global writes under ~/.xcross/overrides', () async {
      await runner().run([
        'plugin',
        'shim',
        'modern_plugin',
        '--project',
        project,
        '--global',
      ]);
      expect(
        File(
          p.join(
            temp.path,
            'home',
            '.xcross',
            'overrides',
            'modern_plugin',
            '2.0.0',
            'Package.swift',
          ),
        ).existsSync(),
        isTrue,
      );
      expect(out.join(), contains('overrides the Package.swift'));
    });

    test('unknown plugin and missing project are coded errors', () async {
      Matcher coded(String code) => throwsA(
        isA<CliError>().having(
          (e) => e.message,
          'message',
          startsWith('[$code]'),
        ),
      );
      await expectLater(
        runner().run(['plugin', 'shim', 'nope', '--project', project]),
        coded('plugin.not_found'),
      );
      await expectLater(
        runner().run(['plugin', 'list', '--project', temp.path]),
        coded('plugin.no_project'),
      );
      await expectLater(
        runner().run(['plugin', 'shim', '--project', project]),
        throwsA(isA<UsageException>()),
      );
    });
  });
}
