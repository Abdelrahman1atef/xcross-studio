import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xcross_studio/src/cli/xcross_events.dart';

/// The public protocol schema (docs/protocol), from apps/studio.
Map<String, Object?> _schema() {
  final file = File('../../docs/protocol/xcross-events-v1.schema.json');
  return (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();
}

Map<String, Map<String, Object?>> _definitions() {
  final defs = (_schema()[r'$defs']! as Map).cast<String, Object?>();
  return {
    for (final def in defs.values)
      ((def! as Map)['title']! as String): (def as Map).cast<String, Object?>(),
  };
}

/// The types Studio's parser dispatches on, read from its source.
Set<String> _studioSwitchTypes() {
  final source = File('lib/src/cli/xcross_events.dart').readAsStringSync();
  final start = source.indexOf("return switch (json['type'])");
  final end = source.indexOf('_ => null', start);
  return RegExp(r"'([a-z_]+)'(?=\s*(?:=>|\|\|))")
      .allMatches(source.substring(start, end))
      .map((m) => m.group(1)!)
      .toSet();
}

void main() {
  final defs = _definitions();

  test(
    'AC-PROTO-1 every schema example parses into its Studio event class',
    () {
      var checked = 0;
      for (final MapEntry(key: type, value: def) in defs.entries) {
        final examples = def['examples'] as List<Object?>? ?? const [];
        for (final example in examples) {
          final event = XcrossEvent.tryParse(jsonEncode(example));
          if (def['x-consumed-by-studio'] == true) {
            expect(event, isNotNull, reason: type);
            expect(
              event.runtimeType.toString(),
              def['x-studio-class'],
              reason: type,
            );
          } else {
            expect(event, isNull, reason: '$type is not read by Studio');
          }
          checked++;
        }
      }
      expect(checked, greaterThanOrEqualTo(18));
    },
  );

  test('AC-PROTO-2 each type dispatches to its class; script-only types are '
      'ignored', () {
    for (final MapEntry(key: type, value: def) in defs.entries) {
      final event = XcrossEvent.tryParse('{"v":1,"type":"$type"}');
      if (def['x-consumed-by-studio'] == true) {
        expect(
          event.runtimeType.toString(),
          def['x-studio-class'],
          reason: type,
        );
      } else {
        expect(event, isNull, reason: type);
      }
    }
    // Newer versions and unknown types are ignored (protocol rules 1 and 3).
    expect(XcrossEvent.tryParse('{"v":2,"type":"step"}'), isNull);
    expect(XcrossEvent.tryParse('{"v":1,"type":"not_a_type"}'), isNull);
  });

  test('AC-PROTO-2 the schema lists exactly the types Studio reads', () {
    final consumed = {
      for (final MapEntry(key: type, value: def) in defs.entries)
        if (def['x-consumed-by-studio'] == true) type,
    };
    expect(_studioSwitchTypes(), consumed);
    expect(consumed, hasLength(38));
  });
}
