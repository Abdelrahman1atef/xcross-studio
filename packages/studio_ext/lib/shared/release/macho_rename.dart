// studio: 018 — changing the library paths a Mach-O file records (what
// `install_name_tool -id` and `-change` do), so a loose `libX.dylib` can become
// `X.framework/X` (App Store Connect 90429: iOS allows dynamic libraries only
// inside framework bundles, apart from the Swift runtime).
import 'dart:convert';
import 'dart:typed_data';

const _lcIdDylib = 0xd;
const _lcLoadDylib = 0xc;
const _lcLoadWeakDylib = 0x80000018;
const _lcReexportDylib = 0x8000001f;
const _lcSegment64 = 0x19;
const _dylibCommands = {
  _lcIdDylib,
  _lcLoadDylib,
  _lcLoadWeakDylib,
  _lcReexportDylib,
};

/// Whether [bytes] begins like a Mach-O file (thin or fat).
bool looksLikeMachO(Uint8List bytes) {
  if (bytes.length < 4) return false;
  final magic =
      (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  return const {
    0xfeedface,
    0xfeedfacf,
    0xcefaedfe,
    0xcffaedfe,
    0xcafebabe,
    0xbebafeca,
    0xcafebabf,
    0xbfbafeca,
  }.contains(magic);
}

/// Rewrites the install name and the loaded-library paths of a thin 64-bit
/// little-endian Mach-O file. [rename] gets the load command (`0xd` is the
/// file's own install name) and the recorded path, and returns the new path or
/// null to keep it.
///
/// Returns the new bytes, or null when nothing changed. The longer names grow
/// into the zero padding after the load commands, so no section moves; the
/// signature is stale afterwards and has to be made again.
///
/// Throws a [FormatException] for a file this cannot rewrite safely (a fat
/// file, 32-bit code, or too little padding for the longer names).
Uint8List? renameDylibPaths(
  Uint8List bytes,
  String? Function(int command, String path) rename,
) {
  if (bytes.length < 32) throw const FormatException('not a Mach-O file');
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(0, Endian.little) != 0xfeedfacf) {
    throw const FormatException('only thin 64-bit Mach-O files are rewritten');
  }
  final count = data.getUint32(16, Endian.little);
  final commandsSize = data.getUint32(20, Endian.little);
  const header = 32;
  if (header + commandsSize > bytes.length) {
    throw const FormatException('load commands run past the end of the file');
  }

  final commands = <Uint8List>[];
  var firstContent = bytes.length;
  var offset = header;
  var changed = false;
  for (var i = 0; i < count; i++) {
    final command = data.getUint32(offset, Endian.little);
    final size = data.getUint32(offset + 4, Endian.little);
    if (size < 8 || offset + size > header + commandsSize) {
      throw const FormatException('a load command has a bad size');
    }
    final original = Uint8List.sublistView(bytes, offset, offset + size);
    if (command == _lcSegment64) {
      final sections = data.getUint32(offset + 64, Endian.little);
      for (var s = 0; s < sections; s++) {
        final at = offset + 72 + s * 80;
        final sectionSize = data.getUint64(at + 40, Endian.little);
        final sectionOffset = data.getUint32(at + 48, Endian.little);
        if (sectionOffset != 0 && sectionSize != 0) {
          if (sectionOffset < firstContent) firstContent = sectionOffset;
        }
      }
    }
    if (_dylibCommands.contains(command) && size > 24) {
      final nameOffset = data.getUint32(offset + 8, Endian.little);
      if (nameOffset >= 12 && nameOffset < size) {
        final raw = original.sublist(nameOffset);
        final end = raw.indexOf(0);
        final path = utf8.decode(end < 0 ? raw : raw.sublist(0, end));
        final renamed = rename(command, path);
        if (renamed != null && renamed != path) {
          commands.add(_dylibCommand(original, command, renamed));
          changed = true;
          offset += size;
          continue;
        }
      }
    }
    commands.add(Uint8List.fromList(original));
    offset += size;
  }
  if (!changed) return null;

  final newSize = commands.fold<int>(0, (sum, c) => sum + c.length);
  if (header + newSize > firstContent) {
    throw const FormatException(
      'no room after the load commands for the longer library path',
    );
  }
  for (var i = header + commandsSize; i < header + newSize; i++) {
    if (bytes[i] != 0) {
      throw const FormatException(
        'the padding after the load commands is in use',
      );
    }
  }
  final result = Uint8List.fromList(bytes);
  var at = header;
  for (final command in commands) {
    result.setRange(at, at + command.length, command);
    at += command.length;
  }
  for (var i = at; i < header + commandsSize; i++) {
    result[i] = 0; // a shorter set of commands leaves zeros
  }
  ByteData.sublistView(result).setUint32(20, newSize, Endian.little);
  return result;
}

/// [original] with its path replaced by [path], padded to 8 bytes.
Uint8List _dylibCommand(Uint8List original, int command, String path) {
  final name = utf8.encode(path);
  final size = (24 + name.length + 1 + 7) ~/ 8 * 8;
  final result = Uint8List(size);
  result.setRange(0, 24, original.sublist(0, 24)); // timestamps and versions
  ByteData.sublistView(result)
    ..setUint32(0, command, Endian.little)
    ..setUint32(4, size, Endian.little)
    ..setUint32(8, 24, Endian.little);
  result.setRange(24, 24 + name.length, name);
  return result;
}
