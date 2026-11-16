import 'package:meta/meta.dart';

@internal
final class PodConsumerView {
  const PodConsumerView(this.attributes, this.selectedSubspecs);
  final Map<String, Object?> attributes;
  final List<String> selectedSubspecs;
}

/// Resolves the iOS attributes of selected CocoaPods JSON subspecs.
@internal
final class PodConsumer {
  const PodConsumer();

  static const _inherited = {
    'dependencies',
    'frameworks',
    'weak_frameworks',
    'libraries',
    'compiler_flags',
    'pod_target_xcconfig',
    'user_target_xcconfig',
    'requires_arc',
    'header_dir',
    'header_mappings_dir',
    'prefix_header_contents',
    'prefix_header_file',
  };
  static const _perSpec = {
    'source_files',
    'public_header_files',
    'private_header_files',
    'project_header_files',
    'exclude_files',
    'resources',
    'resource_bundles',
    'vendored_frameworks',
    'vendored_libraries',
    'preserve_paths',
    'info_plist',
  };

  PodConsumerView build(Map<String, Object?> root, {List<String>? selected}) {
    final effective = _ios(root);
    final requested = selected ?? _defaults(root);
    final selectedNames = <String>[];

    void visit(
      Map<String, Object?> node,
      String prefix,
      Map<String, Object?> inherited,
    ) {
      final name = node['name']?.toString() ?? '';
      final fullName = prefix.isEmpty ? name : '$prefix/$name';
      if (_isTestOrApp(node) ||
          !_supportsIos(node) ||
          !requested.any(
            (choice) => choice == fullName || choice.startsWith('$fullName/'),
          )) {
        return;
      }
      final own = _ios(node);
      final combined = <String, Object?>{...inherited};
      for (final key in _inherited) {
        if (own.containsKey(key)) {
          combined[key] = _merge(key, combined[key], own[key]);
        }
      }
      for (final key in _inherited) {
        if (own.containsKey(key)) {
          effective[key] = _merge(key, effective[key], own[key]);
        }
      }
      for (final key in _perSpec) {
        if (own.containsKey(key)) {
          effective[key] = _merge(key, effective[key], own[key]);
        }
      }
      selectedNames.add(fullName);
      for (final child in _subspecs(node)) {
        visit(child, fullName, combined);
      }
    }

    final inherited = {
      for (final key in _inherited)
        if (effective.containsKey(key)) key: effective[key],
    };
    for (final child in _subspecs(root)) {
      visit(child, '', inherited);
    }
    return PodConsumerView(effective, selectedNames);
  }

  List<String> _defaults(Map<String, Object?> root) {
    final defaults = root['default_subspecs'];
    if (defaults == ':none' || defaults == 'none') return [];
    if (defaults is String) return [defaults];
    if (defaults is List) {
      return defaults.map((value) => value.toString()).toList();
    }
    final all = <String>[];
    void collect(Map<String, Object?> node, String prefix) {
      for (final child in _subspecs(node)) {
        final name = prefix.isEmpty
            ? child['name'].toString()
            : '$prefix/${child['name']}';
        if (_isTestOrApp(child) || !_supportsIos(child)) continue;
        all.add(name);
        collect(child, name);
      }
    }

    collect(root, '');
    return all;
  }

  Map<String, Object?> _ios(Map<String, Object?> input) {
    final output = <String, Object?>{};
    for (final entry in input.entries) {
      if (entry.key == 'ios' ||
          entry.key == 'subspecs' ||
          entry.key == 'test_specs' ||
          entry.key == 'app_specs' ||
          {'osx', 'tvos', 'watchos', 'visionos'}.contains(entry.key)) {
        continue;
      }
      output[entry.key] = entry.value;
    }
    final ios = input['ios'];
    if (ios is Map) {
      for (final entry in ios.entries) {
        final key = entry.key.toString();
        output[key] = _merge(key, output[key], entry.value);
      }
    }
    return output;
  }

  Object? _merge(String key, Object? parent, Object? child) {
    if (parent == null) return child;
    if (child == null) return parent;
    if (parent is Map && child is Map) {
      final result = <String, Object?>{
        for (final e in parent.entries) e.key.toString(): e.value,
      };
      for (final entry in child.entries) {
        final name = entry.key.toString();
        if (key == 'resource_bundles' || key == 'dependencies') {
          result[name] = _merge('resources', result[name], entry.value);
        } else if (key.contains('xcconfig')) {
          result[name] = result[name] == null
              ? entry.value
              : '${result[name]} ${entry.value}';
        } else {
          result[name] = entry.value;
        }
      }
      return result;
    }
    if (parent is List || child is List || _perSpec.contains(key)) {
      final values = <Object?>{
        ...parent is List ? parent : [parent],
        ...child is List ? child : [child],
      };
      return values.toList();
    }
    if (_inherited.contains(key) &&
        parent is String &&
        child is String &&
        key.contains('xcconfig')) {
      return '$parent $child';
    }
    return child;
  }

  List<Map<String, Object?>> _subspecs(Map<String, Object?> node) => [
    for (final item
        in node['subspecs'] is List ? node['subspecs']! as List : const [])
      if (item is Map)
        item.map((key, value) => MapEntry(key.toString(), value)),
  ];

  bool _isTestOrApp(Map<String, Object?> node) =>
      node.containsKey('test_specification') ||
      node.containsKey('app_specification') ||
      node['test_spec'] == true ||
      node['app_spec'] == true;

  bool _supportsIos(Map<String, Object?> node) {
    final platforms = node['platforms'];
    return platforms is! Map || platforms.containsKey('ios');
  }
}
