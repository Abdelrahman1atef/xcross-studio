import 'dart:io';

import 'package:studio_ext/src/shared/inspect/report_json.dart';
import 'package:test/test.dart';

import '../../support/fixture_builder.dart';
import '../../support/inspect_helpers.dart';

/// Golden reports (AC-001-5, SC-003). The fixtures are deterministic bytes,
/// so the raw `--json` output must match the committed file byte for byte on
/// every OS. Regenerate with `UPDATE_GOLDENS=1 dart test <this file>`.
void main() {
  final update = Platform.environment['UPDATE_GOLDENS'] == '1';

  for (final MapEntry(key: name, value: write) in goldenFixtures.entries) {
    test('AC-001-5 report matches committed golden ($name)', () {
      final temp = Directory.systemTemp.createTempSync('golden_');
      try {
        final json = encodeReportJson(inspectPath(write(temp)).toJson());
        final golden = File('test/goldens/$name.json');
        if (update) {
          golden
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(json.codeUnits);
        }
        expect(
          golden.existsSync(),
          isTrue,
          reason: 'missing golden; run with UPDATE_GOLDENS=1',
        );
        expect(String.fromCharCodes(golden.readAsBytesSync()), json);
      } finally {
        temp.deleteSync(recursive: true);
      }
    });
  }
}
