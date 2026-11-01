import 'dart:convert';
import 'dart:io';

import 'package:studio_ext/src/shared/inspect/inspect_codes.dart';
import 'package:studio_ext/src/shared/inspect/inspect_failure.dart';
import 'package:studio_ext/src/shared/inspect/report_json.dart';
import 'package:test/test.dart';

import '../../support/fixture_builder.dart';
import '../../support/inspect_helpers.dart';
import '../../support/json_schema_lite.dart';

void main() {
  final schema = JsonSchemaLite.inspectContract();

  for (final MapEntry(key: name, value: write) in goldenFixtures.entries) {
    test('FR-002 $name report validates against inspect.schema.json', () {
      final temp = Directory.systemTemp.createTempSync('schema_');
      try {
        final json = jsonDecode(
          encodeReportJson(inspectPath(write(temp)).toJson()),
        );
        expect(schema.validate(json), isEmpty);
      } finally {
        temp.deleteSync(recursive: true);
      }
    });
  }

  test('FR-002 error document validates against inspect.schema.json', () {
    final failure = InspectFailure(InspectCodes.noApp, 'x.ipa has no app.');
    expect(schema.validate(jsonDecode(jsonEncode(failure.toJson()))), isEmpty);
  });

  test('schema rejects absolute paths and unknown properties', () {
    final temp = Directory.systemTemp.createTempSync('schema_');
    try {
      final json =
          jsonDecode(
                encodeReportJson(
                  inspectPath(goldenFixtures['adhoc_push']!(temp)).toJson(),
                ),
              )
              as Map<String, Object?>;
      json['surprise'] = 1;
      (json['frameworks']! as List).add({
        'name': 'X.framework',
        'path': r'C:\abs\X.framework',
        'kind': 'framework',
        'bundleId': null,
      });
      expect(schema.validate(json), isNotEmpty);
      final errors = schema.validateDefinition('report', json);
      expect(errors, contains(r'$: unexpected property "surprise"'));
      expect(errors.any((e) => e.contains('frameworks[2].path')), isTrue);
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
}
