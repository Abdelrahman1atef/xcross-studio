import 'dart:io';

import 'package:darwin_sdk_kit/target/iphone/iphone_build_platform.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/flutter/build/ios_deployment_target.dart';
import 'package:xcross/src/shared/flutter/build/ios_plugins.dart';

import 'swiftpm_test_context.dart';

void main() {
  late Directory tempDir;
  final runtime = testSwiftPmRuntime();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('stager-pod-test-');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test(
    'AC-046-8 stages converted pods under Packages/pod-<Pod> and rewrites dependencies',
    () async {
      // Create a mock converted pod in cache
      final podCacheDir = Directory(
        p.join(tempDir.path, 'cache', 'pod-WebRTC-SDK'),
      )..createSync(recursive: true);
      File(p.join(podCacheDir.path, 'Package.swift')).writeAsStringSync('''
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
  name: "pod-WebRTC-SDK",
  products: [.library(name: "WebRTC", targets: ["WebRTC"])],
  targets: [.binaryTarget(name: "WebRTC", path: "Frameworks/WebRTC.xcframework")]
)
''');

      // Create a mock plugin depending on pod-WebRTC-SDK
      final pluginRoot = p.join(tempDir.path, 'my_plugin');
      final pluginIosDir = Directory(p.join(pluginRoot, 'ios', 'my_plugin'))
        ..createSync(recursive: true);
      File(p.join(pluginIosDir.path, 'Package.swift')).writeAsStringSync('''
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
  name: "my_plugin",
  dependencies: [
    .package(name: "pod-WebRTC-SDK", path: "../dummy/path")
  ],
  targets: [.target(name: "my_plugin", dependencies: ["pod-WebRTC-SDK"])]
)
''');
      File(
        p.join(pluginRoot, 'pubspec.yaml'),
      ).writeAsStringSync('name: my_plugin\n');

      final plugin = IosPlugin(
        fileSystem: runtime.host.fileSystem,
        name: 'my_plugin',
        packageRoot: pluginRoot,
      );

      final flutterFwk = Directory(p.join(tempDir.path, 'Flutter.xcframework'))
        ..createSync(recursive: true);
      File(
        p.join(flutterFwk.path, 'Info.plist'),
      ).writeAsStringSync('<plist></plist>');

      final outputDir = p.join(tempDir.path, 'staged_build');

      await runtime.workspaceStager.writeGeneratedPackages(
        outputDir: outputDir,
        plugins: [plugin],
        flutterXcframework: flutterFwk.path,
        deploymentTarget: const IosDeploymentTarget(
          '15.0',
          platform: IPhoneBuildPlatform(),
        ),
        podPackages: {'WebRTC-SDK': podCacheDir.path},
      );

      // Verify Packages/pod-WebRTC-SDK alias exists
      final stagedPod = Directory(
        p.join(outputDir, 'Packages', 'pod-WebRTC-SDK'),
      );
      expect(stagedPod.existsSync(), isTrue);

      // Verify plugin Package.swift was rewritten to point to Packages/pod-WebRTC-SDK
      final pluginManifest = File(
        p.join(outputDir, 'Packages', 'my_plugin', 'Package.swift'),
      );
      expect(pluginManifest.existsSync(), isTrue);
      final content = pluginManifest.readAsStringSync();
      expect(content, contains('pod-WebRTC-SDK'));
    },
  );
}
