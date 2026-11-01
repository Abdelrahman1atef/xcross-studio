import 'dart:convert';
import 'dart:io';

import 'package:studio_ext/src/shared/inspect/report_json.dart';
import 'package:test/test.dart';

import '../../support/inspect_helpers.dart';
import '../../support/json_schema_lite.dart';

/// Opt-in check against a real IPA or .app: set `STUDIO_INSPECT_IPA=<path>`.
/// Never commit the input or the output (they may contain client data).
void main() {
  final path = Platform.environment['STUDIO_INSPECT_IPA'];

  test('real input validates against the schema and leaks no UDIDs', () {
    final report = inspectPath(path!).toJson();
    expect(
      JsonSchemaLite.inspectContract().validate(
        jsonDecode(encodeReportJson(report)),
      ),
      isEmpty,
    );
    // The input's own sha256 is 64 hex digits; drop it before scanning for
    // 40-hex legacy UDIDs.
    (report['input']! as Map<String, Object?>)['sha256'] = null;
    final json = encodeReportJson(report);
    expect(json, isNot(matches(RegExp('[0-9a-f]{40}'))));
    expect(json, isNot(matches(RegExp('[0-9A-F]{8}-[0-9A-F]{16}'))));
    expect(json, isNot(contains('BEGIN CERTIFICATE')));
  }, skip: path == null ? 'set STUDIO_INSPECT_IPA=<path> to run' : false);
}
