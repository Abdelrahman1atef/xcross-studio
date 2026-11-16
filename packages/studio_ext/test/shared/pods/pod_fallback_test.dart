import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/pods/pod_report.dart';
import 'package:studio_ext/src/shared/pods/pod_fallback.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File reportFile;
  const handler = PodFallbackHandler();

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pod-fallback-test-');
    reportFile = File(p.join(tempDir.path, 'pods-report.json'));
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('AC-046-24 detectPodFailure detects compile error in converted pod', () {
    const errorOutput = r'''
[1/5] Compiling MyPlugin.swift
C:\Users\user\project\.dart_tool\xcross\Packages\pod-WebRTC-SDK\Sources\WebRTC.swift:42:10: error: cannot find 'RTCVideoCodecInfo' in scope
    let codec = RTCVideoCodecInfo()
                ^~~~~~~~~~~~~~~~~
error: fatalError
''';

    final failure = handler.detectPodFailure(
      errorOutput,
      plugin: 'flutter_webrtc',
    );
    expect(failure, isNotNull);
    expect(failure!.pod, 'WebRTC-SDK');
    expect(failure.isDuplicateSymbols, isFalse);
    expect(
      failure.firstErrorLine,
      contains("cannot find 'RTCVideoCodecInfo' in scope"),
    );
  });

  test('AC-046-24 detectPodFailure detects duplicate symbols', () {
    const errorOutput = r'''
ld: duplicate symbol '_OBJC_CLASS_$_GULAppCheck' in:
    C:\Users\user\project\.dart_tool\xcross\Packages\pod-GoogleUtilities\libGoogleUtilities.a
    C:\Users\user\project\.dart_tool\xcross\Packages\pod-FirebaseCoreInternal\libFirebaseCoreInternal.a
clang: error: linker command failed with exit code 1
''';

    final failure = handler.detectPodFailure(
      errorOutput,
      plugin: 'firebase_core',
    );
    expect(failure, isNotNull);
    expect(failure!.pod, 'GoogleUtilities');
    expect(failure.isDuplicateSymbols, isTrue);
    expect(failure.collidingPods, ['GoogleUtilities', 'FirebaseCoreInternal']);
    expect(failure.symbolName, r'_OBJC_CLASS_$_GULAppCheck');
  });

  test(
    'AC-046-20 detectPodFailure parses real ld64.lld duplicate symbol output naming both pods',
    () {
      const lldErrorOutput = r'''
ld64.lld: error: duplicate symbol: _OBJC_CLASS_$_FBLPromise
>>> defined in /Users/runner/work/app/.dart_tool/xcross/Packages/pod-PromisesObjC/libPromisesObjC.a(FBLPromise.o)
>>> defined in /Users/runner/work/app/.dart_tool/xcross/Packages/pod-PromisesSwift/libPromisesSwift.a(FBLPromise.o)
clang: error: linker command failed with exit code 1
''';

      final failure = handler.detectPodFailure(
        lldErrorOutput,
        plugin: 'promises_plugin',
      );
      expect(failure, isNotNull);
      expect(failure!.isDuplicateSymbols, isTrue);
      expect(failure.symbolName, r'_OBJC_CLASS_$_FBLPromise');
      expect(failure.collidingPods, ['PromisesObjC', 'PromisesSwift']);
      expect(failure.pod, 'PromisesObjC');

      var warningLogged = '';
      final excluded = handler.handleFallback(
        failure: failure,
        reportFile: reportFile,
        plugin: 'promises_plugin',
        logWarning: (w) => warningLogged = w,
      );

      expect(excluded, 'PromisesObjC');
      expect(
        warningLogged,
        contains(
          r'duplicate symbol "_OBJC_CLASS_$_FBLPromise" between PromisesObjC and PromisesSwift',
        ),
      );

      final reports = const PodsReportFile().load(reportFile);
      expect(reports, hasLength(1));
      final report = reports.first;
      expect(report.code, 'pod.duplicate_symbols');
      expect(report.pod, 'PromisesObjC');
      expect(
        report.requiredBy,
        containsAll(['promises_plugin', 'PromisesSwift']),
      );
      expect(
        report.detail,
        r'duplicate symbol "_OBJC_CLASS_$_FBLPromise" between PromisesObjC and PromisesSwift',
      );
    },
  );

  test(
    'AC-046-25 handleFallback in strict mode throws PodStrictBuildException',
    () {
      const failure = PodCompileFailure(
        pod: 'WebRTC-SDK',
        firstErrorLine: 'error: compile failed',
        isDuplicateSymbols: false,
        plugin: 'flutter_webrtc',
      );

      expect(
        () => handler.handleFallback(
          failure: failure,
          reportFile: reportFile,
          plugin: 'flutter_webrtc',
          strict: true,
        ),
        throwsA(
          isA<PodStrictBuildException>()
              .having((e) => e.code, 'code', 'pod.compile_failed')
              .having((e) => e.pod, 'pod', 'WebRTC-SDK')
              .having(
                (e) => e.toString(),
                'toString',
                contains('Automatic fallback is disabled'),
              ),
        ),
      );
    },
  );

  test(
    'AC-046-25 handleFallback in distribution mode throws PodStrictBuildException',
    () {
      const failure = PodCompileFailure(
        pod: 'MobileVLCKit',
        firstErrorLine: 'error: linker duplicate symbols',
        isDuplicateSymbols: true,
        plugin: 'flutter_vlc_player',
      );

      expect(
        () => handler.handleFallback(
          failure: failure,
          reportFile: reportFile,
          plugin: 'flutter_vlc_player',
          distribution: true,
        ),
        throwsA(
          isA<PodStrictBuildException>()
              .having((e) => e.code, 'code', 'pod.duplicate_symbols')
              .having((e) => e.pod, 'pod', 'MobileVLCKit'),
        ),
      );
    },
  );

  test(
    'AC-046-24 handleFallback records report and returns pod to exclude',
    () {
      const failure = PodCompileFailure(
        pod: 'WebRTC-SDK',
        firstErrorLine: 'error: type mismatch',
        isDuplicateSymbols: false,
        plugin: 'flutter_webrtc',
      );

      var warningLogged = '';
      final excluded = handler.handleFallback(
        failure: failure,
        reportFile: reportFile,
        plugin: 'flutter_webrtc',
        logWarning: (w) => warningLogged = w,
      );

      expect(excluded, 'WebRTC-SDK');
      expect(
        warningLogged,
        contains('Plugin "flutter_webrtc" is left out of this build'),
      );
      expect(
        warningLogged,
        contains('Why: SwiftPM failed compiling pod "WebRTC-SDK"'),
      );
      expect(reportFile.existsSync(), isTrue);

      final reports = const PodsReportFile().load(reportFile);
      expect(reports, hasLength(1));
      expect(reports.first.pod, 'WebRTC-SDK');
      expect(reports.first.code, 'pod.compile_failed');
    },
  );
}
