import 'dart:io';

import 'package:studio_ext/src/shared/inspect/report_json.dart';
import 'package:test/test.dart';

import '../../support/fixture_builder.dart';
import '../../support/inspect_helpers.dart';

void main() {
  test('SC-001 20 MB IPA under 3 s', () {
    final temp = Directory.systemTemp.createTempSync('inspect_perf_');
    try {
      final bundle = unsignedV209();
      bundle.files['Frameworks/App.framework/App'] = machO(
        signature: codeSignature(identifier: 'io.flutter.flutter.app'),
        bodySize: 20 * 1024 * 1024,
        seed: 42,
      );
      final path = bundle.writeIpa(temp, 'big.ipa', compress: true);
      expect(File(path).lengthSync(), greaterThan(19 * 1024 * 1024));

      final stopwatch = Stopwatch()..start();
      final json = encodeReportJson(inspectPath(path).toJson());
      stopwatch.stop();

      expect(json, contains('"Frameworks/App.framework/App"'));
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 3)),
        reason: 'took ${stopwatch.elapsedMilliseconds} ms',
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
}
