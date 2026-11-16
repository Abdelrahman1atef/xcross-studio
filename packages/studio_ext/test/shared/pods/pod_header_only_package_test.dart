import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/pods/pod_header_only_package.dart';
import 'package:studio_ext/src/shared/pods/pod_source_layout.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  const generator = PodHeaderOnlyPackage(
    directoryFactory: Directory.new,
    fileFactory: File.new,
  );
  const layout = PodSourceLayout(
    directoryFactory: Directory.new,
    fileFactory: File.new,
    linkFactory: Link.new,
  );

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pod-header-only-test-');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('AC-046-13 PodHeaderOnlyPackage (T207)', () {
    test('golden output for GoogleMLKit 9.0.0 with no second module map', () {
      final pkgDir = Directory(p.join(tempDir.path, 'pod-GoogleMLKit'));
      final headerFile = File(p.join(tempDir.path, 'MLKit.h'))
        ..createSync(recursive: true);
      headerFile.writeAsStringSync('// MLKit umbrella header');

      const ownModuleMap = '''
framework module GoogleMLKit {
  umbrella header "GoogleMLKit/MLKit.h"
  export *
  module * { export * }
}
''';

      // 1. Header layout with own module map
      layout.layOutPod(
        packageDir: pkgDir,
        podName: 'GoogleMLKit',
        version: '9.0.0',
        moduleName: 'GoogleMLKit',
        sourceFiles: const {},
        publicHeaders: {'MLKit.h': headerFile},
        privateHeaders: const {},
        customModuleMap: ownModuleMap,
      );

      // 2. Package.swift generation
      final manifestFile = generator.generate(
        packageDir: pkgDir,
        pod: 'GoogleMLKit',
        module: 'GoogleMLKit',
        iosDeploymentTarget: '13.0',
        dependencies: ['MLKitVision', 'MLKitCommon'],
        customModuleMap: ownModuleMap,
      );

      expect(manifestFile.existsSync(), isTrue);
      final manifest = manifestFile.readAsStringSync();

      expect(manifest, contains('name: "pod-GoogleMLKit"'));
      expect(manifest, contains('platforms: [.iOS("13.0")]'));
      expect(
        manifest,
        contains('.library(name: "pod-GoogleMLKit", targets: ["GoogleMLKit"])'),
      );
      expect(
        manifest,
        contains(
          '.package(name: "pod-MLKitVision", path: "../pod-MLKitVision")',
        ),
      );
      expect(
        manifest,
        contains(
          '.package(name: "pod-MLKitCommon", path: "../pod-MLKitCommon")',
        ),
      );
      expect(
        manifest,
        contains('sources: ["Sources/GoogleMLKit/placeholder.c"]'),
      );
      expect(manifest, contains('publicHeadersPath: "Headers/Public"'));

      // Check placeholder.c exists
      final placeholder = File(
        p.join(pkgDir.path, 'Sources', 'GoogleMLKit', 'placeholder.c'),
      );
      expect(placeholder.existsSync(), isTrue);

      // Verify Headers/Public/module.modulemap has the pod's own map and no second map was made
      final mapFile = File(
        p.join(pkgDir.path, 'Headers', 'Public', 'module.modulemap'),
      );
      expect(mapFile.existsSync(), isTrue);
      expect(mapFile.readAsStringSync(), ownModuleMap);

      final secondMap = File(
        p.join(
          pkgDir.path,
          'Headers',
          'Public',
          'GoogleMLKit',
          'module.modulemap',
        ),
      );
      expect(secondMap.existsSync(), isFalse);
    });
  });
}
