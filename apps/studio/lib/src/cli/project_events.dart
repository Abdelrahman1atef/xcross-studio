// Features 027 and 028: what `xcross permissions`, `capabilities` and
// `plugin status` print with `--json`.
part of 'xcross_events.dart';

List<String> _strings(Object? value) => [
  if (value is List)
    for (final entry in value)
      if (entry is String) entry,
];

/// One purpose string set in Info.plist.
class PermissionItem {
  const PermissionItem({
    required this.key,
    required this.name,
    required this.value,
    required this.status,
    this.description,
    this.neededBy = const [],
  });

  factory PermissionItem.fromJson(Map<String, Object?> json) => PermissionItem(
    key: _string(json['key']) ?? '',
    name: _string(json['name']) ?? _string(json['key']) ?? '',
    value: _string(json['value']) ?? '',
    status: _string(json['status']) ?? 'ok',
    description: _string(json['description']),
    neededBy: _strings(json['neededBy']),
  );

  final String key;
  final String name;
  final String value;

  /// `ok`, `placeholder` or `unknown_key`.
  final String status;
  final String? description;
  final List<String> neededBy;

  bool get isPlaceholder => status == 'placeholder';
}

/// A purpose string a plugin needs and Info.plist lacks.
class MissingPermissionItem {
  const MissingPermissionItem({
    required this.resource,
    required this.keys,
    required this.plugins,
  });

  factory MissingPermissionItem.fromJson(Map<String, Object?> json) =>
      MissingPermissionItem(
        resource: _string(json['resource']) ?? '',
        keys: _strings(json['keys']),
        plugins: _strings(json['plugins']),
      );

  final String resource;

  /// Any one of these satisfies it; the first is the one to add.
  final List<String> keys;
  final List<String> plugins;
}

/// A key the editor can add, with a starting sentence.
class PermissionCatalogItem {
  const PermissionCatalogItem({
    required this.key,
    required this.name,
    required this.description,
    required this.suggestion,
  });

  factory PermissionCatalogItem.fromJson(Map<String, Object?> json) =>
      PermissionCatalogItem(
        key: _string(json['key']) ?? '',
        name: _string(json['name']) ?? '',
        description: _string(json['description']) ?? '',
        suggestion: _string(json['suggestion']) ?? '',
      );

  final String key;
  final String name;
  final String description;
  final String suggestion;
}

/// `permissions list`.
class PermissionsReport extends XcrossEvent {
  const PermissionsReport({
    required this.permissions,
    required this.missing,
    required this.catalog,
  });

  factory PermissionsReport.fromJson(Map<String, Object?> json) =>
      PermissionsReport(
        permissions: [
          for (final item in _maps(json['permissions']))
            PermissionItem.fromJson(item),
        ],
        missing: [
          for (final item in _maps(json['missing']))
            MissingPermissionItem.fromJson(item),
        ],
        catalog: [
          for (final item in _maps(json['catalog']))
            PermissionCatalogItem.fromJson(item),
        ],
      );

  final List<PermissionItem> permissions;
  final List<MissingPermissionItem> missing;
  final List<PermissionCatalogItem> catalog;

  PermissionCatalogItem? catalogOf(String key) {
    for (final item in catalog) {
      if (item.key == key) return item;
    }
    return null;
  }
}

/// `permissions set|remove` and `capabilities add|remove`: what changed.
class ProjectChange extends XcrossEvent {
  const ProjectChange({
    required this.action,
    required this.target,
    required this.changed,
    this.backup,
    this.notes = const [],
  });

  factory ProjectChange.fromJson(Map<String, Object?> json) => ProjectChange(
    action: _string(json['action']) ?? '',
    target: _string(json['key']) ?? _string(json['id']) ?? '',
    changed: json['changed'] == true,
    backup: _string(json['backup']),
    notes: _strings(json['notes']),
  );

  /// `set`, `remove` or `add`.
  final String action;

  /// The key or the capability id.
  final String target;
  final bool changed;

  /// Where the old file was copied, relative to the project.
  final String? backup;
  final List<String> notes;
}

