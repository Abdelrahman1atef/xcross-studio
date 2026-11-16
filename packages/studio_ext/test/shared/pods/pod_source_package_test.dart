import 'dart:io';

import 'package:studio_ext/src/shared/pods/pod_settings_converter.dart';
import 'package:studio_ext/src/shared/pods/pod_source_package.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pod-source-pkg-test-');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AC-046-15 ObjC++ and static_framework Package.swift generation', () {
    const generator = PodSourcePackage(
      directoryFactory: Directory.new,
      fileFactory: File.new,
    );

    test(
      'generates Package.swift for onnxruntime-objc with C++17 and onnxruntime-c dependency',
      () {
        final manifestFile = generator.generate(
          packageDir: tempDir,
          pod: 'onnxruntime-objc',
          module: 'onnxruntime_objc',
          iosDeploymentTarget: '11.0',
          settings: const PodTargetSettings(
            cxxLanguageStandard: 'cxx17',
            defines: {'ORT_DISABLE_CONTRIB_OPS': '1'},
            linkedFrameworks: ['Foundation'],
          ),
          dependencies: const ['onnxruntime-c'],
          dependencyModules: const {'onnxruntime-c': 'onnxruntime'},
          isStaticFramework: true,
          hasCxx: true,
        );

        expect(manifestFile.existsSync(), isTrue);
        final text = manifestFile.readAsStringSync();

        expect(text, contains('// swift-tools-version: 5.9'));
        expect(text, contains('// xcross: pod-converter v1'));
        expect(text, contains('name: "pod-onnxruntime-objc"'));
        expect(text, contains('platforms: [.iOS("11.0")]'));
        expect(
          text,
          contains(
            '.library(name: "pod-onnxruntime-objc", targets: ["onnxruntime_objc"])',
          ),
        );
        expect(
          text,
          contains(
            '.package(name: "pod-onnxruntime-c", path: "../pod-onnxruntime-c")',
          ),
        );
        expect(
          text,
          contains(
            '.product(name: "onnxruntime", package: "pod-onnxruntime-c")',
          ),
        );
        expect(text, contains('.define("COCOAPODS")'));
        expect(text, contains('.unsafeFlags(["-USWIFT_PACKAGE"])'));
        expect(text, contains('.define("ORT_DISABLE_CONTRIB_OPS", to: "1")'));
        expect(text, contains('.linkedFramework("Foundation")'));
        expect(text, contains('cxxLanguageStandard: .cxx17'));
      },
    );

    test('generates Package.swift for plain C pod with cLanguageStandard', () {
      final manifestFile = generator.generate(
        packageDir: tempDir,
        pod: 'nanopb',
        module: 'nanopb',
        iosDeploymentTarget: '12.0',
        settings: const PodTargetSettings(
          cLanguageStandard: 'c11',
          defines: {'PB_FIELD_32BIT': '1'},
        ),
      );

      expect(manifestFile.existsSync(), isTrue);
      final text = manifestFile.readAsStringSync();

      expect(text, contains('name: "pod-nanopb"'));
      expect(text, contains('.define("PB_FIELD_32BIT", to: "1")'));
      expect(text, contains('cLanguageStandard: .c11'));
      expect(text, isNot(contains('cxxLanguageStandard')));
    });
  });
}
