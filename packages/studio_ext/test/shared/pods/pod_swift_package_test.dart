import 'dart:io';

import 'package:studio_ext/src/shared/pods/pod_swift_package.dart';
import 'package:test/test.dart';

void main() {
  group('AC-046-11 Swift language mode resolution', () {
    test('defaults to Swift 5 when no versions given', () {
      final mode = PodSwiftPackage.resolveLanguageMode(const []);
      expect(mode, PodSwiftLanguageMode.v5);
      expect(mode.code, '.v5');
    });

    test('selects highest accepted mode when multiple versions supported', () {
      final mode = PodSwiftPackage.resolveLanguageMode(const [
        '4.0',
        '4.2',
        '5.0',
      ]);
      expect(mode, PodSwiftLanguageMode.v5);
    });

    test('selects 4.2 when highest is 4.2', () {
      final mode = PodSwiftPackage.resolveLanguageMode(const ['4.0', '4.2']);
      expect(mode, PodSwiftLanguageMode.v4_2);
      expect(mode.code, '.v4_2');
    });

    test('selects 4.0 when only 4.0 supported', () {
      final mode = PodSwiftPackage.resolveLanguageMode(const ['4.0']);
      expect(mode, PodSwiftLanguageMode.v4);
      expect(mode.code, '.v4');
    });

    test('selects 6 when Swift 6 supported', () {
      final mode = PodSwiftPackage.resolveLanguageMode(const ['5.0', '6.0']);
      expect(mode, PodSwiftLanguageMode.v6);
      expect(mode.code, '.version("6")');
    });
  });

  group('AC-046-11 Module name and identifier sanitization', () {
    test('sanitizes hyphens and invalid chars', () {
      expect(
        PodSwiftPackage.sanitizeIdentifier('my-swift-pod'),
        'my_swift_pod',
      );
      expect(
        PodSwiftPackage.sanitizeIdentifier('TensorFlowLiteSwift'),
        'TensorFlowLiteSwift',
      );
      expect(PodSwiftPackage.sanitizeIdentifier('123pod'), '_123pod');
    });
  });

  group('AC-046-11 Golden Package.swift for Swift-only pod', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pod-swift-test-');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'generates Package.swift with swiftLanguageVersions and COCOAPODS define',
      () {
        const generator = PodSwiftPackage(
          directoryFactory: Directory.new,
          fileFactory: File.new,
        );

        final manifestFile = generator.generate(
          packageDir: tempDir,
          pod: 'TensorFlowLiteSwift',
          module: 'TensorFlowLiteSwift',
          iosDeploymentTarget: '12.0',
          dependencies: const ['TensorFlowLiteC'],
          linkedFrameworks: const ['Accelerate'],
          defines: const ['TFL_USE_SHERPACK'],
        );

        expect(manifestFile.existsSync(), isTrue);
        final text = manifestFile.readAsStringSync();

        expect(text, contains('// swift-tools-version: 5.9'));
        expect(text, contains('// xcross: pod-converter v1'));
        expect(text, contains('name: "pod-TensorFlowLiteSwift"'));
        expect(text, contains('platforms: [.iOS("12.0")]'));
        expect(
          text,
          contains(
            '.library(name: "pod-TensorFlowLiteSwift", targets: ["TensorFlowLiteSwift"])',
          ),
        );
        expect(
          text,
          contains(
            '.package(name: "pod-TensorFlowLiteC", path: "../pod-TensorFlowLiteC")',
          ),
        );
        expect(
          text,
          contains(
            '.product(name: "TensorFlowLiteC", package: "pod-TensorFlowLiteC")',
          ),
        );
        expect(text, contains('path: "Sources/TensorFlowLiteSwift"'));
        expect(text, contains('.define("COCOAPODS")'));
        expect(text, contains('.define("TFL_USE_SHERPACK")'));
        expect(text, contains('.linkedFramework("Accelerate")'));
        expect(text, contains('swiftLanguageVersions: [.v5]'));
      },
    );
  });
}
