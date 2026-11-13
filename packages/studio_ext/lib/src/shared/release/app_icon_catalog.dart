// studio: 004 — what App Store Connect reads the app icon from: the icon set
// records (rendition part 218, one per idiom) of the app icon in Assets.car.
// An IPA without them gets Apple's grey placeholder icon.
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// The icon set records an `Assets.car` holds for one app icon name.
@internal
@immutable
final class AppIconCatalogEntry {
  const AppIconCatalogEntry({required this.named, required this.idioms});

  /// Whether FACETKEYS lists the icon name at all.
  final bool named;

  /// CoreUI idiom codes with an icon set record for the name
  /// (1 iPhone, 2 iPad, 6 App Store "ios-marketing", …).
  final Set<int> idioms;
}

/// Reads the app icon's icon set records from `Assets.car` bytes.
///
/// It reads the file's own KEYFORMAT and FACETKEYS (Xcode's actool and
/// xcross number asset identifiers differently) and walks BOM trees of any
/// depth.
@internal
abstract final class AppIconCatalog {
  static const partIconSet = 218;
  static const idiomMarketing = 6;

  static const _attributePart = 2;
  static const _attributeIdiom = 15;
  static const _attributeIdentifier = 17;
  static const _keyFormatMagic = 0x6B666D74; // 'kfmt'
  static const _treeMagic = 0x74726565; // 'tree'

  /// The records for [iconName]; throws [FormatException] when [car] is not a
  /// readable catalog.
  static AppIconCatalogEntry read(Uint8List car, String iconName) {
    try {
      return _read(car, iconName);
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      // Out-of-range reads of a truncated or damaged file.
      throw FormatException('damaged Assets.car ($error)');
    }
  }

  static AppIconCatalogEntry _read(Uint8List car, String iconName) {
    final bom = CatalogBom(car);
    final format = _keyFormat(bom.variable('KEYFORMAT'));
    final partSlot = format.indexOf(_attributePart);
    final idiomSlot = format.indexOf(_attributeIdiom);
    final identifierSlot = format.indexOf(_attributeIdentifier);
    if (partSlot < 0 || idiomSlot < 0 || identifierSlot < 0) {
      throw const FormatException('KEYFORMAT has no part, idiom or identifier');
    }

    int? identifier;
    for (final (key, value) in bom.tree('FACETKEYS')) {
      if (_name(key) != iconName) continue;
      identifier = _facetIdentifier(value);
      break;
    }
    if (identifier == null) {
      return const AppIconCatalogEntry(named: false, idioms: {});
    }

    final idioms = <int>{};
    for (final (key, _) in bom.tree('RENDITIONS')) {
      if (key.length < format.length * 2) continue;
      final slots = ByteData.sublistView(key);
      int slot(int index) => slots.getUint16(index * 2, Endian.little);
      if (slot(partSlot) == partIconSet && slot(identifierSlot) == identifier) {
        idioms.add(slot(idiomSlot));
      }
    }
    return AppIconCatalogEntry(named: true, idioms: idioms);
  }

  /// KEYFORMAT: `'kfmt'`, version, count, then `count` attribute ids (LE).
  static List<int> _keyFormat(Uint8List block) {
    final data = ByteData.sublistView(block);
    if (block.length < 12 ||
        (data.getUint32(0, Endian.little) != _keyFormatMagic &&
            data.getUint32(0) != _keyFormatMagic)) {
      throw const FormatException('no KEYFORMAT');
    }
    final count = data.getUint32(8, Endian.little);
    if (12 + count * 4 > block.length) {
      throw const FormatException('KEYFORMAT is cut short');
    }
    return [
      for (var i = 0; i < count; i++) data.getUint32(12 + i * 4, Endian.little),
    ];
  }

  /// A FACETKEYS value: hot spot (2 × u16), attribute count (u16), then
  /// `(attribute, value)` u16 pairs, all LE.
  static int? _facetIdentifier(Uint8List value) {
    if (value.length < 6) return null;
    final data = ByteData.sublistView(value);
    final count = data.getUint16(4, Endian.little);
    for (var i = 0; i < count; i++) {
      final offset = 6 + i * 4;
      if (offset + 4 > value.length) return null;
      if (data.getUint16(offset, Endian.little) == _attributeIdentifier) {
        return data.getUint16(offset + 2, Endian.little);
      }
    }
    return null;
  }

  static String _name(Uint8List key) {
    var end = key.length;
    while (end > 0 && key[end - 1] == 0) {
      end--;
    }
    return utf8.decode(key.sublist(0, end), allowMalformed: true);
  }
}

/// The parts of a BOM file the icon lookup needs (big-endian structures).
@internal
final class CatalogBom {
  CatalogBom(this.bytes) : _data = ByteData.sublistView(bytes) {
    if (bytes.length < 32 ||
        ascii.decode(bytes.sublist(0, 8), allowInvalid: true) != 'BOMStore') {
      throw const FormatException('not a BOM file');
    }
    final indexOffset = _data.getUint32(16);
    final count = _data.getUint32(indexOffset);
    for (var i = 0; i < count; i++) {
      _blocks.add((
        _data.getUint32(indexOffset + 4 + i * 8),
        _data.getUint32(indexOffset + 8 + i * 8),
      ));
    }
    final varsOffset = _data.getUint32(24);
    final varCount = _data.getUint32(varsOffset);
    var cursor = varsOffset + 4;
    for (var i = 0; i < varCount; i++) {
      final id = _data.getUint32(cursor);
      final length = bytes[cursor + 4];
      final name = ascii.decode(
        bytes.sublist(cursor + 5, cursor + 5 + length),
        allowInvalid: true,
      );
      _variables[name] = id;
      cursor += 5 + length;
    }
  }

  final Uint8List bytes;
  final ByteData _data;
  final List<(int, int)> _blocks = [];
  final Map<String, int> _variables = {};

  Uint8List block(int id) {
    if (id < 0 || id >= _blocks.length) {
      throw FormatException('no block $id');
    }
    final (address, length) = _blocks[id];
    if (address + length > bytes.length) {
      throw FormatException('block $id is outside the file');
    }
    return Uint8List.sublistView(bytes, address, address + length);
  }

  Uint8List variable(String name) {
    final id = _variables[name];
    if (id == null) throw FormatException('no $name');
    return block(id);
  }

  /// Every `(key, value)` of the tree [name], whatever its depth: non-leaf
  /// paths are followed to their children, and leaves to their `forward`
  /// neighbours, each path read once.
  List<(Uint8List, Uint8List)> tree(String name) {
    final header = ByteData.sublistView(variable(name));
    if (header.lengthInBytes < 12 ||
        header.getUint32(0) != AppIconCatalog._treeMagic) {
      throw FormatException('$name is not a tree');
    }
    final entries = <(Uint8List, Uint8List)>[];
    final seen = <int>{};
    final pending = [header.getUint32(8)];
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (id == 0 || !seen.add(id)) continue;
      final path = block(id);
      final data = ByteData.sublistView(path);
      if (path.length < 12) throw FormatException('$name path $id is short');
      final leaf = data.getUint16(0) == 1;
      final count = data.getUint16(2);
      final forward = data.getUint32(4);
      if (12 + count * 8 > path.length) {
        throw FormatException('$name path $id is cut short');
      }
      for (var i = 0; i < count; i++) {
        final first = data.getUint32(12 + i * 8);
        final second = data.getUint32(16 + i * 8);
        if (leaf) {
          entries.add((block(second), block(first)));
        } else {
          pending.add(first);
        }
      }
      if (leaf) pending.add(forward);
    }
    return entries;
  }
}
