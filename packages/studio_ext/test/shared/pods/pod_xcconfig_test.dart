import 'package:studio_ext/src/shared/pods/pod_xcconfig.dart';
import 'package:test/test.dart';

void main() {
  const parser = PodXcconfig();
  const simulator = PodBuildContext(simulator: true, distribution: false);
  const deviceRelease = PodBuildContext(simulator: false, distribution: true);

  ParsedXcconfig parse(Map<String, Object?> source, PodBuildContext context) =>
      parser.parse(
        source,
        context: context,
        pod: 'A',
        podRoots: {'A': 'Sources/A', 'B': '../pod-B/Sources/B'},
        publicHeaders: 'Headers/Public',
      );

  test('AC-046-11 evaluates sdk, arch, and config conditions', () {
    final source = {
      'OTHER_CFLAGS[sdk=iphonesimulator*][arch=arm64]': '-DSIM',
      'OTHER_CFLAGS[sdk=iphoneos*][config=Release]': '-DRELEASE',
      'OTHER_CFLAGS[arch=x86_64]': '-DWRONG',
    };
    expect(parse(source, simulator).values['OTHER_CFLAGS'], ['-DSIM']);
    expect(parse(source, deviceRelease).values['OTHER_CFLAGS'], ['-DRELEASE']);
  });

  test('AC-046-11 expands known variables and records unknown ones', () {
    final result = parse({
      'HEADER_SEARCH_PATHS':
          r'${PODS_TARGET_SRCROOT} ${PODS_ROOT}/B/include '
          r'${PODS_ROOT}/Headers/Public/A $(inherited) ${OTHER}',
    }, simulator);
    expect(
      result.values['HEADER_SEARCH_PATHS']!.single,
      contains('Sources/A ../pod-B/Sources/B/include Headers/Public/A'),
    );
    expect(result.ignored, contains('pod.setting_ignored: OTHER'));
  });

  test('AC-046-11 resolves each pod root and inherited value', () {
    final result = parse({
      'HEADER_SEARCH_PATHS':
          r'${PODS_ROOT}/A/include ${PODS_ROOT}/B/include '
          r'${PODS_ROOT}/Headers/Public/B $(inherited)',
    }, simulator);
    expect(
      result.values['HEADER_SEARCH_PATHS']!.single,
      'Sources/A/include ../pod-B/Sources/B/include Headers/Public/B',
    );
    expect(result.ignored, isEmpty);
  });

  test('AC-046-11 warns for unsupported build directory variable', () {
    final result = parse({
      'HEADER_SEARCH_PATHS': r'${PODS_CONFIGURATION_BUILD_DIR}',
    }, simulator);
    expect(result.ignored, [
      'pod.setting_ignored: PODS_CONFIGURATION_BUILD_DIR',
    ]);
  });

  test('AC-046-11 reports unknown keys', () {
    expect(parse({'MYSTERY': 'value'}, simulator).ignored, [
      'pod.setting_ignored: MYSTERY',
    ]);
  });
}
