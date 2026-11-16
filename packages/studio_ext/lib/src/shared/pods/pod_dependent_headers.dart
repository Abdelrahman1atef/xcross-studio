import 'package:meta/meta.dart';

/// Represents a collision between two dependency pods exporting the same flat header (§8.5.5).
@internal
@immutable
final class PodHeaderClash {
  const PodHeaderClash({
    required this.header,
    required this.firstPod,
    required this.secondPod,
  });

  final String header;
  final String firstPod;
  final String secondPod;

  String get warningMessage =>
      '[pod.header_clash] Header "$header" is exported by both "$firstPod" and "$secondPod"; '
      'using "$firstPod" (first in dependency graph).';
}

/// Computes per-dependent header search paths (-I) and detects header collisions (§8.5.5).
@internal
final class PodDependentHeaders {
  const PodDependentHeaders();

  /// Computes the `-I` compiler flags for [dependent] given its transitive pod [dependencies].
  ///
  /// - Only the dependent's targets receive these flags; other plugins receive none.
  /// - Injects `-I <podPath>/Headers/Public` (for angle imports `<Module/X.h>`) and
  ///   `-I <podPath>/Headers/Public/<Module>` (for quoted `"X.h"` imports).
  /// - Detects flat header clashes between multiple pods in [dependencies], invoking
  ///   [onClash] when a collision occurs (the first pod in graph order wins).
  List<String> resolveHeaderFlags({
    required String dependent,
    required List<String> dependencies,
    required Map<String, String> podModules,
    required Map<String, String> podPaths,
    required Map<String, List<String>> podPublicHeaders,
    void Function(PodHeaderClash)? onClash,
  }) {
    if (dependencies.isEmpty) {
      return const [];
    }

    final flags = <String>[];
    final claimedHeaders = <String, String>{}; // header basename -> podName

    for (final pod in dependencies) {
      final module = podModules[pod] ?? pod;
      final podPath = podPaths[pod];
      if (podPath == null) continue;

      // Check for flat header collisions
      final headers = podPublicHeaders[pod] ?? const [];
      for (final header in headers) {
        final existingPod = claimedHeaders[header];
        if (existingPod != null && existingPod != pod) {
          onClash?.call(
            PodHeaderClash(
              header: header,
              firstPod: existingPod,
              secondPod: pod,
            ),
          );
        } else {
          claimedHeaders[header] = pod;
        }
      }

      // Add -I flags
      flags.add('-I');
      flags.add('$podPath/Headers/Public');

      flags.add('-I');
      flags.add('$podPath/Headers/Public/$module');
    }

    return flags;
  }
}
