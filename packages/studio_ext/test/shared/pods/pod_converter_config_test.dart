import 'package:studio_ext/shared/pods/pod_converter_config.dart';
import 'package:test/test.dart';

void main() {
  test(
    'AC-046-23 converter defaults off with all kinds enabled by Phase 3',
    () {
      final config = PodConverterConfig.fromEnvironment(const {});
      expect(config.enabled, isFalse);
      expect(config.kinds, {'binary', 'objc', 'swift', 'mixed'});
      expect(config.skipped, isEmpty);
    },
  );

  test('AC-046-24 reads opt-in, kinds, and skipped pods', () {
    final config = PodConverterConfig.fromEnvironment(const {
      'XCROSS_POD_CONVERTER': 'on',
      'XCROSS_POD_KINDS': 'binary, objc,invalid',
      'XCROSS_POD_SKIP': 'A, B,',
    });
    expect(config.enabled, isTrue);
    expect(config.kinds, {'binary', 'objc'});
    expect(config.skipped, {'A', 'B'});
  });
}
