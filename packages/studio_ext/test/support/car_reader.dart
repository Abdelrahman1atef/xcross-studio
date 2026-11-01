// studio: 004 — a minimal BOM / Assets.car reader for structural tests.
import 'dart:convert';
import 'dart:typed_data';

/// One BOM tree: header fields plus `(key, value)` per leaf entry. For
/// inline-key trees the key is the 4-byte big-endian inline value.
final class CarTree {
  CarTree({
    required this.blockSize,
    required this.pathInternal,
    required this.leafLength,
    required this.leafCount,
    required this.entries,
    required this.idPairs,
  });

  final int blockSize;
  final bool pathInternal;
  final int leafLength;
  final int leafCount;
  final List<(Uint8List, Uint8List)> entries;

  /// `(valueBlockID, keyBlockID or inline key)` per leaf entry.
  final List<(int, int)> idPairs;
}

final class CarFile {
  CarFile(this.bytes) : _data = ByteData.sublistView(bytes) {
    if (ascii.decode(bytes.sublist(0, 8)) != 'BOMStore') {
      throw const FormatException('not a BOM file');
    }
    final indexOffset = _data.getUint32(0x10);
    final count = _data.getUint32(indexOffset);
    for (var i = 0; i < count; i++) {
      _blocks.add((
        _data.getUint32(indexOffset + 4 + i * 8),
        _data.getUint32(indexOffset + 8 + i * 8),
      ));
    }
    final varsOffset = _data.getUint32(0x18);
    final varCount = _data.getUint32(varsOffset);
    var cursor = varsOffset + 4;
    for (var i = 0; i < varCount; i++) {
      final id = _data.getUint32(cursor);
      final length = bytes[cursor + 4];
      final name = utf8.decode(bytes.sublist(cursor + 5, cursor + 5 + length));
      variables[name] = id;
      cursor += 5 + length;
    }
  }

  final Uint8List bytes;
  final ByteData _data;
  final List<(int, int)> _blocks = [];

  /// Variable name → block id, in table order.
  final Map<String, int> variables = {};

  int get blockCount => _blocks.length;

  Uint8List block(int id) {
    final (address, length) = _blocks[id];
    return Uint8List.sublistView(bytes, address, address + length);
  }

  Uint8List variable(String name) => block(variables[name]!);

  CarTree tree(String name) {
    final header = ByteData.sublistView(variable(name));
    if (header.getUint32(0) != 0x74726565) {
      throw FormatException('$name is not a tree');
    }
    final leafId = header.getUint32(8);
    final pathInternal = header.getUint8(20) == 1;
    final leafBytes = block(leafId);
    final leaf = ByteData.sublistView(leafBytes);
    final count = leaf.getUint16(2);
    final entries = <(Uint8List, Uint8List)>[];
    final ids = <(int, int)>[];
    for (var i = 0; i < count; i++) {
      final valueId = leaf.getUint32(12 + i * 8);
      final keyId = leaf.getUint32(16 + i * 8);
      ids.add((valueId, keyId));
      entries.add((
        pathInternal
            ? (Uint8List(4)..buffer.asByteData().setUint32(0, keyId))
            : block(keyId),
        block(valueId),
      ));
    }
    return CarTree(
      blockSize: header.getUint32(12),
      pathInternal: pathInternal,
      leafLength: leafBytes.length,
      leafCount: leaf.getUint16(0) == 1 ? count : -1,
      entries: entries,
      idPairs: ids,
    );
  }

  /// FACETKEYS asset names.
  List<String> get facetNames => [
    for (final (key, _) in tree('FACETKEYS').entries) utf8.decode(key),
  ];

  /// RENDITIONS as `(key slots, CSI bytes)`.
  List<(List<int>, Uint8List)> get renditions => [
    for (final (key, value) in tree('RENDITIONS').entries)
      (
        [for (var i = 0; i < key.length; i += 2) key[i] | key[i + 1] << 8],
        value,
      ),
  ];
}

/// Little-endian reads over a CSI record.
final class Csi {
  Csi(this.bytes) : data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData data;

  int u32(int offset) => data.getUint32(offset, Endian.little);
  int u16(int offset) => data.getUint16(offset, Endian.little);
  String get tag => ascii.decode(bytes.sublist(0, 4));
  int get flags => u32(8);
  int get width => u32(12);
  int get height => u32(16);
  int get scaleFactor => u32(20);
  String get pixelFormat => ascii.decode(bytes.sublist(24, 28));
  int get colorSpace => u32(28);
  int get layout => u16(36);
  String get name {
    final field = bytes.sublist(40, 168);
    final end = field.indexOf(0);
    return utf8.decode(end < 0 ? field : field.sublist(0, end));
  }

  int get tvlLength => u32(168);
  int get bitmapCount => u32(172);
  int get renditionLength => u32(180);

  /// TVL entries as `type → value bytes`.
  Map<int, Uint8List> get tvl {
    final out = <int, Uint8List>{};
    var cursor = 184;
    while (cursor < 184 + tvlLength) {
      final type = u32(cursor);
      final length = u32(cursor + 4);
      out[type] = bytes.sublist(cursor + 8, cursor + 8 + length);
      cursor += 8 + length;
    }
    return out;
  }

  Uint8List get body => bytes.sublist(184 + tvlLength);

  /// The decoded pixels of an `MLEC` body made of `bvx-` stored frames.
  Uint8List get mlecPixels {
    final payload = body;
    final view = ByteData.sublistView(payload);
    if (ascii.decode(payload.sublist(0, 4)) != 'MLEC') {
      throw const FormatException('not MLEC');
    }
    final chunks = view.getUint32(12, Endian.little);
    final out = BytesBuilder();
    var cursor = 16;
    for (var i = 0; i < chunks; i++) {
      final size = view.getUint32(cursor + 16, Endian.little);
      final frame = payload.sublist(cursor + 20, cursor + 20 + size);
      final frameView = ByteData.sublistView(frame);
      if (ascii.decode(frame.sublist(0, 4)) != 'bvx-') {
        throw const FormatException('not a stored LZFSE block');
      }
      final rawLength = frameView.getUint32(4, Endian.little);
      out.add(frame.sublist(8, 8 + rawLength));
      if (ascii.decode(frame.sublist(8 + rawLength, 12 + rawLength)) !=
          r'bvx$') {
        throw const FormatException('missing LZFSE end of stream');
      }
      cursor += 20 + size;
    }
    return out.toBytes();
  }
}
