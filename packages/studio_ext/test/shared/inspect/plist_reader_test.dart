import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:studio_ext/src/shared/inspect/plist_reader.dart';
import 'package:test/test.dart';

import '../../support/fixture_builder.dart';

void main() {
  final sample = <String, Object>{
    'b': 'two',
    'a': 1,
    'date': DateTime.utc(2027, 3, 4, 5, 6, 7),
    'data': ByteData.sublistView(Uint8List.fromList([1, 2, 3])),
    'list': [true, 1.5],
  };

  test('reads XML and binary plists and reports the format', () {
    final xml = readPlist(xmlPlist(sample));
    final binary = readPlist(binaryPlist(sample));
    expect(xml?.format, PlistFormat.xml);
    expect(binary?.format, PlistFormat.binary);
    expect(xml?.dictionary?['b'], 'two');
    expect(binary?.dictionary?['a'], 1);
  });

  test('accepts a UTF-8 BOM before the XML declaration', () {
    final bytes = Uint8List.fromList([0xef, 0xbb, 0xbf, ...xmlPlist(sample)]);
    expect(readPlist(bytes)?.dictionary?['b'], 'two');
  });

  test('maps values to deterministic JSON with sorted keys', () {
    final json = plistToJson(readPlist(binaryPlist(sample))!.root)!;
    expect(
      jsonEncode(json),
      jsonEncode({
        'a': 1,
        'b': 'two',
        'data': {r'$data': 'AQID'},
        'date': '2027-03-04T05:06:07Z',
        'list': [true, 1.5],
      }),
    );
  });

  test('returns null for non-plist or malformed input without printing', () {
    final printed = <String>[];
    runZoned(
      () {
        expect(readPlist(Uint8List.fromList(utf8.encode('hello'))), isNull);
        expect(
          readPlist(
            Uint8List.fromList(
              utf8.encode('<?xml version="1.0"?><plist><dict><key>a</key>'),
            ),
          ),
          isNull,
        );
        expect(
          readPlist(Uint8List.fromList([...utf8.encode('bplist00'), 1, 2])),
          isNull,
        );
      },
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );
    expect(printed, isEmpty);
  });
}
