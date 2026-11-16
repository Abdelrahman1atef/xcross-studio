import 'dart:convert';

import 'package:studio_ext/shared/plugins/plugin_command.dart';
import 'package:studio_ext/shared/pods/pods_cdn.dart';
import 'package:studio_ext/src/shared/plugins/package_swift_draft.dart';
import 'package:studio_ext/src/shared/plugins/podspec.dart';
import 'package:studio_ext/src/shared/pods/pod_consumer.dart';
import 'package:studio_ext/src/shared/pods/pod_version.dart';

final class PlannedPod {
  const PlannedPod({
    required this.name,
    required this.classification,
    required this.requiredBy,
    required this.source,
    this.version,
    this.kind,
    this.reason,
  });

  final String name;
  final String? version;
  final String? kind;
  final String classification;
  final String? reason;
  final List<String> requiredBy;
  final String source;

  Map<String, Object?> toJson() => {
    'name': name,
    'version': version,
    'kind': kind,
    'class': classification,
    'reason': reason,
    'requiredBy': requiredBy,
    'source': source,
  };
}

final class PodGraphPlan {
  const PodGraphPlan(this.byPlugin);
  final Map<String, List<PlannedPod>> byPlugin;
}

/// Classifies pod dependencies across the whole Flutter project.
final class PodGraphPlanner {
  const PodGraphPlanner({
    required this.plugins,
    required this.cdn,
    this.converterEnabled = false,
    this.enabledKinds = const {},
    this.skipped = const {},
  });

  final ProjectPlugins plugins;
  final PodsCdn cdn;
  final bool converterEnabled;
  final Set<String> enabledKinds;
  final Set<String> skipped;

  Future<PodGraphPlan> plan(String project, {bool offline = false}) async {
    final allPlugins = plugins.read(project);
    final names = allPlugins.map((plugin) => plugin.name).toSet();
    final specs = <String, Podspec>{};
    final requirements = <String, List<String>>{};
    for (final plugin in allPlugins) {
      final manifestPods = _manifestPods(project, plugin);
      final spec =
          plugins.hasPodspec(plugin) && !plugins.hasSwiftPackage(plugin)
          ? Podspec.parse(
              plugins.fileSystem
                  .file(plugins.podspecPath(plugin))
                  .readAsStringSync(),
            )
          : const Podspec();
      if (spec.dependencies.isEmpty && manifestPods.isEmpty) continue;
      final dependencies = [
        ...spec.dependencies,
        for (final pod in manifestPods)
          if (!spec.dependencies.any((dependency) => dependency.name == pod))
            PodDependency(pod),
      ];
      specs[plugin.name] = Podspec(name: spec.name, dependencies: dependencies);
      for (final dependency in dependencies) {
        final base = dependency.name.split('/').first;
        if (base == 'Flutter' ||
            names.contains(base) ||
            swiftPackageFor(dependency.name, dependency.requirement) != null) {
          continue;
        }
        requirements
            .putIfAbsent(base, () => [])
            .add(dependency.requirement ?? '');
      }
    }
    final result = <String, List<PlannedPod>>{};
    for (final plugin in allPlugins) {
      final spec = specs[plugin.name];
      if (spec == null) {
        result[plugin.name] = [];
        continue;
      }
      final planned = <PlannedPod>[];
      for (final dependency in spec.dependencies) {
        final base = dependency.name.split('/').first;
        final requirement = dependency.requirement ?? '';
        if (base == 'Flutter') {
          planned.add(_simple(dependency.name, 'flutter', plugin.name));
        } else if (base == plugin.name) {
          planned.add(_simple(dependency.name, 'own_subspec', plugin.name));
        } else if (names.contains(base)) {
          planned.add(_simple(dependency.name, 'sibling_plugin', plugin.name));
        } else if (swiftPackageFor(dependency.name, dependency.requirement) !=
            null) {
          planned.add(_simple(dependency.name, 'swift_package', plugin.name));
        } else if (skipped.contains(base)) {
          planned.add(
            _unsupported(dependency.name, plugin.name, 'skipped_by_user'),
          );
        } else if (!converterEnabled) {
          planned.add(
            _unsupported(dependency.name, plugin.name, 'converter_off'),
          );
        } else {
          planned.add(
            await _fromCdn(
              dependency.name,
              requirements[base] ?? [requirement],
              plugin.name,
              offline,
            ),
          );
        }
      }
      result[plugin.name] = planned;
    }
    return PodGraphPlan(result);
  }

