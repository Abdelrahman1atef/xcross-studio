// studio: 016 — XCROSS_RUNNER=auto and SwiftPM module maps
// (specs/016-push-firebase-maps, AC-016-9, AC-016-10).
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/flutter/build/project_runner_sources.dart';
import 'package:xcross/src/shared/flutter/build/swiftpm_module_map.dart';
import 'package:xcross/src/shared/flutter/swiftpm/artifact_filesystem.dart';

void main() {
  group('AC-016-9 Flutter template sources', () {
    bool template(String name, String source) =>
        ProjectRunnerSources.isTemplateSource(name, source);

    test('the UIScene Swift AppDelegate', () {
      expect(
        template('AppDelegate', '''
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
'''),
        isTrue,
      );
    });

    test('the older Swift AppDelegate', () {
      expect(
        template('AppDelegate', '''
import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
'''),
        isTrue,
      );
    });

    test('the Objective-C AppDelegate and main', () {
      expect(
        template('AppDelegate', '''
#import "AppDelegate.h"
#import "GeneratedPluginRegistrant.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  [GeneratedPluginRegistrant registerWithRegistry:self];
  // Override point for customization after application launch.
  return [super application:application didFinishLaunchingWithOptions:launchOptions];
}

@end
'''),
        isTrue,
      );
      expect(
        template('main', '''
#import <Flutter/Flutter.h>
#import <UIKit/UIKit.h>
#import "AppDelegate.h"

int main(int argc, char* argv[]) {
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
  }
}
'''),
        isTrue,
      );
    });

    test('a Maps key, Firebase setup or another file is custom code', () {
      expect(
        template('AppDelegate', '''
import Flutter
import GoogleMaps
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("k")
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
'''),
        isFalse,
      );
      expect(template('AppDelegate', 'FirebaseApp.configure()'), isFalse);
      expect(template('Helper', '@implementation Helper @end'), isFalse);
      expect(
        template(
          'SceneDelegate',
          'class SceneDelegate: FlutterSceneDelegate {}',
        ),
        isTrue,
      );
    });
  });

  group('AC-016-10 SwiftPM module maps', () {
    test('the umbrella header folder, or its parent named after the module', () {
      expect(
        SwiftPmModuleMap.includeDirectoryOf(
          'module FirebaseCore {\n'
          r'    umbrella header "C:\\x\\FirebaseCore\\Sources\\Public\\FirebaseCore\\FirebaseCore.h"'
          '\n    export *\n}\n',
        ),
        r'C:\x\FirebaseCore\Sources\Public',
      );
      expect(
        SwiftPmModuleMap.includeDirectoryOf(
          'module CTweetNacl {\n    umbrella header "/x/CTweetNacl/include/tweetnacl.h"\n}\n',
        ),
        '/x/CTweetNacl/include',
      );
      expect(
        SwiftPmModuleMap.includeDirectoryOf(
          'module GoogleMapsCoreTarget {\n'
          '    umbrella "/x/ios-maps-sdk/Core/Sources"\n    export *\n}\n',
        ),
        '/x/ios-maps-sdk/Core/Sources',
      );
    });

    test('discovers every *.build/module.modulemap with its arguments', () {
      final products = Directory.systemTemp.createTempSync('module-maps-');
      addTearDown(() => products.deleteSync(recursive: true));
      for (final target in ['FirebaseCore', 'firebase_messaging']) {
        Directory(p.join(products.path, '$target.build')).createSync();
        File(
          p.join(products.path, '$target.build', 'module.modulemap'),
        ).writeAsStringSync(
          'module $target {\n    umbrella header "/src/$target/include/$target.h"\n}\n',
        );
      }
      Directory(p.join(products.path, 'Swifty.build')).createSync();
      final maps = SwiftPmModuleMap.discover(
        const HostArtifacts(),
        products.path,
      );
      expect(maps, hasLength(2));
      expect(maps.first.path, endsWith('module.modulemap'));
      expect(maps.first.swiftArguments, [
        '-Xcc',
        '-fmodule-map-file=${maps.first.path}',
        '-Xcc',
        '-I/src/FirebaseCore/include',
      ]);
      expect(maps.first.clangArguments, [
        '-fmodule-map-file=${maps.first.path}',
        '-I/src/FirebaseCore/include',
      ]);
    });
  });
}

@internal
final class HostArtifacts implements SwiftPmArtifactFileSystem {
  const HostArtifacts();

  @override
  File file(String path) => File(path);

  @override
  Directory directory(String path) => Directory(path);

  @override
  Link link(String path) => Link(path);

  @override
  String processPath(String path) => path;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
