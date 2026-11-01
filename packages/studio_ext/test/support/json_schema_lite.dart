import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

/// Minimal JSON Schema validator covering the keywords used by
/// `specs/001-inspect/contracts/inspect.schema.json`: `$ref` (local
/// `#/$defs/...`), `oneOf`, `type` (string or list), `const`, `enum`,
/// `required`, `properties`, `additionalProperties: false`, `items`,
/// `pattern` and `minimum`. Returns human-readable violations.
final class JsonSchemaLite {
  JsonSchemaLite(this.schema);

  /// Loads the published inspect schema from the repository.
  factory JsonSchemaLite.inspectContract() {
    final packageLib = Isolate.resolvePackageUriSync(
      Uri.parse('package:studio_ext/'),
    )!;
    final repoRoot = Directory.fromUri(packageLib).parent.parent.parent;
    final file = File(
      '${repoRoot.path}/specs/001-inspect/contracts/inspect.schema.json',
    );
    return JsonSchemaLite(
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
    );
  }

  /// Loads the device-log NDJSON schema from the repository (feature 010).
  factory JsonSchemaLite.devicelogContract() {
    final packageLib = Isolate.resolvePackageUriSync(
      Uri.parse('package:studio_ext/'),
    )!;
    final repoRoot = Directory.fromUri(packageLib).parent.parent.parent;
    final file = File(
      '${repoRoot.path}/specs/010-device-logs/contracts/devicelog.schema.json',
    );
    return JsonSchemaLite(
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
    );
  }

  final Map<String, Object?> schema;

  List<String> validate(Object? value) {
    final errors = <String>[];
    _check(schema, value, r'$', errors);
    return errors;
  }

  /// Validates [value] against `#/$defs/<name>` for detailed messages.
  List<String> validateDefinition(String name, Object? value) {
    final errors = <String>[];
    _check({r'$ref': '#/\$defs/$name'}, value, r'$', errors);
    return errors;
  }

  Map<String, Object?> _resolve(Map<String, Object?> node) {
    final ref = node[r'$ref'];
    if (ref is! String) return node;
    Object? target = schema;
    for (final part in ref.substring(2).split('/')) {
      target = (target! as Map<String, Object?>)[part];
    }
    return _resolve(target! as Map<String, Object?>);
  }

  void _check(
    Map<String, Object?> raw,
    Object? value,
    String path,
    List<String> errors,
  ) {
    final node = _resolve(raw);
    final oneOf = node['oneOf'];
    if (oneOf is List) {
      final matches = oneOf.where((option) {
        final optionErrors = <String>[];
        _check(option as Map<String, Object?>, value, path, optionErrors);
        return optionErrors.isEmpty;
      }).length;
      if (matches != 1) {
        errors.add('$path: matches $matches oneOf options (want 1)');
      }
      return;
    }
    if (node.containsKey('const') && node['const'] != value) {
      errors.add('$path: expected const ${node['const']}, got $value');
    }
    final enumValues = node['enum'];
    if (enumValues is List && !enumValues.contains(value)) {
      errors.add('$path: $value not in $enumValues');
    }
    final type = node['type'];
    if (type != null) {
      final types = type is List ? type.cast<String>() : [type as String];
      if (!types.any((t) => _isType(t, value))) {
        errors.add('$path: $value is not of type $types');
        return;
      }
    }
    if (value is String) {
      final pattern = node['pattern'];
      if (pattern is String && !RegExp(pattern).hasMatch(value)) {
        errors.add('$path: "$value" does not match $pattern');
      }
    }
    if (value is num) {
      final minimum = node['minimum'];
      if (minimum is num && value < minimum) {
        errors.add('$path: $value < $minimum');
      }
    }
    if (value is Map) {
      final required = node['required'];
      if (required is List) {
        for (final key in required) {
          if (!value.containsKey(key)) errors.add('$path: missing "$key"');
        }
      }
      final properties = node['properties'];
      final props = properties is Map ? properties : const <Object?, Object?>{};
      for (final MapEntry(:key, value: child) in value.entries) {
        final childSchema = props[key];
        if (childSchema is Map<String, Object?>) {
          _check(childSchema, child, '$path.$key', errors);
        } else if (node['additionalProperties'] == false) {
          errors.add('$path: unexpected property "$key"');
        }
      }
    }
    if (value is List) {
      final items = node['items'];
      if (items is Map<String, Object?>) {
        for (var i = 0; i < value.length; i++) {
          _check(items, value[i], '$path[$i]', errors);
        }
      }
    }
  }

  static bool _isType(String type, Object? value) => switch (type) {
    'null' => value == null,
    'boolean' => value is bool,
    'integer' => value is int,
    'number' => value is num,
    'string' => value is String,
    'array' => value is List,
    'object' => value is Map,
    _ => false,
  };
}
