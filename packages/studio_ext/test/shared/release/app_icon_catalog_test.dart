// studio: 004 — reading the app icon's icon set records from Assets.car the
// way Xcode's actool lays them out, not only the way xcross writes them.
import 'dart:convert';
import 'dart:typed_data';

import 'package:studio_ext/src/shared/assets/bom_writer.dart';
import 'package:studio_ext/src/shared/release/app_icon_catalog.dart';
import 'package:test/test.dart';

/// KEYFORMAT in an order xcross never writes: identifier, part, idiom first.
const _format = [17, 2, 15, 12, 7, 13, 16, 9, 1];

Uint8List _u32le(List<int> values) {
  final data = ByteData(values.length * 4);
  for (var i = 0; i < values.length; i++) {
    data.setUint32(i * 4, values[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

Uint8List _key({required int identifier, required int part, int idiom = 1}) {
  final slots = {17: identifier, 2: part, 15: idiom, 12: 1, 1: 85};
  final data = ByteData(_format.length * 2);
  for (var i = 0; i < _format.length; i++) {
    data.setUint16(i * 2, slots[_format[i]] ?? 0, Endian.little);
  }
  return data.buffer.asUint8List();
}

Uint8List _facet(int identifier) {
  final data = ByteData(6 + 3 * 4)
    ..setUint16(4, 3, Endian.little)
    ..setUint16(6, 1, Endian.little)
    ..setUint16(8, 85, Endian.little)
    ..setUint16(10, 2, Endian.little)
    ..setUint16(12, 220, Endian.little)
    ..setUint16(14, 17, Endian.little)
    ..setUint16(16, identifier, Endian.little);
  return data.buffer.asUint8List();
}

Uint8List _path({
  required bool leaf,
  required List<(int, int)> pairs,
  int forward = 0,
}) {
  final data = ByteData(12 + pairs.length * 8)
    ..setUint16(0, leaf ? 1 : 0)
    ..setUint16(2, pairs.length)
    ..setUint32(4, forward);
  for (var i = 0; i < pairs.length; i++) {
    data
      ..setUint32(12 + i * 8, pairs[i].$1)
      ..setUint32(16 + i * 8, pairs[i].$2);
  }
  return data.buffer.asUint8List();
}

Uint8List _treeHeader(int root) {
  final data = ByteData(21)
    ..setUint32(0, 0x74726565)
    ..setUint32(4, 1)
    ..setUint32(8, root)
    ..setUint32(12, 4096)
    ..setUint32(16, 2);
  return data.buffer.asUint8List();
}

/// A catalog whose RENDITIONS tree has a non-leaf root over two leaves, and
/// whose AppIcon identifier is 7 (actool's numbering, not xcross's CRC).
Uint8List _actoolStyleCatalog({bool marketing = true}) {
  final bom = BomWriter();
  bom.setVariable(
    'KEYFORMAT',
    bom.addBlock(_u32le([0x6B666D74, 0, _format.length, ..._format])),
  );

  final facetValue = bom.addBlock(_facet(7));
  final facetKey = bom.addBlock(Uint8List.fromList(utf8.encode('AppIcon')));
  final facetLeaf = bom.addBlock(
    _path(leaf: true, pairs: [(facetValue, facetKey)]),
  );
  bom.setVariable('FACETKEYS', bom.addBlock(_treeHeader(facetLeaf)));

  (int, int) pair(Uint8List key) =>
      (bom.addBlock(Uint8List.fromList(utf8.encode('csi'))), bom.addBlock(key));

  // Another asset's icon set (identifier 9) must not count.
  final secondLeaf = bom.addBlock(
    _path(
      leaf: true,
      pairs: [
        if (marketing) pair(_key(identifier: 7, part: 218, idiom: 6)),
        pair(_key(identifier: 9, part: 218, idiom: 2)),
      ],
    ),
  );
  final firstLeaf = bom.addBlock(
    _path(
      leaf: true,
      pairs: [
        pair(_key(identifier: 7, part: 220)),
        pair(_key(identifier: 7, part: 218)),
      ],
      forward: secondLeaf,
    ),
  );
  final root = bom.addBlock(
    _path(
      leaf: false,
      pairs: [
        (firstLeaf, bom.addBlock(_key(identifier: 7, part: 218))),
        (secondLeaf, bom.addBlock(_key(identifier: 9, part: 218))),
      ],
    ),
  );
  bom.setVariable('RENDITIONS', bom.addBlock(_treeHeader(root)));
  return bom.finalize();
}

void main() {
  test('finds icon sets in every leaf of a multi-level tree, by FACETKEYS '
      'identifier and by the KEYFORMAT the file declares', () {
    final entry = AppIconCatalog.read(_actoolStyleCatalog(), 'AppIcon');
    expect(entry.named, isTrue);
    expect(entry.idioms, {1, AppIconCatalog.idiomMarketing});
  });

  test('a missing marketing record leaves only the iPhone idiom', () {
    final entry = AppIconCatalog.read(
      _actoolStyleCatalog(marketing: false),
      'AppIcon',
    );
    expect(entry.idioms, {1});
  });

  test('an unknown icon name is not named', () {
    final entry = AppIconCatalog.read(_actoolStyleCatalog(), 'Other');
    expect(entry.named, isFalse);
    expect(entry.idioms, isEmpty);
  });

  test('damaged files throw FormatException only', () {
    final good = _actoolStyleCatalog();
    for (final bytes in [
      Uint8List(0),
      Uint8List.fromList(utf8.encode('not a catalog at all, just text')),
      Uint8List.fromList([
        ...utf8.encode('BOMStore'),
        ...List.filled(40, 0xff),
      ]),
      Uint8List.sublistView(good, 0, good.length ~/ 2),
    ]) {
      expect(
        () => AppIconCatalog.read(bytes, 'AppIcon'),
        throwsA(isA<FormatException>()),
      );
    }
  });
}
