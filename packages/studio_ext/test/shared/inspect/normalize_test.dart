import 'dart:convert';
import 'dart:io';

import 'package:studio_ext/src/shared/inspect/report_json.dart';
import 'package:studio_ext/src/shared/inspect/report_normalizer.dart';
import 'package:test/test.dart';

import '../../support/fixture_builder.dart';
import '../../support/inspect_helpers.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('normalize_'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('AC-001-6 two builds of the same source normalise equal', () {
    final first = profileAppex().writeIpa(temp, 'app.ipa');
    final firstReport = inspectPath(first).toJson();
    final second = profileAppex(
      uuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      created: DateTime.utc(2026, 6),
      expires: DateTime.utc(2027, 6),
    ).writeIpa(temp, 'app2.ipa', modified: DateTime.utc(2021, 5, 6, 7, 8));
    final secondReport = inspectPath(second).toJson();
    // Same file name in both reports, as for two builds of one project.
    (secondReport['input']! as Map<String, Object?>)['name'] = 'app.ipa';

    expect(
      encodeReportJson(firstReport),
      isNot(encodeReportJson(secondReport)),
    );
    final a = encodeReportJson(normalizeReportJson(firstReport));
    final b = encodeReportJson(normalizeReportJson(secondReport));
    expect(a, b);

    final json = jsonDecode(a) as Map<String, Object?>;
    expect(json['normalized'], isTrue);
    final input = json['input']! as Map<String, Object?>;
    expect(input['sizeBytes'], isNull);
    expect(input['sha256'], isNull);
    final profile = json['profile']! as Map<String, Object?>;
    expect(profile['uuid'], '<uuid>');
    expect(profile['creationDate'], '<date>');
    expect(profile['expirationDate'], '<date>');
    final resources = json['resources']! as Map<String, Object?>;
    expect((resources['assetsCar']! as Map)['sizeBytes'], isNull);
    final extension = (json['extensions']! as List).single as Map;
    expect((extension['profile']! as Map)['uuid'], '<uuid>');
    expect((extension['profile']! as Map)['expirationDate'], '<date>');
  });

  test('normalisation leaves everything else untouched', () {
    final report = inspectPath(
      unsignedV209().writeIpa(temp, 'app.ipa'),
    ).toJson();
    final normalized = normalizeReportJson(report);
    for (final key in ['bundle', 'signature', 'executables', 'issues']) {
      expect(jsonEncode(normalized[key]), jsonEncode(report[key]));
    }
    expect(normalized['profile'], isNull);
    expect(report['normalized'], isFalse, reason: 'input map not mutated');
  });
}
