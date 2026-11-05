// studio: 027 — what a project's Info.plist says about permissions and what its
// entitlements say about capabilities, with what the plugins need on top.
import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/permissions/capability_catalog.dart';
import 'package:studio_ext/src/shared/permissions/permission_catalog.dart';
import 'package:studio_ext/src/shared/permissions/project_plists.dart';
import 'package:studio_ext/src/shared/release/release_checks.dart';
import 'package:studio_ext/src/shared/release/release_tables.dart';

/// One purpose string in `Info.plist`.
@internal
@immutable
final class PermissionEntry {
  const PermissionEntry({
    required this.key,
    required this.name,
    required this.value,
    required this.status,
    this.description,
    this.neededBy = const [],
  });

  final String key;
  final String name;
  final String value;

  /// `ok`, `placeholder` (empty, too short, or a stand-in) or `unknown_key`
  /// (a purpose string the catalog does not list).
  final String status;
  final String? description;

  /// Plugins that use the resource this key explains.
  final List<String> neededBy;

  Map<String, Object?> toJson() => {
    'key': key,
    'name': name,
    'value': value,
    'status': status,
    'description': description,
    'neededBy': neededBy,
  };
}

/// A purpose string the project's plugins need and `Info.plist` lacks.
@internal
@immutable
final class MissingPermission {
  const MissingPermission(this.resource, this.keys, this.plugins);

  final String resource;

  /// Any one of these satisfies it; the first is the one to add.
  final List<String> keys;
  final List<String> plugins;

  Map<String, Object?> toJson() => {
    'resource': resource,
    'keys': keys,
    'plugins': plugins,
  };
}

/// One capability, on or off.
@internal
@immutable
final class CapabilityEntry {
  const CapabilityEntry(this.info, {required this.enabled, this.value});

  final CapabilityInfo info;
  final bool enabled;

  /// The value as stored: String, bool or List.
  final Object? value;

  Map<String, Object?> toJson() => {
    ...info.toJson(),
    'enabled': enabled,
    'value': value,
  };
}

/// The permissions and capabilities of one project.
@internal
abstract final class PermissionsReport {
  /// The purpose strings of [info], and the ones [project]'s plugins need and
  /// it lacks (when [project] is known).
  static ({List<PermissionEntry> permissions, List<MissingPermission> missing})
  permissions(ProjectPlist info, ReleaseProject? project) {
    final values = info.values;
    final plugins = project?.plugins ?? const <String>{};
    List<String> usedBy(String key) => [
      for (final plugin in plugins.toList()..sort())
        if (ReleaseTables.pluginUsage[plugin] case final needs?)
          if (needs.any((need) => need.anyOf.contains(key))) plugin,
    ];
    final entries = [
      for (final key
          in values.keys.where(ReleaseTables.isUsageKey).toList()..sort())
        () {
          final catalog = PermissionCatalog.of(key);
          final value = values[key];
          return PermissionEntry(
            key: key,
            name: catalog?.name ?? key,
            value: value is String ? value : '',
            status: ReleaseTables.isPlaceholderPurpose(key, value)
                ? 'placeholder'
                : catalog == null
                ? 'unknown_key'
                : 'ok',
            description: catalog?.description,
            neededBy: usedBy(key),
          );
        }(),
    ];
    final missing = <String, MissingPermission>{};
    for (final plugin in plugins.toList()..sort()) {
      for (final need
          in ReleaseTables.pluginUsage[plugin] ?? const <UsageRequirement>[]) {
        if (need.anyOf.any(values.containsKey)) continue;
        final id = '${need.resource}|${need.anyOf.join(',')}';
        final before = missing[id];
        missing[id] = MissingPermission(need.resource, need.anyOf, [
          ...?before?.plugins,
          plugin,
        ]);
      }
    }
    return (permissions: entries, missing: missing.values.toList());
  }

  /// The capabilities, from the entitlements and the Info.plist, plus the
  /// entitlement keys the catalog does not know.
  static ({List<CapabilityEntry> capabilities, List<String> unknown})
  capabilities(ProjectPlist info, ProjectPlist entitlements) {
    final fromInfo = info.values;
    final fromEntitlements = entitlements.values;
    final entries = <CapabilityEntry>[];
    for (final capability in CapabilityCatalog.all) {
      final source = capability.inInfoPlist ? fromInfo : fromEntitlements;
      final present = source.containsKey(capability.key);
      final value = source[capability.key];
      final enabled =
          present &&
          switch (capability.value) {
            CapabilityValue.flag => value == true,
            CapabilityValue.list => value is List && value.isNotEmpty,
            CapabilityValue.choice => value is String && value.isNotEmpty,
          };
      entries.add(CapabilityEntry(capability, enabled: enabled, value: value));
    }
    final unknown = [
      for (final key in fromEntitlements.keys.toList()..sort())
        if (CapabilityCatalog.byKey(key) == null) key,
    ];
    return (capabilities: entries, unknown: unknown);
  }
}
