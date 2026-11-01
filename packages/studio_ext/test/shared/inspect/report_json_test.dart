import 'package:studio_ext/src/shared/inspect/report_json.dart';
import 'package:test/test.dart';

void main() {
  group('encodeReportJson', () {
    test('escapes every non-ASCII code unit, including surrogate pairs', () {
      final text = encodeReportJson({'a': 'é ✔ 😀'});
      expect(text, contains(r'"\u00e9 \u2714 \ud83d\ude00"'));
      expect(
        text.codeUnits.every((unit) => unit <= 0x7e || unit == 0x0a),
        isTrue,
      );
    });

    test('keeps insertion order, two-space indent, one trailing LF', () {
      final text = encodeReportJson({
        'z': 1,
        'a': [true, null],
      });
      expect(text, '{\n  "z": 1,\n  "a": [\n    true,\n    null\n  ]\n}\n');
      expect(text, isNot(contains('\r')));
      expect(text.endsWith('}\n'), isTrue);
      expect(text.endsWith('\n\n'), isFalse);
    });

    test('escapes DEL', () {
      expect(encodeReportJson('\u007f'), '"\\u007f"\n');
    });
  });
}
