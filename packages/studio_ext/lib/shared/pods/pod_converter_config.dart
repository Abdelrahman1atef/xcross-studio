/// Phase-gated converter switches read once at the CLI composition root.
final class PodConverterConfig {
  const PodConverterConfig({
    required this.enabled,
    required this.kinds,
    required this.skipped,
  });

  factory PodConverterConfig.fromEnvironment(Map<String, String> environment) {
    const enabledByPhase = <String>{'binary', 'objc', 'swift', 'mixed'};
    const validKinds = {'binary', 'objc', 'swift', 'mixed'};
    final kindsValue = environment['XCROSS_POD_KINDS'];
    final kinds = kindsValue == null
        ? enabledByPhase
        : kindsValue
              .split(',')
              .map((kind) => kind.trim())
              .where(validKinds.contains)
              .toSet();
    final skipped =
        environment['XCROSS_POD_SKIP']
            ?.split(',')
            .map((pod) => pod.trim())
            .where((pod) => pod.isNotEmpty)
            .toSet() ??
        <String>{};
    return PodConverterConfig(
      enabled: environment['XCROSS_POD_CONVERTER'] == 'on',
      kinds: kinds,
      skipped: skipped,
    );
  }

  final bool enabled;
  final Set<String> kinds;
  final Set<String> skipped;
}
