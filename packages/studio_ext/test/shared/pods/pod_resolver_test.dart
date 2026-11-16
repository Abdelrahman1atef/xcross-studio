import 'dart:convert';
import 'dart:io';

import 'package:studio_ext/src/shared/pods/pod_consumer.dart';
import 'package:studio_ext/src/shared/pods/pod_resolver.dart';
import 'package:test/test.dart';

void main() {
  const resolver = PodResolver();
  test('AC-046-4 prefers a valid lock pin and warns on a stale one', () {
    final available = {
      'A': [
        const PodCandidate(version: '2.0', iosMinimum: '13.0'),
        const PodCandidate(version: '1.0', iosMinimum: '12.0'),
      ],
    };
    final roots = [const PodConstraint('A', '>= 1.0', 'plugin')];
    expect(
      resolver
          .resolve(
            roots: roots,
            available: available,
            iosTarget: '13.0',
            lockPins: {'A': '1.0'},
          )
          .pods['A']!
          .version,
      '1.0',
    );
    final stale = resolver.resolve(
      roots: [const PodConstraint('A', '>= 2.0', 'plugin')],
      available: available,
      iosTarget: '13.0',
      lockPins: {'A': '1.0'},
    );
    expect(stale.pods['A']!.version, '2.0');
    expect(stale.staleLocks, ['A 1.0 -> 2.0']);
    expect(stale.warnings.single, contains('pod.lock_stale'));
    expect(
      resolver
          .resolve(roots: roots, available: available, iosTarget: '13.0')
          .pods['A']!
          .version,
      '2.0',
    );
  });

  test('AC-046-4 backtracks and filters iOS minimum', () {
    final result = resolver.resolve(
      roots: [const PodConstraint('A', '>= 1.0', 'plugin')],
      available: {
        'A': [
          const PodCandidate(version: '3.0', iosMinimum: '16.0'),
          const PodCandidate(
            version: '2.0',
            iosMinimum: '13.0',
            dependencies: [PodConstraint('B', '< 2.0', 'A 2.0')],
          ),
          const PodCandidate(
            version: '1.0',
            iosMinimum: '12.0',
            dependencies: [PodConstraint('B', '>= 2.0', 'A 1.0')],
          ),
        ],
        'B': [const PodCandidate(version: '2.0', iosMinimum: '12.0')],
      },
      iosTarget: '13.0',
    );
    expect(result.pods['A']!.version, '1.0');
    expect(result.pods['B']!.version, '2.0');
  });

  test('AC-046-4 reports each conflicting source', () {
    expect(
      () => resolver.resolve(
        roots: [
          const PodConstraint('A', '>= 2.0', 'plugin one'),
          const PodConstraint('A', '< 2.0', 'plugin two'),
        ],
        available: {
          'A': [const PodCandidate(version: '2.0', iosMinimum: '12.0')],
        },
        iosTarget: '13.0',
      ),
      throwsA(
        isA<PodResolveConflict>()
            .having(
              (error) => error.constraints.map((c) => c.source),
              'sources',
              ['plugin one', 'plugin two'],
            )
            .having(
              (error) => error.toString(),
              'report',
              allOf(contains('plugin one'), contains('plugin two')),
            ),
      ),
    );
  });

  test('AC-046-4 permits a pinned prerelease', () {
    final result = resolver.resolve(
      roots: [const PodConstraint('MLImage', '>= 1.0.0-beta8', 'MLKit')],
      available: {
        'MLImage': [
          const PodCandidate(version: '1.0.0-beta8', iosMinimum: '15.5'),
        ],
      },
      iosTarget: '15.5',
      lockPins: {'MLImage': '1.0.0-beta8'},
    );
    expect(result.pods['MLImage']!.version, '1.0.0-beta8');
  });

  test('AC-046-4 bounds resolver search steps', () {
    expect(
      () => const PodResolver(stepLimit: 1).resolve(
        roots: [const PodConstraint('A', '>= 1.0', 'plugin')],
        available: {
          'A': [const PodCandidate(version: '1.0', iosMinimum: '12.0')],
        },
        iosTarget: '13.0',
      ),
      throwsA(
        isA<PodResolveConflict>().having(
          (error) => error.steps,
          'steps',
          greaterThan(1),
        ),
      ),
    );
  });

  test('AC-046-4 identifies an iOS minimum with no compatible version', () {
    expect(
      () => resolver.resolve(
        roots: [const PodConstraint('A', '>= 1.0', 'plugin')],
        available: {
          'A': [const PodCandidate(version: '2.0', iosMinimum: '16.0')],
        },
        iosTarget: '15.0',
      ),
      throwsA(
        isA<PodIosMinimum>().having(
          (error) => error.minimum,
          'minimum',
          '16.0',
        ),
      ),
    );
  });

  test('AC-046-4 resolves the saved 12-pod ML Kit graph', () {
    final available = <String, List<PodCandidate>>{};
    final files = Directory(
      'test/fixtures/pods/mlkit',
    ).listSync().whereType<File>();
    for (final file in files) {
      final spec = (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)
          .cast<String, Object?>();
      final name = spec['name']! as String;
      final selected = switch (name) {
        'GoogleMLKit' => ['MLKitCore', 'TextRecognition'],
        'GoogleToolboxForMac' => ['Defines', 'Logger', 'NSData+zlib'],
        'GoogleUtilities' => [
          'Environment',
          'Logger',
          'Privacy',
          'UserDefaults',
        ],
        'GTMSessionFetcher' => ['Core'],
        _ => null,
      };
      final view = const PodConsumer().build(spec, selected: selected);
      final dependencies = <PodConstraint>[];
      final raw = view.attributes['dependencies'];
      if (raw is Map) {
        for (final entry in raw.entries) {
          final requirement = entry.value is List
              ? (entry.value as List).join(', ')
              : entry.value.toString();
          dependencies.add(
            PodConstraint(entry.key.toString(), requirement, name),
          );
        }
      }
      final platforms = spec['platforms']! as Map;
      available[name] = [
        PodCandidate(
          version: spec['version']! as String,
          iosMinimum: platforms['ios']! as String,
          dependencies: dependencies,
        ),
      ];
    }
    final graph = resolver.resolve(
      roots: [
        const PodConstraint('MLKitVision', '~> 10.0.0', 'google_mlkit_commons'),
        const PodConstraint(
          'GoogleMLKit/TextRecognition',
          '~> 9.0.0',
          'google_mlkit_text_recognition',
        ),
      ],
      available: available,
      iosTarget: '15.5',
    );
    expect(graph.pods.keys, hasLength(12));
    expect(graph.pods['MLImage']!.version, '1.0.0-beta8');
    expect(graph.subspecs['GoogleMLKit'], contains('TextRecognition'));
    expect(graph.requiredBy['MLKitVision'], contains('google_mlkit_commons'));
    expect(graph.sources['MLKitVision'], 'resolved');
  });

  test('AC-046-4 resolves the published goSellSDK ErrorReporting graph', () {
    final available = <String, List<PodCandidate>>{};
    final files = Directory(
      'test/fixtures/pods/tap',
    ).listSync().whereType<File>();
    for (final file in files) {
      final spec = (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)
          .cast<String, Object?>();
      final name = spec['name']! as String;
      final selected = switch (name) {
        'goSellSDK' => ['Core', 'ErrorReporting'],
        'SwiftyRSA' => ['ObjC'],
        _ => null,
      };
      final view = const PodConsumer().build(spec, selected: selected);
      final dependencies = <PodConstraint>[];
      final raw = view.attributes['dependencies'];
      if (raw is Map) {
        for (final entry in raw.entries) {
          final requirement = entry.value is List
              ? (entry.value as List).join(', ')
              : entry.value.toString();
          dependencies.add(
            PodConstraint(entry.key.toString(), requirement, name),
          );
        }
      }
      final platforms = spec['platforms'] as Map?;
      available[name] = [
        PodCandidate(
          version: spec['version']! as String,
          iosMinimum: platforms?['ios']?.toString() ?? '8.0',
          dependencies: dependencies,
        ),
      ];
    }
    final graph = resolver.resolve(
      roots: [
        const PodConstraint(
          'goSellSDK/ErrorReporting',
          '2.3.49',
          'go_sell_sdk_flutter',
        ),
      ],
      available: available,
      iosTarget: '15.0',
    );
    expect(graph.pods.keys, hasLength(19));
    expect(graph.pods['TapCardVlidatorKit-iOS']!.version, '1.0.26');

    final goSell =
        (jsonDecode(
                  File(
                    'test/fixtures/pods/tap/goSellSDK-2.3.49.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>)
            .cast<String, Object?>();
    final core = const PodConsumer().build(goSell);
    final coreDependencies = core.attributes['dependencies']! as Map;
    available['goSellSDK'] = [
      PodCandidate(
        version: '2.3.49',
        iosMinimum: '11.0',
        dependencies: [
          for (final name in coreDependencies.keys)
            PodConstraint(name.toString(), '', 'goSellSDK/Core'),
        ],
      ),
    ];
    final pluginGraph = resolver.resolve(
      roots: [
        const PodConstraint(
          'goSellSDK',
          '2.3.49',
          'go_sell_sdk_flutter 2.4.29',
        ),
      ],
      available: available,
      iosTarget: '15.0',
    );
    expect(pluginGraph.pods.keys, hasLength(17));
  });

  test(
    'AC-046-16 resolves two plugins sharing a pod with different subspecs into one package with subspec union',
    () {
      final available = {
        'SharedLib': [
          const PodCandidate(version: '1.2.0', iosMinimum: '12.0'),
          const PodCandidate(version: '1.1.0', iosMinimum: '12.0'),
          const PodCandidate(version: '1.0.0', iosMinimum: '11.0'),
        ],
      };

      final roots = [
        const PodConstraint('SharedLib/Core', '~> 1.0', 'plugin_audio'),
        const PodConstraint('SharedLib/Logging', '>= 1.1', 'plugin_video'),
      ];

      final resolution = resolver.resolve(
        roots: roots,
        available: available,
        iosTarget: '13.0',
      );

      // 1. Exactly one package per pod
      expect(resolution.pods.keys, ['SharedLib']);
      expect(resolution.pods['SharedLib']!.version, '1.2.0');

      // 2. Subspecs union
      expect(resolution.subspecs['SharedLib'], {'Core', 'Logging'});

      // 3. Required by both plugins
      expect(
        resolution.requiredBy['SharedLib'],
        containsAll(['plugin_audio', 'plugin_video']),
      );
    },
  );
}
