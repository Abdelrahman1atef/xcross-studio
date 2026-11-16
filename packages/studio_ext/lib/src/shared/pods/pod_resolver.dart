import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/pods/pod_version.dart';

@internal
final class PodConstraint {
  const PodConstraint(this.name, this.requirement, this.source);
  final String name;
  final String requirement;
  final String source;
}

@internal
final class PodCandidate {
  const PodCandidate({
    required this.version,
    required this.iosMinimum,
    this.dependencies = const [],
  });
  final String version;
  final String iosMinimum;
  final List<PodConstraint> dependencies;
}

@internal
final class PodResolution {
  const PodResolution(
    this.pods,
    this.staleLocks,
    this.subspecs,
    this.requiredBy,
    this.sources,
  );
  final Map<String, PodCandidate> pods;
  final List<String> staleLocks;
  List<String> get warnings => [
    for (final lock in staleLocks)
      'pod.lock_stale: Podfile.lock pins $lock; run pod install on a Mac to refresh it.',
  ];
  final Map<String, Set<String>> subspecs;
  final Map<String, List<String>> requiredBy;
  final Map<String, String> sources;
}

@internal
final class PodResolveConflict implements Exception {
  const PodResolveConflict(this.constraints, this.steps);
  final List<PodConstraint> constraints;
  final int steps;
  @override
  String toString() =>
      'pod.resolve_conflict: ${constraints.map((c) => '${c.name}: ${c.source} needs ${c.requirement}').join('; ')}';
}

@internal
final class PodIosMinimum implements Exception {
  const PodIosMinimum(this.pod, this.target, this.minimum);
  final String pod;
  final String target;
  final String minimum;

  @override
  String toString() =>
      'ios_minimum: $pod requires iOS $minimum; app targets iOS $target';
}

/// Backtracking resolver over saved or CDN supplied podspec candidates.
@internal
final class PodResolver {
  const PodResolver({this.stepLimit = 10000});
  final int stepLimit;

  PodResolution resolve({
    required List<PodConstraint> roots,
    required Map<String, List<PodCandidate>> available,
    required String iosTarget,
    Map<String, String> lockPins = const {},
  }) {
    var steps = 0;
    var lastConflict = roots;
    PodIosMinimum? minimumFailure;
    var stepExceeded = false;
    final stale = <String>[];
    final target = PodVersion(iosTarget);

    Map<String, PodCandidate>? search(
      Map<String, PodCandidate> chosen,
      List<PodConstraint> constraints,
    ) {
      if (++steps > stepLimit) {
        stepExceeded = true;
        lastConflict = constraints;
        return null;
      }
      final grouped = <String, List<PodConstraint>>{};
      for (final constraint in constraints) {
        final base = constraint.name.split('/').first;
        grouped.putIfAbsent(base, () => []).add(constraint);
      }
      for (final entry in grouped.entries) {
        final selected = chosen[entry.key];
        if (selected == null) continue;
        if (!_fits(
          selected,
          entry.value,
          target,
          pinned: lockPins[entry.key] == selected.version,
        )) {
          lastConflict = entry.value;
          return null;
        }
      }
      final pending = grouped.keys.where((name) => !chosen.containsKey(name));
      if (pending.isEmpty) return chosen;
      final name = pending.first;
      final requirements = grouped[name]!;
      final candidates = [
        ...?available[name],
      ]..sort((a, b) => PodVersion(b.version).compareTo(PodVersion(a.version)));
      final pin = lockPins[name];
      if (pin != null) {
        candidates.sort((a, b) {
          if (a.version == pin) return -1;
          if (b.version == pin) return 1;
          return PodVersion(b.version).compareTo(PodVersion(a.version));
        });
      }
      final requirementCompatible = candidates.where((candidate) {
        final version = PodVersion(candidate.version);
        return requirements.every(
          (constraint) => PodRequirement(
            constraint.requirement,
          ).allows(version, pinned: candidate.version == pin),
        );
      }).toList();
      if (requirementCompatible.isNotEmpty &&
          requirementCompatible.every(
            (candidate) =>
                PodVersion(candidate.iosMinimum).compareTo(target) > 0,
          )) {
        minimumFailure = PodIosMinimum(
          name,
          iosTarget,
          requirementCompatible.last.iosMinimum,
        );
      }
      for (final candidate in candidates) {
        if (!_fits(
          candidate,
          requirements,
          target,
          pinned: candidate.version == pin,
        )) {
          continue;
        }
        final result = search(
          {...chosen, name: candidate},
          [...constraints, ...candidate.dependencies],
        );
        if (result != null) return result;
      }
      if (candidates.every(
        (candidate) => !_fits(
          candidate,
          requirements,
          target,
          pinned: candidate.version == pin,
        ),
      )) {
        lastConflict = requirements;
      }
      return null;
    }

    final result = search({}, roots);
    if (result == null) {
      if (minimumFailure != null && !stepExceeded) throw minimumFailure!;
      throw PodResolveConflict(lastConflict, steps);
    }
    for (final pin in lockPins.entries) {
      if (result[pin.key] != null && result[pin.key]!.version != pin.value) {
        stale.add('${pin.key} ${pin.value} -> ${result[pin.key]!.version}');
      }
    }
    final subspecs = <String, Set<String>>{};
    final requiredBy = <String, List<String>>{};
    for (final constraint in [
      ...roots,
      for (final pod in result.values) ...pod.dependencies,
    ]) {
      final parts = constraint.name.split('/');
      final base = parts.first;
      if (!result.containsKey(base)) continue;
      if (parts.length > 1) {
        subspecs.putIfAbsent(base, () => {}).add(parts.skip(1).join('/'));
      }
      requiredBy.putIfAbsent(base, () => []);
      if (!requiredBy[base]!.contains(constraint.source)) {
        requiredBy[base]!.add(constraint.source);
      }
    }
    final sources = {
      for (final entry in result.entries)
        entry.key: lockPins[entry.key] == entry.value.version
            ? 'lock'
            : 'resolved',
    };
    return PodResolution(result, stale, subspecs, requiredBy, sources);
  }

  bool _fits(
    PodCandidate candidate,
    List<PodConstraint> requirements,
    PodVersion target, {
    required bool pinned,
  }) {
    if (PodVersion(candidate.iosMinimum).compareTo(target) > 0) return false;
    final version = PodVersion(candidate.version);
    return requirements.every(
      (constraint) => PodRequirement(
        constraint.requirement,
      ).allows(version, pinned: pinned),
    );
  }
}
