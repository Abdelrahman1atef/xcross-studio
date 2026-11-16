import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/pods/pod_patcher.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  const patcher = PodSwiftPackagePatcher();

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pod-patcher-test-');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('AC-046-13 PodSwiftPackagePatcher (T206)', () {
    test(
      'rewrites #if SWIFT_PACKAGE and #if !SWIFT_PACKAGE in Swift source',
      () {
        const source = '''
#if SWIFT_PACKAGE
import GoogleUtilities_Environment
#else
import GoogleUtilities
#endif

#if !SWIFT_PACKAGE
func cocoaPodsOnly() {}
#endif
''';

        final result = patcher.patchContent(source, 'Sources/MyPod/File.swift');

        expect(result.patches, hasLength(2));
        expect(result.patches.first.kind, 'swift_package_macro');
        expect(result.content, contains('#if XCROSS_POD_NOT_SWIFT_PACKAGE'));
        expect(result.content, contains('#if !XCROSS_POD_NOT_SWIFT_PACKAGE'));
        expect(result.content, contains('import GoogleUtilities'));
      },
    );

    test(
      'rewrites public header with SWIFT_PACKAGE to take CocoaPods branch',
      () {
        const header = '''
#ifndef GUL_ENVIRONMENT_H
#define GUL_ENVIRONMENT_H

#if SWIFT_PACKAGE
@import GoogleUtilities_Environment;
#else
#import <GoogleUtilities/GULEnvironment.h>
#endif

#endif
''';

        final result = patcher.patchContent(
          header,
          'Headers/Public/GULEnvironment.h',
        );

        expect(result.patches, hasLength(1));
        expect(result.content, contains('#if XCROSS_POD_NOT_SWIFT_PACKAGE'));
        expect(
          result.content,
          contains('#import <GoogleUtilities/GULEnvironment.h>'),
        );
      },
    );

    test('rewrites compound defined(SWIFT_PACKAGE) expressions', () {
      const code = '''
#if defined(SWIFT_PACKAGE) && !defined(COCOAPODS)
#define ORT_SPM 1
#endif
''';

      final result = patcher.patchContent(code, 'src/defs.h');
      expect(result.patches, hasLength(1));
      expect(
        result.content,
        contains(
          '#if defined(XCROSS_POD_NOT_SWIFT_PACKAGE) && !defined(COCOAPODS)',
        ),
      );
    });

    test(
      'patchFiles updates files in place and writePodMetadata writes xcross-pod.json',
      () {
        final swiftFile = File(
          p.join(tempDir.path, 'Sources', 'MyModule', 'File.swift'),
        )..createSync(recursive: true);
        swiftFile.writeAsStringSync('''
#if SWIFT_PACKAGE
import SPMTarget
#else
import PodTarget
#endif
''');

        final headerFile = File(
          p.join(tempDir.path, 'Headers', 'Public', 'Header.h'),
        )..createSync(recursive: true);
        headerFile.writeAsStringSync('''
#if SWIFT_PACKAGE
#import "SPM.h"
#else
#import "Pod.h"
#endif
''');

        final patches = patcher.patchFiles([
          swiftFile,
          headerFile,
        ], baseDirectory: tempDir.path);
        expect(patches, hasLength(2));

        expect(
          swiftFile.readAsStringSync(),
          contains('XCROSS_POD_NOT_SWIFT_PACKAGE'),
        );
        expect(
          headerFile.readAsStringSync(),
          contains('XCROSS_POD_NOT_SWIFT_PACKAGE'),
        );

        final metaFile = File(p.join(tempDir.path, 'xcross-pod.json'));
        patcher.writePodMetadata(
          metadataFile: metaFile,
          pod: 'MyPod',
          version: '1.2.3',
          patches: patches,
        );

        expect(metaFile.existsSync(), isTrue);
        final json =
            jsonDecode(metaFile.readAsStringSync()) as Map<String, Object?>;
        expect(json['pod'], 'MyPod');
        expect(json['version'], '1.2.3');
        final recordedPatches = json['patches']! as List;
        expect(recordedPatches, hasLength(2));
      },
    );
  });
}
