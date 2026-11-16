import 'package:studio_ext/src/shared/pods/pod_dependent_headers.dart';
import 'package:test/test.dart';

void main() {
  const resolver = PodDependentHeaders();

  group('AC-046-14 PodDependentHeaders (T203)', () {
    test('existing plugins with no pod dependencies get no search paths', () {
      final flags = resolver.resolveHeaderFlags(
        dependent: 'url_launcher_ios',
        dependencies: const [],
        podModules: const {},
        podPaths: const {},
        podPublicHeaders: const {},
      );

      expect(flags, isEmpty);
    });

    test('injects per-dependent -I for angle and quoted headers', () {
      final flags = resolver.resolveHeaderFlags(
        dependent: 'my_plugin',
        dependencies: ['GoogleToolboxForMac'],
        podModules: {'GoogleToolboxForMac': 'GoogleToolboxForMac'},
        podPaths: {'GoogleToolboxForMac': '../pod-GoogleToolboxForMac'},
        podPublicHeaders: {
          'GoogleToolboxForMac': ['GTMLogger.h', 'GTMDefines.h'],
        },
      );

      expect(flags, [
        '-I',
        '../pod-GoogleToolboxForMac/Headers/Public',
        '-I',
        '../pod-GoogleToolboxForMac/Headers/Public/GoogleToolboxForMac',
      ]);
    });

    test(
      'detects flat header clash between two dependency pods and notifies onClash',
      () {
        final clashes = <PodHeaderClash>[];

        final flags = resolver.resolveHeaderFlags(
          dependent: 'consumer_plugin',
          dependencies: ['PodA', 'PodB'],
          podModules: {'PodA': 'ModA', 'PodB': 'ModB'},
          podPaths: {'PodA': '../pod-PodA', 'PodB': '../pod-PodB'},
          podPublicHeaders: {
            'PodA': ['Common.h', 'UniqueA.h'],
            'PodB': ['Common.h', 'UniqueB.h'],
          },
          onClash: clashes.add,
        );

        expect(clashes, hasLength(1));
        expect(clashes.first.header, 'Common.h');
        expect(clashes.first.firstPod, 'PodA');
        expect(clashes.first.secondPod, 'PodB');
        expect(
          clashes.first.warningMessage,
          contains('Header "Common.h" is exported by both "PodA" and "PodB"'),
        );

        // Both pods' -I paths are still injected
        expect(flags, [
          '-I',
          '../pod-PodA/Headers/Public',
          '-I',
          '../pod-PodA/Headers/Public/ModA',
          '-I',
          '../pod-PodB/Headers/Public',
          '-I',
          '../pod-PodB/Headers/Public/ModB',
        ]);
      },
    );
  });
}
