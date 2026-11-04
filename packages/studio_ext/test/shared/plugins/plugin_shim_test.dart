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
      // No version in the podspec: the known package's own (a client app's
      // `from: "1.0.0"` SDWebImage clashed with file_picker's 5.x).
      expect(
        swiftRequirement(
          null,
          defaultVersion: knownPackageFor('SDWebImage')!.defaultVersion,
        ),
        'from: "5.0.0"',
      );
      expect(
        swiftRequirement('~> 5.1', defaultVersion: '9.0'),
        contains('5.1'),
      );
      for (final (pod, product) in [
        ('Mantle', 'Mantle'),
        ('SDWebImageWebPCoder', 'SDWebImageWebPCoder'),
      ]) {
        expect(knownPackageFor(pod)?.product, product);
        expect(knownPackageFor(pod)?.defaultVersion, isNotNull);
      }
      expect(
        knownPackageFor('Firebase/Messaging')?.product,
        'FirebaseMessaging',
      );
      expect(knownPackageFor('FirebaseCore')?.package, 'firebase-ios-sdk');
      expect(knownPackageFor('SomeVendorSDK'), isNull);
    });

    // flutter_facebook_auth (a client app, 2026-11-04): "no such module
    // 'FBSDKLoginKit'". The Swift package's products have other names, and it
    // needs a newer iOS than the podspec's, which SwiftPM refuses.
    test('Facebook pods use the facebook-ios-sdk products and raise the '
        'iOS minimum to what the package needs', () {
      final draft = draftPackageSwift(
        plugin: 'flutter_facebook_auth',
        spec: Podspec.parse('''
Pod::Spec.new do |s|
  s.name = 'flutter_facebook_auth'
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'FBSDKLoginKit', '18.0.2'
  s.dependency 'FBSDKCoreKit', '18.0.2'
  s.platform = :ios, '11.0'
end
'''),
        files: const ['Classes/FacebookAuth.swift'],
      );
      expect(draft.text, contains('platforms: [.iOS("12.0")]'));
      expect(
        RegExp('facebook-ios-sdk"').allMatches(draft.text).length,
        3,
        reason: 'one package line, two products',
      );
      expect(
        draft.text,
        contains(
          '.package(url: "https://github.com/facebook/facebook-ios-sdk", '
          'exact: "18.0.2")',
        ),
      );
      expect(
        draft.text,
        contains(
          '.product(name: "FacebookLogin", package: "facebook-ios-sdk")',
        ),
      );
      expect(
        draft.text,
        contains('.product(name: "FacebookCore", package: "facebook-ios-sdk")'),
      );
      expect(draft.text, isNot(contains('TODO')));
    });

    test('a podspec above the package minimum keeps its own iOS version', () {
      final draft = draftPackageSwift(
        plugin: 'newer',
        spec: Podspec.parse('''
Pod::Spec.new do |s|
  s.source_files = 'Classes/**/*'
  s.dependency 'FBSDKLoginKit', '18.0.2'
  s.platform = :ios, '15.5'
end
'''),
        files: const ['Classes/A.swift'],
      );
      expect(draft.text, contains('platforms: [.iOS("15.5")]'));
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
      expect(draft.notes.single, contains('SomeVendorSDK'));
    });

    // fluttertoast 8.2.14 (2026-11-05): `release check` found no manifest in
    // the app although the plugin ships one, in a folder the target can't see.
    test('AC-006-16 a privacy manifest outside the target folder is copied '
        'into it and declared', () {
      final draft = draftPackageSwift(
        plugin: 'legacy_maps',
        spec: Podspec.parse(_objcPodspec),
        files: const [
          'Classes/LegacyMapsPlugin.m',
          'Resources/PrivacyInfo.xcprivacy',
        ],
      );
      expect(draft.resourceCopies, {
        'Resources/PrivacyInfo.xcprivacy': 'Classes/PrivacyInfo.xcprivacy',
      });
      expect(draft.text, contains('.process("PrivacyInfo.xcprivacy")'));
      expect(draft.notes.join(), isNot(contains('PrivacyInfo.xcprivacy')));
    });

    test('AC-006-16 a mixed plugin: the Objective-C target declares the '
        'manifest and the Swift target excludes it', () {
      final draft = draftPackageSwift(
        plugin: 'old_swift_plugin',
        spec: Podspec.parse('''
Pod::Spec.new do |s|
  s.name = 'old_swift_plugin'
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.resource_bundles = {'old_swift_plugin_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
'''),
        files: const [
          'Classes/OldSwiftPlugin.m',
          'Classes/SwiftOldSwiftPlugin.swift',
          'Resources/PrivacyInfo.xcprivacy',
        ],
      );
      final swiftTarget = draft.text.substring(
        draft.text.indexOf('name: "old_swift_plugin_swift"'),
        draft.text.lastIndexOf('name: "old_swift_plugin",'),
      );
      expect(swiftTarget, contains('"PrivacyInfo.xcprivacy"'));
      expect(swiftTarget, isNot(contains('.process(')));
      expect(
        draft.text.substring(draft.text.indexOf('resources: [')),
        contains('.process("PrivacyInfo.xcprivacy")'),
      );
    });

    test('AC-006-16 what cannot be copied stays a review note', () {
      final draft = draftPackageSwift(
        plugin: 'legacy_maps',
        spec: Podspec.parse('''
Pod::Spec.new do |s|
  s.name = 'legacy_maps'
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.resource_bundles = {'a' => ['Resources/PrivacyInfo.xcprivacy'], 'b' => ['Assets/logo.png']}
end
'''),
        // The podspec names a manifest the plugin doesn't have.
        files: const ['Classes/LegacyMapsPlugin.m', 'Assets/logo.png'],
      );
      expect(draft.resourceCopies, isEmpty);
      expect(draft.text, isNot(contains('resources: [')));
      expect(draft.notes.join(), contains('Resources/PrivacyInfo.xcprivacy'));
      expect(draft.notes.join(), contains('Assets/logo.png'));
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
      expect(draft.notes.single, contains('"old_swift_plugin_swift"'));
      expect(draft.objcSources, [
        'Classes/OldSwiftPlugin.m',
        'Classes/OldSwiftPlugin.h',
      ]);
    });

    test('AC-006-9 the Swift-header imports become @import of the Swift '
        'target', () {
      const pusherStyle = '''
#import "PusherChannelsFlutterPlugin.h"
#if __has_include(<pusher_channels_flutter/pusher_channels_flutter-Swift.h>)
#import <pusher_channels_flutter/pusher_channels_flutter-Swift.h>
#else
// fallback comment
#import "pusher_channels_flutter-Swift.h"
#endif

@implementation PusherChannelsFlutterPlugin
@end
''';
      final patched = patchSwiftHeaderImports(
        pusherStyle,
        'pusher_channels_flutter',
      );
      expect(patched, isNotNull);
      expect(patched, contains('@import pusher_channels_flutter_swift;'));
      expect(patched, isNot(contains('-Swift.h')));
      expect(patched, contains('#import "PusherChannelsFlutterPlugin.h"'));
      expect(patched, contains('@implementation PusherChannelsFlutterPlugin'));
      expect(
        patchSwiftHeaderImports(
          '#import "Other.h"\n',
          'pusher_channels_flutter',
        ),
        isNull,
      );
      expect(
        patchSwiftHeaderImports('  #import "x-Swift.h"\n', 'x'),
        '@import x_swift;\n',
      );
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

  test('AC-006-9 resources come before publicHeadersPath (Swift argument '
      'order)', () {
    // google_maps_flutter_ios 2.18.3: a privacy manifest plus include/.
    final draft = draftPackageSwift(
      plugin: 'spm_layout',
      spec: Podspec.parse('''
Pod::Spec.new do |s|
  s.name = 'spm_layout'
  s.source_files = 'spm_layout/Sources/spm_layout/**/*.{h,m}'
  s.public_header_files = 'spm_layout/Sources/spm_layout/include/**/*.h'
  s.resource_bundles = {'spm_layout_privacy' => ['spm_layout/Sources/spm_layout/Resources/PrivacyInfo.xcprivacy']}
  s.frameworks = 'CoreLocation'
  s.dependency 'Flutter'
end
'''),
      files: const [
        'spm_layout/Sources/spm_layout/Plugin.m',
        'spm_layout/Sources/spm_layout/include/spm_layout/Plugin.h',
      ],
    );
    final text = draft.text;
    final resources = text.indexOf('resources: [');
    final headers = text.indexOf('publicHeadersPath:');
    final cSettings = text.indexOf('cSettings: [');
    final linker = text.indexOf('linkerSettings:');
    expect(resources, isNonNegative);
    expect(headers, greaterThan(resources));
    expect(cSettings, greaterThan(headers));
    expect(linker, greaterThan(cSettings));
    // `#import "Plugin.h"` from another folder, as CocoaPods allows.
    expect(text, contains('.headerSearchPath("include/spm_layout")'));
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

    test('AC-006-10 a mixed plugin gets patched Objective-C files, also with '
        'Windows long-path names', () async {
      final root = p.join(temp.path, 'pub', 'mixed_plugin');
      File(p.join(root, 'pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('name: mixed_plugin\nversion: 1.0.0\n');
      void ios(String path, String text) =>
          File(p.joinAll([root, 'ios', ...path.split('/')]))
            ..createSync(recursive: true)
            ..writeAsStringSync(text);
      ios(
        'mixed_plugin.podspec',
        "Pod::Spec.new do |s|\n  s.source_files = 'Classes/**/*'\n"
            "  s.dependency 'Flutter'\nend\n",
      );
      ios('Classes/MixedPlugin.h', '#import <Flutter/Flutter.h>\n');
      ios(
        'Classes/MixedPlugin.m',
        '#import "MixedPlugin.h"\n#import "mixed_plugin-Swift.h"\n',
      );
      ios('Classes/SwiftMixedPlugin.swift', 'public class X {}\n');
      File(p.join(project, '.flutter-plugins-dependencies')).writeAsStringSync(
        jsonEncode({
          'plugins': {
            'ios': [
              {'name': 'mixed_plugin', 'path': root},
            ],
          },
        }),
      );
      // The host file system on Windows lists \\?\-prefixed paths.
      await (CommandRunner<void>('xcross', 'test')..addCommand(
            PluginCommand(
              fileSystem: const IoFileSystem(longPathPrefix: true),
              paths: p.context,
              write: out.add,
              home: p.join(temp.path, 'home'),
            ),
          ))
          .run(['plugin', 'shim', 'mixed_plugin', '--project', project]);
      final folder = p.join(
        project,
        'xcross_overrides',
        'mixed_plugin',
        '1.0.0',
      );
      expect(out.join(), isNot(contains('No Swift or Objective-C sources')));
      expect(
        File(p.join(folder, 'Package.swift')).readAsStringSync(),
        contains('name: "mixed_plugin_swift"'),
      );
      expect(
        File(p.join(folder, 'Classes', 'MixedPlugin.m')).readAsStringSync(),
        '#import "MixedPlugin.h"\n@import mixed_plugin_swift;\n',
      );
      expect(
        File(p.join(folder, 'Classes', 'MixedPlugin.h')).existsSync(),
        isFalse,
      );
      expect(out.join(), contains('✔ Patched Classes/MixedPlugin.m'));
    });

    // audio_waveforms and video_compress (a client app, 2026-11-04): a pod's Swift
    // files see its umbrella header (Foundation, UIKit, Flutter) without
    // importing it; under SwiftPM "cannot find type 'FlutterResult' in scope".
    test('AC-006-13 Swift files get the imports CocoaPods gave them', () async {
      final root = p.join(temp.path, 'pub', 'pod_swift');
      File(p.join(root, 'pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('name: pod_swift\nversion: 1.0.0\n');
      void ios(String path, String text) => File(p.join(root, 'ios', path))
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
      ios(
        'pod_swift.podspec',
        "Pod::Spec.new do |s|\n  s.source_files = 'Classes/**/*'\n"
            "  s.dependency 'Flutter'\nend\n",
      );
      ios(
        'Classes/Plugin.swift',
        'import Flutter\nclass P: FlutterPlugin {}\n',
      );
      ios(
        'Classes/Player.swift',
        '// Copyright\nimport AVKit\n\nvar r: FlutterResult?\n',
      );
      ios('Classes/Utility.swift', 'class U { let u: URL? = nil }\n');
      File(p.join(project, '.flutter-plugins-dependencies')).writeAsStringSync(
        jsonEncode({
          'plugins': {
            'ios': [
              {'name': 'pod_swift', 'path': root},
            ],
          },
        }),
      );
      await runner().run(['plugin', 'shim', 'pod_swift', '--project', project]);
      final folder = p.join(
        project,
        'xcross_overrides',
        'pod_swift',
        '1.0.0',
        'Classes',
      );
      expect(
        File(p.join(folder, 'Player.swift')).readAsStringSync(),
        '// Copyright\nimport Flutter\nimport AVKit\n\nvar r: FlutterResult?\n',
      );
      expect(
        File(p.join(folder, 'Utility.swift')).readAsStringSync(),
        'import Foundation\nclass U { let u: URL? = nil }\n',
      );
      expect(File(p.join(folder, 'Plugin.swift')).existsSync(), isFalse);
      expect(
        out.join(),
        contains('✔ Patched Classes/Player.swift (import Flutter)'),
      );
    });

    // permission_handler_apple (a client app, 2026-11-04): "use of undeclared
    // identifier 'UIApplication'". A pod's prefix header gave each Objective-C
    // file UIKit.
    test('AC-006-13 Objective-C files get the UIKit their prefix header '
        'gave them, also when nothing else needs patching', () async {
      final root = p.join(temp.path, 'pub', 'pod_objc');
      File(p.join(root, 'pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('name: pod_objc\nversion: 1.0.0\n');
      void ios(String path, String text) => File(p.join(root, 'ios', path))
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
      ios(
        'pod_objc.podspec',
        "Pod::Spec.new do |s|\n  s.source_files = 'Classes/**/*'\n"
            "  s.dependency 'Flutter'\nend\n",
      );
      ios('Classes/Plugin.h', '#import <Flutter/Flutter.h>\n');
      ios(
        'Classes/Phone.m',
        '//  Phone\n\n#import "Plugin.h"\n[UIApplication sharedApplication];\n',
      );
      ios('Classes/Native.c', 'int UIFake = 1;\n');
      File(p.join(project, '.flutter-plugins-dependencies')).writeAsStringSync(
        jsonEncode({
          'plugins': {
            'ios': [
              {'name': 'pod_objc', 'path': root},
            ],
          },
        }),
      );
      await runner().run(['plugin', 'shim', 'pod_objc', '--project', project]);
      final folder = p.join(
        project,
        'xcross_overrides',
        'pod_objc',
        '1.0.0',
        'Classes',
      );
      expect(
        File(p.join(folder, 'Phone.m')).readAsStringSync(),
        '//  Phone\n\n#import <UIKit/UIKit.h>\n#import "Plugin.h"\n'
        '[UIApplication sharedApplication];\n',
      );
      expect(File(p.join(folder, 'Plugin.h')).existsSync(), isFalse);
      expect(File(p.join(folder, 'Native.c')).existsSync(), isFalse);
      expect(out.join(), contains('✔ Patched Classes/Phone.m (import UIKit)'));
    });

    // flutter_image_compress_common (a client app, 2026-11-04): "'Mantle/Mantle.h'
    // file not found". Mantle and SDWebImageWebPCoder keep flat headers in
    // their Swift packages, so only their modules can be imported.
    test('AC-006-14 pods with flat headers in their Swift package are '
        'imported as modules', () async {
      final root = p.join(temp.path, 'pub', 'pod_flat');
      File(p.join(root, 'pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('name: pod_flat\nversion: 1.0.0\n');
      void ios(String path, String text) => File(p.join(root, 'ios', path))
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
      ios(
        'pod_flat.podspec',
        "Pod::Spec.new do |s|\n  s.source_files = 'Classes/**/*'\n"
            "  s.dependency 'Flutter'\n  s.dependency 'Mantle'\n"
            "  s.dependency 'SDWebImage'\n  s.dependency 'SDWebImageWebPCoder'\n"
            'end\n',
      );
      ios('Classes/Base.h', '#import <Mantle/Mantle.h>\nint a;\n');
      ios(
        'Classes/Coder.m',
        '#import <SDWebImage/SDWebImage.h>\n'
            '#import <SDWebImageWebPCoder/SDImageWebPCoder.h>\n'
            '  #include <Mantle/MTLModel.h> // model\n'
            'int b;\n',
      );
      File(p.join(project, '.flutter-plugins-dependencies')).writeAsStringSync(
        jsonEncode({
          'plugins': {
            'ios': [
              {'name': 'pod_flat', 'path': root},
            ],
          },
        }),
      );
      await runner().run(['plugin', 'shim', 'pod_flat', '--project', project]);
      final folder = p.join(
        project,
        'xcross_overrides',
        'pod_flat',
        '1.0.0',
        'Classes',
      );
      expect(
        File(p.join(folder, 'Base.h')).readAsStringSync(),
        '@import Mantle;\nint a;\n',
      );
      expect(
        File(p.join(folder, 'Coder.m')).readAsStringSync(),
        '#import <SDWebImage/SDWebImage.h>\n'
        '@import SDWebImageWebPCoder;\n'
        '@import Mantle;\n'
        'int b;\n',
      );
      expect(
        out.join(),
        contains('✔ Patched Classes/Base.h (@import Mantle;)'),
      );
    });

    // permission_handler_apple (a client app, 2026-11-04): "'AudioVideoPermission
    // Strategy.h' file not found" when another module imports the plugin.
    // CocoaPods flattens a pod's headers, so a bare name finds any of them.
    test('AC-006-15 headers importing a header in another folder get its '
        'relative path', () {
      const headers = [
        'Classes/Manager.h',
        'Classes/Base.h',
        'Classes/strategies/Strategy.h',
        'Classes/strategies/Near.h',
        'Classes/one/Same.h',
        'Classes/two/Same.h',
      ];
      expect(
        patchHeaderPaths(
          '#import "Strategy.h"\n#import "Base.h"\n'
          '  #include "Near.h" // near\n#import <Flutter/Flutter.h>\n',
          file: 'Classes/Manager.h',
          headers: headers,
        ),
        '#import "strategies/Strategy.h"\n#import "Base.h"\n'
        '  #include "strategies/Near.h" // near\n#import <Flutter/Flutter.h>\n',
      );
      expect(
        patchHeaderPaths(
          '#import "Base.h"\n#import "Near.h"\n',
          file: 'Classes/strategies/Strategy.h',
          headers: headers,
        ),
        '#import "../Base.h"\n#import "Near.h"\n',
      );
      // Unknown, ambiguous, already a path, or next to the file: unchanged.
      expect(
        patchHeaderPaths(
          '#import "Other.h"\n#import "Same.h"\n#import "strategies/Near.h"\n'
          '#import "Base.h"\n',
          file: 'Classes/Manager.h',
          headers: headers,
        ),
        isNull,
      );
    });

    test('implicit Objective-C imports: what counts as imported and used', () {
      // Flutter's header brings UIKit; a comment is not a use.
      for (final source in [
        '#import <UIKit/UIKit.h>\nUIView *v;\n',
        '@import UIKit;\nUIView *v;\n',
        '#import <Flutter/Flutter.h>\nUIView *v;\n',
        '@import Flutter;\nUIView *v;\n',
        '// UIView\n#import "A.h"\nint x;\n',
        '#import "A.h"\nNSString *s;\n',
      ]) {
        expect(patchImplicitObjcImports(source), isNull, reason: source);
      }
      // No import at all: Foundation for its NS types.
      expect(
        patchImplicitObjcImports('NSString *s;\n'),
        '#import <Foundation/Foundation.h>\nNSString *s;\n',
      );
      // And its NS_ macros: permission_handler_apple's enums header, as a
      // module, "type specifier missing" at `typedef NS_ENUM(int, Group)`.
      expect(
        patchImplicitObjcImports(
          '#ifndef X\n#define X 0\n#endif\n'
          'typedef NS_ENUM(int, Group) { GroupA };\n',
          header: true,
        ),
        '#ifdef __OBJC__\n#import <Foundation/Foundation.h>\n#endif\n'
        '#ifndef X\n#define X 0\n#endif\n'
        'typedef NS_ENUM(int, Group) { GroupA };\n',
      );
      // A header can be included from plain C: guarded.
      expect(
        patchImplicitObjcImports(
          '#ifndef A_H\n#define A_H\nUIView *v;\n#endif\n',
          header: true,
        ),
        '#ifdef __OBJC__\n#import <UIKit/UIKit.h>\n#endif\n'
        '#ifndef A_H\n#define A_H\nUIView *v;\n#endif\n',
      );
    });

    test('implicit imports: what counts as imported and used', () {
      // UIKit and Flutter bring Foundation; only what is used is added.
      expect(patchImplicitImports('import UIKit\nlet u: URL? = nil\n'), isNull);
      expect(patchImplicitImports('import Foundation\nlet x = 1\n'), isNull);
      expect(
        patchImplicitImports('import Foundation\nlet v: UIView? = nil\n'),
        'import UIKit\nimport Foundation\nlet v: UIView? = nil\n',
      );
      // No code, nothing to add; an import inside #if counts.
      expect(patchImplicitImports('// nothing here\n'), isNull);
      expect(
        patchImplicitImports(
          '#if os(iOS)\n  import Flutter\n#endif\nvar r: FlutterResult?\n',
        ),
        isNull,
      );
      // After a block comment, and with CRLF files keeping their line ends.
      expect(
        patchImplicitImports(
          '/* License\n text */\r\nvar r: FlutterResult?\r\n',
        ),
        '/* License\n text */\r\nimport Flutter\r\nvar r: FlutterResult?\r\n',
      );
    });

    test('AC-006-12 a pod whose Objective-C module is renamed in its Swift '
        'package gets patched imports', () async {
      // google_maps_flutter_ios: `@import GoogleMapsUtils;` must become
      // `@import GoogleMapsUtilsObjC;` under SwiftPM.
      final root = p.join(temp.path, 'pub', 'maps_plugin');
      File(p.join(root, 'pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('name: maps_plugin\nversion: 1.0.0\n');
      void ios(String path, String text) =>
          File(p.joinAll([root, 'ios', ...path.split('/')]))
            ..createSync(recursive: true)
            ..writeAsStringSync(text);
      ios(
        'maps_plugin.podspec',
        "Pod::Spec.new do |s|\n  s.source_files = 'Classes/**/*'\n"
            "  s.dependency 'Flutter'\n"
            "  s.dependency 'Google-Maps-iOS-Utils', '>= 5.0'\nend\n",
      );
      ios('Classes/Trampoline.h', '@import GoogleMapsUtils;\n');
      ios('Classes/MapsPlugin.m', '#import "Trampoline.h"\n');
      File(p.join(project, '.flutter-plugins-dependencies')).writeAsStringSync(
        jsonEncode({
          'plugins': {
            'ios': [
              {'name': 'maps_plugin', 'path': root},
            ],
          },
        }),
      );
      await runner().run([
        'plugin',
        'shim',
        'maps_plugin',
        '--project',
        project,
      ]);
      final folder = p.join(
        project,
        'xcross_overrides',
        'maps_plugin',
        '1.0.0',
      );
      expect(
        File(p.join(folder, 'Classes', 'Trampoline.h')).readAsStringSync(),
        '@import GoogleMapsUtilsObjC;\n',
      );
      expect(
        File(p.join(folder, 'Classes', 'MapsPlugin.m')).existsSync(),
        isFalse,
        reason: 'unchanged files are not copied',
      );
      expect(
        out.join(),
        contains(
          '✔ Patched Classes/Trampoline.h (@import GoogleMapsUtilsObjC;',
        ),
      );
    });

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

    test('AC-006-16 shim --force gives an older draft the privacy manifest of '
        'the plugin, byte for byte', () async {
      // Binary plists are valid manifests, so this must not go through text.
      const manifest = [0x62, 0x70, 0x6c, 0x69, 0x73, 0x74, 0xff, 0x00];
      File(
          p.join(
            temp.path,
            'pub',
            'legacy_maps',
            'ios',
            'Resources',
            'PrivacyInfo.xcprivacy',
          ),
        )
        ..createSync(recursive: true)
        ..writeAsBytesSync(manifest);
      final folder = p.join(
        project,
        'xcross_overrides',
        'legacy_maps',
        '0.0.1',
      );
      final package = File(p.join(folder, 'Package.swift'))
        ..createSync(recursive: true)
        ..writeAsStringSync('// an older draft, without the manifest');

      await runner().run([
        'plugin',
        'shim',
        'legacy_maps',
        '--project',
        project,
        '--force',
      ]);

      expect(
        File(
          p.join(folder, 'Classes', 'PrivacyInfo.xcprivacy'),
        ).readAsBytesSync(),
        manifest,
      );
      expect(
        package.readAsStringSync(),
        contains('.process("PrivacyInfo.xcprivacy")'),
      );
      expect(
        out.join(),
        contains('copied from Resources/PrivacyInfo.xcprivacy'),
      );
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
