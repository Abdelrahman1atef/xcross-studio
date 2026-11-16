import 'package:studio_ext/src/shared/pods/pod_settings_converter.dart';
import 'package:studio_ext/src/shared/pods/pod_xcconfig.dart';
import 'package:test/test.dart';

void main() {
  const xcconfigParser = PodXcconfig();
  const converter = PodSettingsConverter();
  const context = PodBuildContext(simulator: false, distribution: false);

  group('AC-046-13 PodSettingsConverter (T204)', () {
    test(
      'onnxruntime-objc flags: drops -Werror, maps -std=c++17, keeps visibility and warnings',
      () {
        final parsed = xcconfigParser.parse(
          {
            'OTHER_CPLUSPLUSFLAGS':
                '-Werror -Werror=return-type -std=c++17 -fvisibility=hidden -Wall -Wextra -DORT_VERSION=1.16',
          },
          context: context,
          pod: 'onnxruntime-objc',
          podRoots: {'onnxruntime-objc': 'Sources/onnxruntime_objc'},
          publicHeaders: 'Headers/Public',
        );

        final settings = converter.convert(
          xcconfig: parsed,
          pod: 'onnxruntime-objc',
        );

        expect(settings.cxxFlags, isNot(contains('-Werror')));
        expect(settings.cxxFlags, isNot(contains('-Werror=return-type')));
        expect(settings.cxxFlags, isNot(contains('-std=c++17')));
        expect(settings.cxxLanguageStandard, 'cxx17');
        expect(
          settings.cxxFlags,
          containsAll(['-fvisibility=hidden', '-Wall', '-Wextra']),
        );
        expect(settings.defines['ORT_VERSION'], '1.16');
      },
    );

    test(
      'GoogleUtilities and GoogleDataTransport HEADER_SEARCH_PATHS expansion',
      () {
        final parsed = xcconfigParser.parse(
          {
            'HEADER_SEARCH_PATHS':
                r'${PODS_TARGET_SRCROOT}/GoogleUtilities/Environment/Public ${PODS_ROOT}/GoogleUtilities/Private $(inherited)',
          },
          context: context,
          pod: 'GoogleUtilities',
          podRoots: {'GoogleUtilities': 'Sources/GoogleUtilities'},
          publicHeaders: 'Headers/Public',
        );

        final settings = converter.convert(
          xcconfig: parsed,
          pod: 'GoogleUtilities',
        );

        expect(settings.headerSearchPaths, [
          'Sources/GoogleUtilities/GoogleUtilities/Environment/Public',
          'Sources/GoogleUtilities/Private',
        ]);
      },
    );

    test(
      r'GCC_PREPROCESSOR_DEFINITIONS skips $(inherited) and parses definitions',
      () {
        final parsed = xcconfigParser.parse(
          {
            'GCC_PREPROCESSOR_DEFINITIONS':
                r'$(inherited) COCOAPODS=1 FOO="BAR" BAZ',
          },
          context: context,
          pod: 'MyPod',
          podRoots: {},
          publicHeaders: 'Headers/Public',
        );

        final settings = converter.convert(xcconfig: parsed, pod: 'MyPod');

        expect(settings.defines['COCOAPODS'], '1');
        expect(settings.defines['FOO'], 'BAR');
        expect(settings.defines['BAZ'], isNull);
        expect(settings.defines.containsKey(r'$(inherited)'), isFalse);
      },
    );

    test('CLANG_CXX_LIBRARY libc++ accepted, other values warn', () {
      final parsed = xcconfigParser.parse(
        {'CLANG_CXX_LIBRARY': 'libstdc++'},
        context: context,
        pod: 'OldPod',
        podRoots: {},
        publicHeaders: 'Headers/Public',
      );

      final settings = converter.convert(xcconfig: parsed, pod: 'OldPod');

      expect(
        settings.ignoredSettings.any(
          (w) => w.contains('CLANG_CXX_LIBRARY=libstdc++'),
        ),
        isTrue,
      );
    });

    test('CLANG_ENABLE_OBJC_WEAK adds -fobjc-weak', () {
      final parsed = xcconfigParser.parse(
        {'CLANG_ENABLE_OBJC_WEAK': 'YES'},
        context: context,
        pod: 'WeakPod',
        podRoots: {},
        publicHeaders: 'Headers/Public',
      );

      final settings = converter.convert(xcconfig: parsed, pod: 'WeakPod');

      expect(settings.cFlags, contains('-fobjc-weak'));
      expect(settings.cxxFlags, contains('-fobjc-weak'));
    });

    test(
      'OTHER_SWIFT_FLAGS -D maps to swiftDefines; C flags not passed to Swift',
      () {
        final parsed = xcconfigParser.parse(
          {
            'OTHER_SWIFT_FLAGS': '-DFEATURE_X -w',
            'OTHER_CFLAGS': '-Wno-unused',
          },
          context: context,
          pod: 'SwiftPod',
          podRoots: {},
          publicHeaders: 'Headers/Public',
        );

        final settings = converter.convert(xcconfig: parsed, pod: 'SwiftPod');

        expect(settings.swiftDefines.containsKey('FEATURE_X'), isTrue);
        expect(settings.swiftFlags, isNot(contains('-Wno-unused')));
        expect(
          settings.ignoredSettings.any(
            (w) => w.contains('OTHER_SWIFT_FLAGS -w'),
          ),
          isTrue,
        );
      },
    );

    test(
      'user_target_xcconfig processes linker keys and warns on non-linker keys',
      () {
        final settings = converter.convert(
          xcconfig: const ParsedXcconfig({}, []),
          pod: 'LinkerPod',
          userTargetXcconfig: {
            'OTHER_LDFLAGS':
                '-framework Security -weak_framework AudioToolbox -lc++ -lz',
            'GCC_OPTIMIZATION_LEVEL': '3',
          },
        );

        expect(settings.linkedFrameworks, ['Security']);
        expect(
          settings.linkerFlags,
          containsAll(['-weak_framework', 'AudioToolbox']),
        );
        expect(settings.linkedLibraries, containsAll(['c++', 'z']));
        expect(
          settings.ignoredSettings.any(
            (w) => w.contains('user_target_xcconfig GCC_OPTIMIZATION_LEVEL'),
          ),
          isTrue,
        );
      },
    );
  });
}