  List<String> _manifestPods(String project, ProjectPlugin plugin) {
    final base = plugins.paths.join(project, 'xcross_overrides', plugin.name);
    final candidates = [
      if (plugin.version != null)
        plugins.paths.join(base, plugin.version, 'Package.swift'),
      plugins.paths.join(base, 'Package.swift'),
      plugins.paths.join(
        plugin.platformDirectory,
        plugin.name,
        'Package.swift',
      ),
    ];
    for (final candidate in candidates) {
      final file = plugins.fileSystem.file(candidate);
      if (!file.existsSync()) continue;
      final contents = file.readAsStringSync();
      if (!converterEnabled &&
          contents.contains('// xcross: pod-converter v1')) {
        return const [];
      }
      return [
        for (final match in RegExp(
          r'''\.package\s*\(\s*name:\s*["']pod-([^"']+)["']''',
        ).allMatches(contents))
          match.group(1)!,
      ];
    }
    return const [];
  }

  PlannedPod _simple(String name, String classification, String plugin) =>
      PlannedPod(
        name: name,
        classification: classification,
        requiredBy: [plugin, name],
        source: 'cache',
      );

  PlannedPod _unsupported(String name, String plugin, String reason) =>
      PlannedPod(
        name: name,
        classification: 'unsupported',
        reason: reason,
        requiredBy: [plugin, name],
        source: 'cache',
      );

  Future<PlannedPod> _fromCdn(
    String name,
    List<String> requirements,
    String plugin,
    bool offline,
  ) async {
    final base = name.split('/').first;
    try {
      final versions = offline
          ? cdn.cachedVersions(base)
          : await cdn.versions(base);
      if (versions == null) {
        return _unsupported(name, plugin, 'not_resolved_yet');
      }
      final candidates =
          versions
              .map(PodVersion.new)
              .where(
                (version) => requirements.every(
                  (requirement) => PodRequirement(requirement).allows(version),
                ),
              )
              .toList()
            ..sort((a, b) => b.compareTo(a));
      if (candidates.isEmpty) {
        return _unsupported(name, plugin, 'resolve_conflict');
      }
      final version = candidates.first.source;
      final cached = offline
          ? cdn.cachedSpec(base, version)
          : await cdn.spec(base, version);
      if (cached == null) {
        return _unsupported(name, plugin, 'not_resolved_yet');
      }
      final json = jsonDecode(cached.json);
      if (json is! Map<String, dynamic>) {
        return _unsupported(name, plugin, 'podspec_unread');
      }
      final selected = name.contains('/')
          ? name.split('/').skip(1).join('/')
          : null;
      final consumer = const PodConsumer().build(
        json,
        selected: selected == null ? null : [selected],
      );
      final kind = _kind(consumer.attributes);
      return PlannedPod(
        name: name,
        version: version,
        kind: kind,
        classification: enabledKinds.contains(kind)
            ? 'converted'
            : 'unsupported',
        reason: enabledKinds.contains(kind) ? null : 'not_yet_supported',
        requiredBy: [plugin, name],
        source: offline ? 'cache' : 'resolved',
      );
    } on PodNotOnCdn {
      return _unsupported(name, plugin, 'not_on_cdn');
    }
  }

  String _kind(Map<String, dynamic> json) {
    final source = json['source_files']?.toString().toLowerCase() ?? '';
    final vendored =
        json['vendored_frameworks'] != null ||
        json['vendored_libraries'] != null;
    final swift = source.contains('.swift');
    final native = RegExp(r'\.(m|mm|c|cc|cpp)\b').hasMatch(source);
    if (swift && native) return 'mixed';
    if (swift) return 'swift';
    if (native) return 'objc';
    if (vendored) return 'binary';
    if (source.isNotEmpty) return 'objc';
    return 'binary';
  }
}
