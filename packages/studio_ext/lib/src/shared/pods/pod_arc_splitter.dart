import 'package:meta/meta.dart';

/// Describes one SwiftPM target synthesized for a pod (§8.3).
@internal
@immutable
final class PodTargetSpec {
  const PodTargetSpec({
    required this.name,
    required this.sources,
    this.flags = const [],
    this.dependencies = const [],
    this.isArc = true,
  });

  final String name;
  final List<String> sources;
  final List<String> flags;
  final List<String> dependencies;
  final bool isArc;
}

/// Splits pod sources into ARC and non-ARC targets and per-flag-set targets (§8.3).
@internal
final class PodArcSplitter {
  const PodArcSplitter();

  /// Splits [sources] according to [requiresArc] and [subspecFlags].
  ///
  /// - If [requiresArc] is `false`: all sources belong to a non-ARC target with `-fno-objc-arc`.
  /// - If [requiresArc] is `true`: all sources belong to a standard ARC target.
  /// - If [requiresArc] is a `List<String>` or `Set<String>` (file list/globs):
  ///   matching files go to the ARC target `<Module>`, non-matching go to `<Module>_noarc`
  ///   with `-fno-objc-arc`, and `<Module>` depends on `<Module>_noarc`.
  List<PodTargetSpec> splitTargets({
    required String moduleName,
    required Iterable<String> sources,
    Object? requiresArc,
    Map<String, List<String>> subspecFlags = const {},
  }) {
    final allSources = sources.toList()..sort();
    if (allSources.isEmpty) {
      return [PodTargetSpec(name: moduleName, sources: const [])];
    }

    // 1. Entire pod has requires_arc: false
    if (requiresArc == false) {
      return [
        PodTargetSpec(
          name: moduleName,
          sources: allSources,
          flags: const ['-fno-objc-arc'],
          isArc: false,
        ),
      ];
    }

    // 2. Entire pod has requires_arc: true (or null/default)
    if (requiresArc == true || requiresArc == null) {
      // Check if subspecs have distinct compiler flags
      if (subspecFlags.isNotEmpty) {
        return _splitBySubspecFlags(moduleName, allSources, subspecFlags);
      }
      return [PodTargetSpec(name: moduleName, sources: allSources)];
    }

    // 3. requires_arc is a list of file patterns / paths
    if (requiresArc is Iterable) {
      final patterns = requiresArc
          .map((e) => e.toString().toLowerCase())
          .toSet();
      final arcSources = <String>[];
      final nonArcSources = <String>[];

      for (final src in allSources) {
        final lower = src.toLowerCase();
        final matchesArc = patterns.any(
          (pat) =>
              lower.contains(pat) ||
              RegExp('(^|/)${RegExp.escape(pat)}(\$|/)').hasMatch(lower),
        );
        if (matchesArc) {
          arcSources.add(src);
        } else {
          nonArcSources.add(src);
        }
      }

      if (nonArcSources.isEmpty) {
        return [PodTargetSpec(name: moduleName, sources: arcSources)];
      }

      if (arcSources.isEmpty) {
        return [
          PodTargetSpec(
            name: moduleName,
            sources: nonArcSources,
            flags: const ['-fno-objc-arc'],
            isArc: false,
          ),
        ];
      }

      final noArcTargetName = '${moduleName}_noarc';
      return [
        PodTargetSpec(
          name: noArcTargetName,
          sources: nonArcSources,
          flags: const ['-fno-objc-arc'],
          isArc: false,
        ),
        PodTargetSpec(
          name: moduleName,
          sources: arcSources,
          dependencies: [noArcTargetName],
        ),
      ];
    }

    return [PodTargetSpec(name: moduleName, sources: allSources)];
  }

  static List<PodTargetSpec> _splitBySubspecFlags(
    String moduleName,
    List<String> sources,
    Map<String, List<String>> subspecFlags,
  ) {
    // If there are subspecs with distinct flags, create subspec target and main target
    final specs = <PodTargetSpec>[];
    final claimed = <String>{};

    for (final entry in subspecFlags.entries) {
      final subspec = entry.key;
      final flags = entry.value;
      if (flags.isEmpty) continue;

      final subspecSources = sources
          .where((s) => s.toLowerCase().contains(subspec.toLowerCase()))
          .toList();
      if (subspecSources.isNotEmpty) {
        final targetName = '${moduleName}_$subspec';
        specs.add(
          PodTargetSpec(
            name: targetName,
            sources: subspecSources,
            flags: flags,
          ),
        );
        claimed.addAll(subspecSources);
      }
    }

    final remaining = sources.where((s) => !claimed.contains(s)).toList();
    specs.add(
      PodTargetSpec(
        name: moduleName,
        sources: remaining,
        dependencies: [for (final s in specs) s.name],
      ),
    );

    return specs;
  }
}
