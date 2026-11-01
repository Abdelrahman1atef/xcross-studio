// studio: 007 — the bundle names xcross's scene delegate only for a project
// runner (the shim keeps its own `SceneDelegate`).
@TestOn('!windows')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/flutter/build/internal/runner_binary.dart';
import 'package:xcross/src/shared/flutter/build/ios_native_assets.dart';
import 'package:xcross/src/shared/flutter/build/project_runner.dart';
import 'package:xcross/src/shared/flutter/flutter_build_steps.dart';
import 'package:xcross/src/shared/flutter/flutter_bundle_assembler.dart';
import 'package:xcross/src/shared/flutter/models/flutter/flutter_build_options.dart';

import '../flutter_test_runtime.dart';

void main() {
  test('AC-007-4 Info.plist scene delegate follows the runner kind', () async {
    final project = Directory.systemTemp.createTempSync('xcross_runner_plist_');
    addTearDown(() => project.deleteSync(recursive: true));
    File(
      p.join(project.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: fixture\n');
    final app = Directory(p.join(project.path, 'App.framework'))..createSync();
    File(p.join(app.path, 'App')).writeAsStringSync('kernel');
    final engine = Directory(p.join(project.path, 'Flutter.xcframework'));
    final framework = Directory(
      p.join(engine.path, 'ios-arm64', 'Flutter.framework'),
    )..createSync(recursive: true);
    File(p.join(framework.path, 'Flutter')).writeAsStringSync('engine');
    final runner = File(p.join(project.path, 'Runner'))
      ..writeAsStringSync('runner');
    final runtime = testIPhoneRuntime();

    Future<String> plistFor(String? sceneDelegateClass) async {
      final context = FlutterBuildContext(
        request: FlutterBuildRequest(
          runtime: runtime,
          projectRoot: project.path,
          bundleId: 'com.example.fixture',
          options: const FlutterBuildOptions(pub: false),
        ),
        flutterRoot: '/unused',
      );
      final bundle = await FlutterBundleAssembler(context).assemble(
        FlutterLinkedArtifacts(
          compiled: FlutterCompiledArtifacts(
            appFramework: app.path,
            nativeAssets: const IosNativeAssetsBuildResult(
              manifestPath: '/unused',
              frameworks: [],
            ),
          ),
          runner: RunnerBinary(
            xcframework: engine.path,
            runnerBinary: runner.path,
            sdkName: runtime.target.buildPlatform.sdkName,
            sceneDelegateClass: sceneDelegateClass,
          ),
          extensions: const [],
        ),
      );
      return File(p.join(bundle, 'Info.plist')).readAsStringSync();
    }

    final fromProject = await plistFor(ProjectRunnerBuilder.sceneDelegateClass);
    expect(fromProject, contains('<string>XcrossSceneDelegate</string>'));
    expect(fromProject, isNot(contains('<string>SceneDelegate</string>')));

    final shim = await plistFor(null);
    expect(shim, contains('<string>SceneDelegate</string>'));
    expect(shim, isNot(contains('XcrossSceneDelegate')));
  });
}
