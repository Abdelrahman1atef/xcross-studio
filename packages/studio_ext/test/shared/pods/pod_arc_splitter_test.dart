import 'package:studio_ext/src/shared/pods/pod_arc_splitter.dart';
import 'package:test/test.dart';

void main() {
  const splitter = PodArcSplitter();

  group('AC-046-13 PodArcSplitter (T205)', () {
    test('golden output for Protobuf 3.11.4 (requires_arc: false)', () {
      final sources = [
        'GPBArray.m',
        'GPBCodedInputStream.m',
        'GPBDescriptor.m',
        'GPBMessage.m',
      ];

      final targets = splitter.splitTargets(
        moduleName: 'protobuf',
        sources: sources,
        requiresArc: false,
      );

      expect(targets, hasLength(1));
      expect(targets.first.name, 'protobuf');
      expect(targets.first.isArc, isFalse);
      expect(targets.first.flags, contains('-fno-objc-arc'));
      expect(targets.first.sources, sources);
    });

    test(
      'splits ARC target and non-ARC target when requires_arc is a file list',
      () {
        final sources = [
          'Source/LegacyMemory.m',
          'Source/LegacyParser.m',
          'Source/ModernArcBridge.m',
        ];

        final targets = splitter.splitTargets(
          moduleName: 'MyMixedPod',
          sources: sources,
          requiresArc: ['ModernArcBridge.m'],
        );

        expect(targets, hasLength(2));

        final noArc = targets.firstWhere((t) => t.name == 'MyMixedPod_noarc');
        expect(noArc.isArc, isFalse);
        expect(noArc.flags, contains('-fno-objc-arc'));
        expect(noArc.sources, [
          'Source/LegacyMemory.m',
          'Source/LegacyParser.m',
        ]);

        final arc = targets.firstWhere((t) => t.name == 'MyMixedPod');
        expect(arc.isArc, isTrue);
        expect(arc.sources, ['Source/ModernArcBridge.m']);
        expect(arc.dependencies, ['MyMixedPod_noarc']);
      },
    );

    test(
      'golden output for GoogleToolboxForMac subspecs with distinct compiler flags',
      () {
        final sources = ['GTMDefines.m', 'GTMStringEncoding.m', 'GTMLogger.m'];

        final targets = splitter.splitTargets(
          moduleName: 'GoogleToolboxForMac',
          sources: sources,
          requiresArc: true,
          subspecFlags: {
            'StringEncoding': ['-fno-builtin'],
            'Logger': ['-DGTM_LOGGER_ENABLED=1'],
          },
        );

        expect(targets, hasLength(3));

        final stringEncoding = targets.firstWhere(
          (t) => t.name == 'GoogleToolboxForMac_StringEncoding',
        );
        expect(stringEncoding.sources, ['GTMStringEncoding.m']);
        expect(stringEncoding.flags, ['-fno-builtin']);

        final logger = targets.firstWhere(
          (t) => t.name == 'GoogleToolboxForMac_Logger',
        );
        expect(logger.sources, ['GTMLogger.m']);
        expect(logger.flags, ['-DGTM_LOGGER_ENABLED=1']);

        final main = targets.firstWhere((t) => t.name == 'GoogleToolboxForMac');
        expect(main.sources, ['GTMDefines.m']);
        expect(
          main.dependencies,
          containsAll([
            'GoogleToolboxForMac_StringEncoding',
            'GoogleToolboxForMac_Logger',
          ]),
        );
      },
    );
  });
}
