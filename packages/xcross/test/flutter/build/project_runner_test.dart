// studio: 007 — the project's own Runner sources (XCROSS_RUNNER=project).
import 'dart:io';

import 'package:cli_kit/shared/logging/logging.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:darwin_sdk_kit/target/iphone/iphone_build_platform.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/diagnostics/build_warnings.dart';
import 'package:xcross/src/shared/flutter/build/ios_deployment_target.dart';
import 'package:xcross/src/shared/flutter/build/project_runner.dart';
import 'package:xcross/src/shared/flutter/build/project_runner_sources.dart';
import 'package:xcross/src/shared/flutter/errors.dart';
import 'package:xcross/src/shared/flutter/project/pbx_project_reader.dart';

import '../../log_fixture.dart';

/// A Flutter-template-shaped project: Runner app + RunnerTests.
const _pbxproj = r'''
// !$*UTF8*$!
{
	archiveVersion = 1;
	objectVersion = 54;
	objects = {
		AA01 /* Runner */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = BB01;
			buildPhases = (
				SS01,
			);
			name = Runner;
			productName = Runner;
			productType = "com.apple.product-type.application";
		};
		AA02 /* RunnerTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = BB01;
			buildPhases = (
				SS02,
			);
			name = RunnerTests;
			productType = "com.apple.product-type.bundle.unit-test";
		};
		SS01 = {
			isa = PBXSourcesBuildPhase;
			files = (
				FB01,
				FB02,
				FB03,
				FB04,
			);
		};
		SS02 = {
			isa = PBXSourcesBuildPhase;
			files = (
				FB05,
			);
		};
		FB01 = { isa = PBXBuildFile; fileRef = FR01; };
		FB02 = { isa = PBXBuildFile; fileRef = FR02; };
		FB03 = { isa = PBXBuildFile; fileRef = FR03; };
		FB04 = { isa = PBXBuildFile; fileRef = FR04; };
		FB05 = { isa = PBXBuildFile; fileRef = FR05; };
		FR01 = { isa = PBXFileReference; path = AppDelegate.swift; sourceTree = "<group>"; };
		FR02 = { isa = PBXFileReference; path = SceneDelegate.swift; sourceTree = "<group>"; };
		FR03 = { isa = PBXFileReference; path = GeneratedPluginRegistrant.m; sourceTree = "<group>"; };
		FR04 = { isa = PBXFileReference; path = Helper.m; sourceTree = "<group>"; };
		FR05 = { isa = PBXFileReference; path = RunnerTests.swift; sourceTree = "<group>"; };
		GR00 = {
			isa = PBXGroup;
			children = (
				GR01,
				GR02,
			);
			sourceTree = "<group>";
		};
		GR01 = {
			isa = PBXGroup;
			children = (
				FR01,
				FR02,
				FR03,
				FR04,
			);
			path = Runner;
			sourceTree = "<group>";
		};
		GR02 = {
			isa = PBXGroup;
			children = (
				FR05,
			);
			path = RunnerTests;
			sourceTree = "<group>";
		};
		CC01 = {
			isa = XCBuildConfiguration;
			buildSettings = {
				PRODUCT_BUNDLE_IDENTIFIER = com.example.app;
				PRODUCT_MODULE_NAME = "$(PRODUCT_NAME:c99extidentifier)";
				SWIFT_OBJC_BRIDGING_HEADER = "Runner/Runner-Bridging-Header.h";
			};
			name = Debug;
		};
		BB01 = {
			isa = XCConfigurationList;
			buildConfigurations = (
				CC01,
			);
		};
	};
	rootObject = PP01;
}
''';

const _templateAppDelegate = '''
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
''';

// studio: 016 — app A's shape: a Maps key before Flutter starts.
const _mapsAppDelegate = '''
import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Must run before any map is created.
    GMSServices.provideAPIKey("test-maps-key")
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
''';

const _legacyAppDelegate = '''
import Flutter
import UIKit

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
''';

