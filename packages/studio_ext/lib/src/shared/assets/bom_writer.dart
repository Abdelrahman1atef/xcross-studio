// studio: 004 — ported from xtool-org/AssetKit (MIT, see
// packages/studio_ext/THIRD_PARTY_NOTICES.md): BOM/BOMWriter.swift and
// BOM/BOMTree.swift.
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/assets/asset_byte_writer.dart';

/// Writes a BOM ("Bill of Materials") container, big-endian throughout:
/// a 512-byte header area, the block payloads, the block index
/// (`count`, then `(address, length)` per block; block 0 is null) and the
/// variables table (`count`, then `blockID u32, nameLength u8, name`).
@internal
final class BomWriter {
  static const headerSize = 512;

  final List<Uint8List> _blocks = [Uint8List(0)];
  final List<(String, int)> _variables = [];

  int get blockCount => _blocks.length;

  /// Adds a block and returns its id.
  int addBlock(Uint8List data) {
    _blocks.add(data);
    return _blocks.length - 1;
  }

  /// Names [blockId]; the variables table keeps insertion order, which
  /// CoreUI relies on.
  void setVariable(String name, int blockId) {
    if (utf8.encode(name).length > 255) {
      throw ArgumentError.value(name, 'name', 'longer than 255 bytes');
    }
    _variables.add((name, blockId));
  }

  Uint8List finalize() {
    final addresses = <int>[0];
    var offset = headerSize;
    for (final block in _blocks.skip(1)) {
      addresses.add(offset);
      offset += block.length;
    }
    final indexOffset = offset;
    final indexLength = 4 + _blocks.length * 8;
    final varsOffset = indexOffset + indexLength;
    final names = [for (final (name, _) in _variables) utf8.encode(name)];
    final varsLength =
        4 + names.fold<int>(0, (sum, name) => sum + 5 + name.length);

    final writer = AssetByteWriter()
      ..bytes(ascii.encode('BOMStore'))
      ..u32be(1)
      ..u32be(_blocks.length)
      ..u32be(indexOffset)
      ..u32be(indexLength)
      ..u32be(varsOffset)
      ..u32be(varsLength);
    writer.zeros(headerSize - writer.length);
    for (final block in _blocks.skip(1)) {
      writer.bytes(block);
    }
    writer.u32be(_blocks.length);
    for (var i = 0; i < _blocks.length; i++) {
      writer
        ..u32be(addresses[i])
        ..u32be(_blocks[i].length);
    }
    writer.u32be(_variables.length);
    for (var i = 0; i < _variables.length; i++) {
      writer
        ..u32be(_variables[i].$2)
        ..byte(names[i].length)
        ..bytes(names[i]);
    }
    return writer.toBytes();
  }
}

/// A BOM tree entry whose key lives in its own block.
@internal
final class BomTreeEntry {
  const BomTreeEntry(this.key, this.value);
  final Uint8List key;
  final Uint8List value;
}

/// A BOM tree entry whose key is an inline `u32` (`isPathInternal`).
@internal
final class BomInlineKeyEntry {
  const BomInlineKeyEntry(this.key, this.value);
  final int key;
  final Uint8List value;
}

/// Writes single-leaf BOM B+ trees.
///
/// Tree header: `'tree'`, version, child block id, block size, path count,
/// `isPathInternal u8`, 8 reserved zero bytes. Leaf: `isLeaf u16`,
/// `count u16`, forward and backward links, then `(valueID, keyID)` pairs,
/// zero-padded to the block size.
///
/// AssetKit always declares 4096 (1024 for inline-key trees); a leaf that
/// would not fit (more than ~500 entries) declares the next power of two
/// instead, so the leaf is never larger than its declared page.
@internal
abstract final class BomTree {
  static const treeMagic = 0x74726565; // 'tree'
  static const leafHeaderSize = 12;

  /// Inserts the tree into [bom] and returns the tree header's block id.
  static int insert(
    BomWriter bom,
    List<BomTreeEntry> entries, {
    int blockSize = 4096,
  }) {
    final sorted = [...entries]..sort((a, b) => compareBytes(a.key, b.key));
    final valueIds = <int>[];
    final keyIds = <int>[];
    for (final entry in sorted) {
      // actool allocates the value block before its key block; iOS walks
      // the leaf assuming value-first ids.
      valueIds.add(bom.addBlock(entry.value));
      keyIds.add(bom.addBlock(entry.key));
    }
    return _writeLeafAndHeader(
      bom,
      [for (var i = 0; i < sorted.length; i++) (valueIds[i], keyIds[i])],
      blockSize: blockSize,
      pathInternal: false,
    );
  }

  /// Inserts a tree whose leaf entries carry inline `u32` keys.
  static int insertInlineKey(
    BomWriter bom,
    List<BomInlineKeyEntry> entries, {
    int blockSize = 1024,
  }) {
    final sorted = [...entries]..sort((a, b) => a.key.compareTo(b.key));
    final pairs = [
      for (final entry in sorted) (bom.addBlock(entry.value), entry.key),
    ];
    return _writeLeafAndHeader(
      bom,
      pairs,
      blockSize: blockSize,
      pathInternal: true,
    );
  }

  /// The page size declared for a leaf with [count] entries.
  static int pageSizeFor(int count, int minimum) {
    final needed = leafHeaderSize + count * 8;
    var size = minimum;
    while (size < needed) {
      size *= 2;
    }
    return size;
  }

  static int _writeLeafAndHeader(
    BomWriter bom,
    List<(int, int)> pairs, {
    required int blockSize,
    required bool pathInternal,
  }) {
    final pageSize = pageSizeFor(pairs.length, blockSize);
    final leaf = AssetByteWriter()
      ..u16be(1)
      ..u16be(pairs.length)
      ..u32be(0)
      ..u32be(0);
    for (final (value, key) in pairs) {
      leaf
        ..u32be(value)
        ..u32be(key);
    }
    leaf.zeros(pageSize - leaf.length);
    final leafId = bom.addBlock(leaf.toBytes());

    final header = AssetByteWriter()
      ..u32be(treeMagic)
      ..u32be(1)
      ..u32be(leafId)
      ..u32be(pageSize)
      ..u32be(pairs.length)
      ..byte(pathInternal ? 1 : 0)
      ..zeros(8);
    return bom.addBlock(header.toBytes());
  }

  /// Lexicographic byte order, shorter first on a common prefix.
  static int compareBytes(List<int> a, List<int> b) {
    final count = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < count; i++) {
      if (a[i] != b[i]) return a[i] < b[i] ? -1 : 1;
    }
    return a.length.compareTo(b.length);
  }
}
