// studio: 019 — `build/xcross-ios/release.json`, the release evidence of
// US-IOS-001 §11 (specs/019-upload-processing, AC-019-8).
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

/// Merges values into the release record next to the build outputs.
@internal
abstract final class ReleaseRecord {
  static const fileName = 'release.json';

  /// [values] merged into the JSON object at [file] (nested maps merged key
  /// by key, null values left out); returns the merged record.
  static Map<String, Object?> merge(File file, Map<String, Object?> values) {
    Map<String, Object?> current = {};
    if (file.existsSync()) {
      try {
        final Object? decoded = jsonDecode(file.readAsStringSync());
        if (decoded is Map) current = decoded.cast<String, Object?>();
      } on FormatException {
        current = {};
      }
    }
    final merged = mergeMaps(current, values);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(merged)}\n',
    );
    return merged;
  }

  @visibleForTesting
  static Map<String, Object?> mergeMaps(
    Map<String, Object?> base,
    Map<String, Object?> values,
  ) {
    final result = {...base};
    for (final MapEntry(:key, :value) in values.entries) {
      if (value == null) continue;
      final existing = result[key];
      result[key] = value is Map && existing is Map
          ? mergeMaps(
              existing.cast<String, Object?>(),
              value.cast<String, Object?>(),
            )
          : value;
    }
    return result;
  }
}
