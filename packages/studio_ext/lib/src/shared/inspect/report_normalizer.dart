import 'package:meta/meta.dart';

/// Returns a copy of the report JSON [report] with volatile fields replaced
/// (research R10, FR-005), so two builds of the same source compare equal.
///
/// Replaced: `input.sizeBytes`, `input.sha256` and
/// `resources.assetsCar.sizeBytes` become null; profile `uuid` becomes
/// `"<uuid>"` and profile dates `"<date>"` (root and extension profiles);
/// `normalized` becomes true. Nothing else changes.
@internal
Map<String, Object?> normalizeReportJson(Map<String, Object?> report) {
  final copy = _deepCopy(report)! as Map<String, Object?>;
  copy['normalized'] = true;
  final input = copy['input'];
  if (input is Map<String, Object?>) {
    input['sizeBytes'] = null;
    input['sha256'] = null;
  }
  final resources = copy['resources'];
  if (resources is Map<String, Object?>) {
    final assetsCar = resources['assetsCar'];
    if (assetsCar is Map<String, Object?>) assetsCar['sizeBytes'] = null;
  }
  _normalizeProfile(copy['profile']);
  final extensions = copy['extensions'];
  if (extensions is List) {
    for (final extension in extensions) {
      if (extension is Map<String, Object?>) {
        _normalizeProfile(extension['profile']);
      }
    }
  }
  return copy;
}

void _normalizeProfile(Object? profile) {
  if (profile is! Map<String, Object?>) return;
  if (profile['uuid'] != null) profile['uuid'] = '<uuid>';
  for (final key in ['creationDate', 'expirationDate']) {
    if (profile[key] != null) profile[key] = '<date>';
  }
}

Object? _deepCopy(Object? value) => switch (value) {
  Map() => <String, Object?>{
    for (final MapEntry(:key, value: child) in value.entries)
      '$key': _deepCopy(child),
  },
  List() => [for (final item in value) _deepCopy(item)],
  _ => value,
};
