import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The repository root, from packages/studio_ext.
final _root = p.normalize(p.join(Directory.current.path, '..', '..'));

/// Event types in docs/protocol/xcross-events-v1.schema.json.
Set<String> _schemaTypes() {
  final file = File(
    p.join(_root, 'docs', 'protocol', 'xcross-events-v1.schema.json'),
  );
  final schema = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final defs = (schema[r'$defs']! as Map).cast<String, Object?>();
  return {for (final def in defs.values) (def! as Map)['title']! as String};
}

/// Every NDJSON event type the CLI emits, found by scanning its sources:
/// map literals with `'v': 1` and a `'type'` within the next lines, and
/// `event('<type>', {...})` calls of the NDJSON event writer (including the
/// `warn ? 'warning' : 'error'` form). A source scan keeps this test free of
/// new dependencies; it reads code, so it also covers commands without tests.
Set<String> _emittedTypes() {
  final types = <String>{};
  final mapType = RegExp(r"'type':\s*'([a-z_]+)'");
  final eventCall = RegExp(
    r"\bevent\(\s*(?:[^,'(]*\?\s*)?'([a-z_]+)'(?:\s*:\s*'([a-z_]+)')?\s*,\s*\{",
  );
  for (final package in ['studio_ext', 'xcross', 'cli_kit']) {
    final lib = Directory(p.join(_root, 'packages', package, 'lib'));
    for (final file in lib.listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!RegExp(r"'v':\s*1\b").hasMatch(lines[i])) continue;
        final window = lines
            .sublist(i, (i + 9).clamp(0, lines.length))
            .join(' ');
        final match = mapType.firstMatch(window);
        if (match != null) types.add(match.group(1)!);
      }
      final source = lines.join('\n');
      for (final match in eventCall.allMatches(source)) {
        types.add(match.group(1)!);
        if (match.group(2) case final other?) types.add(other);
      }
    }
  }
  return types;
}

void main() {
  test('AC-PROTO-3 every event type the CLI emits is in the protocol schema, '
      'and the schema lists nothing the CLI no longer emits', () {
    final emitted = _emittedTypes();
    final schema = _schemaTypes();
    expect(emitted.difference(schema), isEmpty, reason: 'missing from schema');
    expect(schema.difference(emitted), isEmpty, reason: 'stale in schema');
    expect(emitted, hasLength(43));
  });
}