const _templateSceneDelegate = '''
import Flutter
import UIKit

// The template's scene delegate is empty.
class SceneDelegate: FlutterSceneDelegate {

}
''';

void main() {
  late Directory project;
  const fileSystem = RunnerTestFileSystem();
  final projects = PbxProjectReader(fileSystem, p.context);

  setUp(() => project = Directory.systemTemp.createTempSync('xcross-runner-'));
  tearDown(() => project.deleteSync(recursive: true));

  File write(String relative, String text) =>
      File(p.joinAll([project.path, ...relative.split('/')]))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);

  void templateProject({String appDelegate = _templateAppDelegate}) {
    write('ios/Runner.xcodeproj/project.pbxproj', _pbxproj);
    write('ios/Runner/AppDelegate.swift', appDelegate);
    write('ios/Runner/SceneDelegate.swift', _templateSceneDelegate);
    write(
      'ios/Runner/GeneratedPluginRegistrant.m',
      '#import <a_plugin/APlugin.h>',
    );
    write('ios/Runner/Helper.m', '@implementation Helper @end');
    write(
      'ios/Runner/Runner-Bridging-Header.h',
      '#import "GeneratedPluginRegistrant.h"',
    );
    write('ios/RunnerTests/RunnerTests.swift', 'import XCTest');
  }

  ProjectRunnerSources discover() => ProjectRunnerSources.discover(
    project.path,
    fileSystem: fileSystem,
    paths: p.context,
    projects: projects,
  );

  group('AC-007-2 source discovery', () {
    test('the Runner target sources, without the generated registrant', () {
      templateProject();
      final sources = discover();
      expect(sources.swift.map(p.basename), [
        'AppDelegate.swift',
        'SceneDelegate.swift',
      ]);
      expect(sources.objc.map(p.basename), ['Helper.m']);
      expect(
        sources.bridgingHeader,
        p.join(project.path, 'ios', 'Runner', 'Runner-Bridging-Header.h'),
      );
      expect(sources.moduleName, 'Runner');
      expect(sources.headerDirectories, [
        p.join(project.path, 'ios', 'Runner'),
      ]);
      expect(sources.usesImplicitEngine, isTrue);
      expect(sources.sceneDelegateHasCode, isFalse);
      expect(sources.hasMainFile, isFalse);
    });

    test('without a project file every Runner source is used', () {
      write('ios/Runner/AppDelegate.m', '@implementation AppDelegate @end');
      write('ios/Runner/main.m', 'int main() { return 0; }');
      write('ios/Runner/GeneratedPluginRegistrant.m', '');
      write('ios/Runner/Info.plist', '<plist/>');
      final sources = discover();
      expect(sources.swift, isEmpty);
      expect(sources.objc.map(p.basename), ['AppDelegate.m', 'main.m']);
      expect(sources.hasMainFile, isTrue);
      expect(sources.bridgingHeader, isNull);
      expect(sources.moduleName, 'Runner');
    });

    test('no ios/Runner sources at all is empty', () {
      expect(discover().isEmpty, isTrue);
    });

    test('a pre-UIScene app delegate and scene delegate code are detected', () {
      templateProject(appDelegate: _legacyAppDelegate);
      write(
        'ios/Runner/SceneDelegate.swift',
        'class SceneDelegate: FlutterSceneDelegate {\n'
            '  override func sceneDidBecomeActive(_ scene: UIScene) {}\n'
            '}\n',
      );
      final sources = discover();
      expect(sources.usesImplicitEngine, isFalse);
      expect(sources.sceneDelegateHasCode, isTrue);
      expect(
        ProjectRunnerSources.isEmptySceneDelegate(_templateSceneDelegate),
        isTrue,
      );
      expect(
        ProjectRunnerSources.isEmptySceneDelegate(
          '@implementation SceneDelegate\n@end',
        ),
        isTrue,
      );
    });
  });

  group('AC-007-1 / AC-007-5 / AC-007-6 fallback and warnings', () {
    late TestLogOutput output;
    late BuildWarnings warnings;
    late List<ProjectRunnerSources> compiled;

    setUp(() {
      output = TestLogOutput();
      warnings = BuildWarnings(Log(output: output));
      compiled = [];
    });

    ProjectRunner runner({
      Map<String, String> environment = const {'XCROSS_RUNNER': 'project'},
      ProjectRunnerCompile? compile,
    }) => ProjectRunner(
      environment: environment,
      discover: discover,
      compile:
          compile ??
          (sources) async {
            compiled.add(sources);
            return '/out/Runner';
          },
      warnings: warnings,
      log: Log(output: output),
    );

    String text() => output.messages.join('\n');

    test('AC-007-1 / AC-016-9 a template app keeps the generic runner, '
        'nothing runs', () async {
      templateProject();
      File(p.join(project.path, 'ios', 'Runner', 'Helper.m')).deleteSync();
      expect(await runner(environment: const {}).build(), isNull);
      expect(
        await runner(environment: const {'XCROSS_RUNNER': 'auto'}).build(),
        isNull,
      );
      expect(compiled, isEmpty);
      expect(output.messages, isEmpty);
      expect(
        RunnerMode.fromEnvironment(const {'XCROSS_RUNNER': ' Project '}),
        RunnerMode.project,
      );
      expect(RunnerMode.fromEnvironment(const {}), RunnerMode.auto);
    });

    test('AC-016-9 XCROSS_RUNNER=shim never compiles the project', () async {
      templateProject(appDelegate: _mapsAppDelegate);
      expect(
        await runner(environment: const {'XCROSS_RUNNER': 'shim'}).build(),
        isNull,
      );
      expect(compiled, isEmpty);
      expect(output.messages, isEmpty);
    });

    test(
      'AC-016-9 by default an AppDelegate with its own code is compiled',
      () async {
        templateProject(appDelegate: _mapsAppDelegate);
        File(p.join(project.path, 'ios', 'Runner', 'Helper.m')).deleteSync();
        expect(await runner(environment: const {}).build(), '/out/Runner');
        expect(text(), contains('Runner: AppDelegate has its own code;'));
      },
    );

    test('AC-016-9 by default an extra source file is compiled', () async {
      templateProject();
      expect(await runner(environment: const {}).build(), '/out/Runner');
    });

    test(
      'AC-016-9 by default a failure still falls back with the code',
      () async {
        templateProject(appDelegate: _mapsAppDelegate);
        final result = await runner(
          environment: const {},
          compile: (_) async =>
              throw FlutterBuildError("error: no such module 'GoogleMaps'"),
        ).build();
        expect(result, isNull);
        expect(text(), contains('[build.runner_project_failed]'));
        expect(text(), contains('XCROSS_RUNNER=shim'));
      },
    );

    test(
      'AC-007-2 XCROSS_RUNNER=project compiles the template quietly',
      () async {
        templateProject();
        expect(await runner().build(), '/out/Runner');
        expect(compiled.single.swift, hasLength(2));
        expect(
          text(),
          contains('Runner: compiling the project sources (2 Swift, 1'),
        );
        expect(warnings.takeSummary(), isNull);
      },
    );

    test(
      'AC-007-5 a compile failure warns with the first errors and falls back',
      () async {
        templateProject();
        final result = await runner(
          compile: (_) async => throw FlutterBuildError(
            'swiftc failed (exit 1)\n'
            "AppDelegate.swift:9:5: error: cannot find 'GMSServices' in scope\n"
            'AppDelegate.swift:9:5: note: did you mean ...\n'
            "AppDelegate.swift:12:1: error: expected '}'\n",
          ),
        ).build();
        expect(result, isNull);
        expect(text(), contains('[build.runner_project_failed]'));
        expect(text(), contains("cannot find 'GMSServices' in scope"));
        expect(text(), contains("expected '}'"));
        expect(text(), isNot(contains('note: did you mean')));
        expect(text(), contains('hint: '));
      },
    );

    test('AC-007-5 no sources warns and falls back', () async {
      expect(await runner().build(), isNull);
      expect(text(), contains('[build.runner_project_failed]'));
      expect(text(), contains('no Swift or Objective-C sources'));
      expect(compiled, isEmpty);
    });

    test('AC-007-6 scene delegate code warns', () async {
      templateProject(appDelegate: _legacyAppDelegate);
      write(
        'ios/Runner/SceneDelegate.swift',
        'class SceneDelegate: FlutterSceneDelegate { var x = 1 }',
      );
      expect(await runner().build(), '/out/Runner');
      expect(text(), contains('[build.runner_scene_delegate_replaced]'));
    });

    test('firstErrors keeps marked lines, or the first lines', () {
      expect(ProjectRunner.firstErrors('a\n\nb\nc\nd'), ['a', 'b', 'c']);
      expect(ProjectRunner.firstErrors('x\ny: error: one\nz: error: two'), [
        'y: error: one',
        'z: error: two',
      ]);
      expect(
        ProjectRunner.firstErrors('e: error: ${'x' * 300}').single,
        hasLength(200),
      );
    });
  });

  group('AC-007-3 compiler and linker command lines', () {
    const target = IosDeploymentTarget('13.0', platform: IPhoneBuildPlatform());

    test('swiftc compiles the Swift sources and links the Runner', () {
      final args = ProjectRunnerBuilder.swiftArguments(
        iosSdk: '/sdk/iPhoneOS.sdk',
        resourceDir: '/swift',
        sources: ['/ios/Runner/AppDelegate.swift'],
        objects: ['/obj/0_Helper.o', '/obj/1_XcrossRunnerSupport.o'],
        outputPath: '/out/Runner',
        deploymentTarget: target,
        flutterSlice: '/engine/ios-arm64',
        moduleCache: '/cache',
        moduleName: 'Runner',
        ld64lld: '/ld64.lld',
        sdkVersion: '26.5',
        includeDirectories: ['/ios/Runner', '/out/support'],
        bridgingHeader: '/ios/Runner/Runner-Bridging-Header.h',
        pluginsLibrary: '/plugins/libFlutterPluginsGenerated.dylib',
        pluginModulesDir: '/plugins/Modules',
        pluginSearchArguments: ['-I', '/binary/Headers', '-F', '/binary/slice'],
        nativeAssetFrameworks: ['/assets/sqlite3.framework'],
      );
      expect(args, containsAllInOrder(['-module-name', 'Runner']));
      expect(args, contains('-parse-as-library'));
      expect(
        args,
        containsAllInOrder([
          '-import-objc-header',
          '/ios/Runner/Runner-Bridging-Header.h',
        ]),
      );
      expect(args, containsAllInOrder(['-F', '/engine/ios-arm64']));
      expect(args, containsAllInOrder(['-I', '/plugins/Modules']));
      expect(
        args,
        containsAllInOrder(['-I', '/binary/Headers', '-F', '/binary/slice']),
      );
      expect(args, containsAllInOrder(['-Xcc', '-I/ios/Runner']));
      expect(args, containsAllInOrder(['-framework', 'Flutter']));
      expect(
        args,
        containsAllInOrder([
          '-Xlinker',
          '-rpath',
          '-Xlinker',
          '@executable_path/Frameworks',
        ]),
      );
      expect(
        args,
        containsAllInOrder([
          '-Xlinker',
          '/plugins/libFlutterPluginsGenerated.dylib',
        ]),
      );
      expect(
        args,
        containsAllInOrder([
          '-Xlinker',
          '-needed_framework',
          '-Xlinker',
          'sqlite3',
        ]),
      );
      expect(
        args,
        containsAllInOrder([
          '/obj/0_Helper.o',
          '/obj/1_XcrossRunnerSupport.o',
          '/ios/Runner/AppDelegate.swift',
          '-o',
          '/out/Runner',
        ]),
      );
      expect(args, isNot(contains('-application-extension')));
      expect(args, containsAllInOrder(['-target', target.buildTriple]));
    });

    test('a main.swift is not parsed as a library', () {
      final args = ProjectRunnerBuilder.swiftArguments(
        iosSdk: '/sdk',
        resourceDir: '/swift',
        sources: ['/ios/Runner/main.swift'],
        objects: const [],
        outputPath: '/out/Runner',
        deploymentTarget: target,
        flutterSlice: '/slice',
        moduleCache: '/cache',
        moduleName: 'Runner',
        ld64lld: '/ld64.lld',
        sdkVersion: '26.5',
        includeDirectories: const [],
        parseAsLibrary: false,
      );
      expect(args, isNot(contains('-parse-as-library')));
      expect(args, isNot(contains('-import-objc-header')));
    });

    // A client app (2026-11-04): with many plugins the clang command passed
    // Windows' limit: "The filename or extension is too long", so the app's
    // AppDelegate was left out. Long commands go in a response file.
    group('long commands use a response file', () {
      test('only past the limit', () {
        expect(ProjectRunnerBuilder.needsResponseFile(['-c', 'a.m']), isFalse);
        expect(
          ProjectRunnerBuilder.needsResponseFile(
            List.filled(2000, 'C:/some/long/plugin/search/path/framework'),
          ),
          isTrue,
        );
      });

      test('quoted as each tool reads it, one argument per line', () {
        const arguments = [r'-IC:\a b\c', '-c', r'C:\d\e.m'];
        // clang reads GNU quoting, where a backslash escapes.
        expect(
          ProjectRunnerBuilder.responseFileText('clang', arguments),
          '"-IC:\\\\a b\\\\c"\n"-c"\n"C:\\\\d\\\\e.m"\n',
        );
        // swiftc reads Windows quoting, where it does not.
        expect(
          ProjectRunnerBuilder.responseFileText('swiftc', arguments),
          '"-IC:\\a b\\c"\n"-c"\n"C:\\d\\e.m"\n',
        );
      });
    });

    test('clang compiles Objective-C with the Runner header folders', () {
      final args = ProjectRunnerBuilder.objcCompileArguments(
        sourcePath: '/ios/Runner/Helper.m',
        objectPath: '/obj/0_Helper.o',
        iosSdk: '/sdk',
        subframeworks: '/sdk/System/Library/SubFrameworks',
        flutterSlice: '/slice',
        deploymentTarget: target,
        includeDirectories: ['/ios/Runner', '/out/support'],
        pluginSearchArguments: ['-I/binary/Headers', '-F/binary/slice'],
      );
      expect(
        args,
        containsAllInOrder(['-I', '/ios/Runner', '-I', '/out/support']),
      );
      expect(
        args,
        containsAllInOrder(['-I/binary/Headers', '-F/binary/slice']),
      );
      expect(args, contains('-fobjc-arc'));
      expect(
        args,
        containsAllInOrder([
          '-c',
          '/ios/Runner/Helper.m',
          '-o',
          '/obj/0_Helper.o',
        ]),
      );
    });

    test('an Objective-C-only Runner links every object with ld64.lld', () {
      final args = ProjectRunnerBuilder.objcLinkArguments(
        objects: ['/obj/0_main.o', '/obj/1_AppDelegate.o'],
        outputPath: '/out/Runner',
        iosSdk: '/sdk',
        flutterSlice: '/slice',
        subframeworks: '/sdk/SubFrameworks',
        sdkVersion: '26.5',
        deploymentTarget: target,
        pluginsLibrary: '/plugins/lib.dylib',
      );
      expect(
        args,
        containsAllInOrder([
          '-o',
          '/out/Runner',
          '/obj/0_main.o',
          '/obj/1_AppDelegate.o',
          '/plugins/lib.dylib',
        ]),
      );
      expect(args, containsAllInOrder(['-framework', 'Flutter']));
      expect(
        args,
        containsAllInOrder(['-rpath', '@executable_path/Frameworks']),
      );
    });
  });

  group('AC-007-4 xcross support code and Info.plist', () {
    test('the registrant forwards to the plugins library', () {
      final withPlugins = ProjectRunnerBuilder.supportSource(hasPlugins: true);
      expect(
        withPlugins,
        contains(
          [
            'extern void XcrossRegisterGeneratedPlugins',
            '(NSObject<FlutterPluginRegistry>* registry);',
          ].join(),
        ),
      );
      expect(
        withPlugins,
        contains('  XcrossRegisterGeneratedPlugins(registry);'),
      );
      expect(
        withPlugins,
        contains('@implementation GeneratedPluginRegistrant'),
      );
      final without = ProjectRunnerBuilder.supportSource(hasPlugins: false);
      expect(without, isNot(contains('XcrossRegisterGeneratedPlugins')));
      expect(without, contains('@implementation GeneratedPluginRegistrant'));
      expect(
        ProjectRunnerBuilder.registrantHeader,
        contains('+ (void)registerWithRegistry:'),
      );
    });

    test('the scene delegate creates the Flutter window', () {
      final source = ProjectRunnerBuilder.supportSource(hasPlugins: true);
      expect(
        source,
        contains('@interface XcrossSceneDelegate : FlutterSceneDelegate'),
      );
      expect(
        source,
        contains('window.rootViewController = flutterViewController;'),
      );
      expect(
        source,
        contains(
          'if (launchEngine == nil && ![appDelegate conformsToProtocol:@protocol(FlutterImplicitEngineDelegate)]) {\n'
          '    [GeneratedPluginRegistrant registerWithRegistry:flutterViewController.engine];',
        ),
      );
    });

    test('plugins an app delegate registers at launch get a running engine '
        'there, which the window uses', () {
      final source = ProjectRunnerBuilder.supportSource(hasPlugins: true);
      // Registered during launch, a plugin hears that launch finished: that is
      // when firebase_messaging connects to push and can get its APNs token.
      expect(
        source,
        contains(
          '  if (![registry isKindOfClass:[FlutterEngine class]]) {\n'
          '    if (xcrossLaunchEngine != nil) return;\n'
          '    xcrossLaunchEngine = [[FlutterEngine alloc] initWithName:@"io.flutter"];\n'
          '    [xcrossLaunchEngine run];\n'
          '    registry = xcrossLaunchEngine;\n'
          '  }\n'
          '  XcrossRegisterGeneratedPlugins(registry);',
        ),
      );
      expect(
        source,
        contains(
          '[[FlutterViewController alloc] initWithEngine:launchEngine nibName:nil bundle:nil]',
        ),
      );
      // A second window cannot share an engine that already has one.
      expect(
        source,
        contains(
          'xcrossLaunchEngine.viewController == nil ? xcrossLaunchEngine : nil',
        ),
      );
    });

    test('Info.plist names the xcross scene delegate', () {
      final plist = [
        '<dict><key>UISceneConfigurations</key><dict>',
        '<key>UISceneDelegateClassName</key>\n',
        '\t<string>SceneDelegate</string>',
        '<key>UISceneConfigurationName</key><string>flutter</string>',
        '</dict></dict>',
      ].join();
      final updated = ProjectRunnerBuilder.withSceneDelegate(
        plist,
        ProjectRunnerBuilder.sceneDelegateClass,
      );
      expect(updated, contains('<string>XcrossSceneDelegate</string>'));
      expect(updated, contains('<string>flutter</string>'));
      expect(updated, isNot(contains('<string>SceneDelegate</string>')));
    });
  });
}

/// dart:io-backed host file system for this test.
@internal
final class RunnerTestFileSystem implements HostFileSystemInterface {
  const RunnerTestFileSystem();

  @override
  File file(String path) => File(path);
  @override
  Directory directory(String path) => Directory(path);
  @override
  Link link(String path) => Link(path);
  @override
  void makeExecutable(String path) {}
  @override
  void setPermissions(String path, int mode) {}
  @override
  Future<void> createArchiveLink(String destination, String target) =>
      Link(destination).create(target);
}
