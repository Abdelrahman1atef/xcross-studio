import 'dart:convert';
import 'dart:typed_data';

import 'package:studio_ext/src/shared/inspect/ber_reader.dart';
import 'package:test/test.dart';

void main() {
  Uint8List bytes(List<int> values) => Uint8List.fromList(values);

  test('reads definite short and long lengths', () {
    final short = bytes([0x04, 0x02, 0x41, 0x42]);
    final element = readBer(short);
    expect(element.isUniversal(BerTag.octetString), isTrue);
    expect(utf8.decode(octetStringValue(short, element)), 'AB');

    final payload = List.filled(300, 0x41);
    final long = bytes([0x04, 0x82, 0x01, 0x2c, ...payload]);
    expect(octetStringValue(long, readBer(long)).length, 300);
  });

  test('reads nested indefinite lengths', () {
    final data = bytes([
      0x30, 0x80, // SEQUENCE, indefinite
      0xa0, 0x80, // [0], indefinite
      0x02, 0x01, 0x05, // INTEGER 5
      0x00, 0x00,
      0x00, 0x00,
    ]);
    final sequence = readBer(data);
    expect(sequence.isUniversal(BerTag.sequence), isTrue);
    expect(sequence.elementEnd, data.length);
    final context = sequence.children.single;
    expect(context.isContext(0), isTrue);
    expect(context.children.single.isUniversal(BerTag.integer), isTrue);
  });

  test('concatenates a chunked constructed OCTET STRING', () {
    final data = bytes([
      0x24, 0x80, //
      0x04, 0x02, 0x48, 0x69, // "Hi"
      0x04, 0x01, 0x21, // "!"
      0x00, 0x00,
    ]);
    expect(utf8.decode(octetStringValue(data, readBer(data))), 'Hi!');
  });

  test('decodes object identifiers', () {
    final data = bytes([
      0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02, //
    ]);
    expect(objectIdentifierValue(data, readBer(data)), '1.2.840.113549.1.7.2');
  });

  test('throws FormatException on truncated input', () {
    expect(() => readBer(bytes([0x04, 0x05, 0x41])), throwsFormatException);
    expect(
      () => readBer(bytes([0x30, 0x80, 0x02, 0x01, 0x05])),
      throwsFormatException,
    );
    expect(() => readBer(bytes([0x04])), throwsFormatException);
  });
}