/// One capability.
class CapabilityItem {
  const CapabilityItem({
    required this.id,
    required this.name,
    required this.description,
    required this.kind,
    required this.enabled,
    this.choices = const [],
    this.ascCapability,
    this.example,
    this.value,
  });

  factory CapabilityItem.fromJson(Map<String, Object?> json) => CapabilityItem(
    id: _string(json['id']) ?? '',
    name: _string(json['name']) ?? '',
    description: _string(json['description']) ?? '',
    kind: _string(json['kind']) ?? 'flag',
    enabled: json['enabled'] == true,
    choices: _strings(json['choices']),
    ascCapability: _string(json['ascCapability']),
    example: _string(json['example']),
    value: json['value'],
  );

  final String id;
  final String name;
  final String description;

  /// `flag`, `choice` or `list`.
  final String kind;
  final bool enabled;
  final List<String> choices;
  final String? ascCapability;
  final String? example;
  final Object? value;

  /// The list value, or empty.
  List<String> get values => _strings(value);
}

/// `capabilities list`.
class CapabilitiesReport extends XcrossEvent {
  const CapabilitiesReport({
    required this.capabilities,
    required this.entitlementsPath,
    required this.entitlementsExist,
    required this.xcodeKnowsFile,
    this.unknownEntitlements = const [],
  });

  factory CapabilitiesReport.fromJson(Map<String, Object?> json) {
    final file = _map(json['entitlements']);
    return CapabilitiesReport(
      capabilities: [
        for (final item in _maps(json['capabilities']))
          CapabilityItem.fromJson(item),
      ],
      entitlementsPath: _string(file['path']) ?? '',
      entitlementsExist: file['exists'] == true,
      xcodeKnowsFile: file['xcodeKnowsFile'] == true,
      unknownEntitlements: _strings(json['unknownEntitlements']),
    );
  }

  final List<CapabilityItem> capabilities;
  final String entitlementsPath;
  final bool entitlementsExist;
  final bool xcodeKnowsFile;
  final List<String> unknownEntitlements;
}

/// One thing wrong with a plugin.
class PluginProblemItem {
  const PluginProblemItem(this.code, this.message);

  factory PluginProblemItem.fromJson(Map<String, Object?> json) =>
      PluginProblemItem(
        _string(json['code']) ?? '',
        _string(json['message']) ?? '',
      );

  /// `stale`, `manifest_missing`, `unknown_pods`, `review_pending`.
  final String code;
  final String message;
}

/// One iOS plugin and what it needs.
class PluginItem {
  const PluginItem({
    required this.name,
    required this.kind,
    this.version,
    this.overridePath,
    this.edited = false,
    this.problems = const [],
    this.action,
    this.canRegenerate = false,
    this.command,
  });

  factory PluginItem.fromJson(Map<String, Object?> json) => PluginItem(
    name: _string(json['name']) ?? '',
    version: _string(json['version']),
    kind: _string(json['kind']) ?? 'swiftpm',
    overridePath: _string(json['overridePath']),
    edited: json['edited'] == true,
    problems: [
      for (final item in _maps(json['problems']))
        PluginProblemItem.fromJson(item),
    ],
    action: _string(json['action']),
    canRegenerate: json['canRegenerate'] == true,
    command: json['command'] == null ? null : _strings(json['command']),
  );

  final String name;
  final String? version;

  /// `swiftpm`, `draft`, `hand_written`, `podspec_only` or `no_ios_code`.
  final String kind;
  final String? overridePath;

  /// The draft differs from what xcross would write now.
  final bool edited;
  final List<PluginProblemItem> problems;

  /// `regenerate`, `review`, `manual` or null.
  final String? action;
  final bool canRegenerate;
  final List<String>? command;

  bool get needsAction => problems.isNotEmpty;
}

/// `plugin status`.
class PluginStatusReport extends XcrossEvent {
  const PluginStatusReport(this.plugins);

  factory PluginStatusReport.fromJson(Map<String, Object?> json) =>
      PluginStatusReport([
        for (final item in _maps(json['plugins'])) PluginItem.fromJson(item),
      ]);

  final List<PluginItem> plugins;
}
