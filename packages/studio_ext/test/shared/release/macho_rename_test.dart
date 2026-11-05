// studio: 018 — changing the library paths of a Mach-O file in place.
import 'dart:convert';
import 'dart:typed_data';

import 'package:studio_ext/shared/release/macho_rename.dart';
import 'package:studio_ext/src/shared/release/macho_dylibs.dart';
import 'package:test/test.dart';

const _le = Endian.little;

Uint8List _dylibCommand(int command, String path) {
  final name = utf8.encode(path);
  final size = (24 + name.length + 1 + 7) ~/ 8 * 8;
  final bytes = Uint8List(size);
  ByteData.sublistView(bytes)
    ..setUint32(0, command, _le)
    ..setUint32(4, size, _le)
    ..setUint32(8, 24, _le);
  bytes.setRange(24, 24 + name.length, name);
  return bytes;
}

/// A thin arm64 Mach-O with [commands] and one section of 8 bytes of `0xAB`
/// at [sectionOffset].
Uint8List _machO(List<Uint8List> commands, {int sectionOffset = 0x1000}) {
  final segment = Uint8List(72 + 80);
  ByteData.sublistView(segment)
    ..setUint32(0, 0x19, _le)
    ..setUint32(4, segment.length, _le)
    ..setUint32(64, 1, _le) // one section
    ..setUint64(72 + 40, 8, _le) // section size
    ..setUint32(72 + 48, sectionOffset, _le);
  final all = [...commands, segment];
  final total = all.fold<int>(0, (sum, c) => sum + c.length);
  final bytes = Uint8List(sectionOffset + 16);
  ByteData.sublistView(bytes)
    ..setUint32(0, 0xfeedfacf, _le)
    ..setInt32(4, 0x0100000c, _le)
    ..setUint32(12, 6, _le)
    ..setUint32(16, all.length, _le)
    ..setUint32(20, total, _le);
  var offset = 32;
  for (final command in all) {
    bytes.setRange(offset, offset + command.length, command);
    offset += command.length;
  }
  bytes.fillRange(sectionOffset, sectionOffset + 8, 0xab);
  return bytes;
}

List<String> _paths(Uint8List bytes) => [
  for (final library in MachODylib.read(bytes)) library.path,
];

void main() {
  const idPath = '@rpath/libPlugins.dylib';
  const longer = '@rpath/Plugins.framework/Plugins';

  test('a longer path grows into the padding and nothing else moves', () {
    final original = _machO([
      _dylibCommand(0xd, idPath),
      _dylibCommand(0xc, idPath),
      _dylibCommand(0xc, '/usr/lib/libSystem.B.dylib'),
    ]);
    final rewritten = renameDylibPaths(
      original,
      (command, path) => path == idPath ? longer : null,
    )!;
    expect(rewritten.length, original.length);
    expect(
      rewritten.sublist(0x1000, 0x1008),
      original.sublist(0x1000, 0x1008),
      reason: 'section data is where it was',
    );
    // The id command is not a dependency, so only the load shows.
    expect(_paths(rewritten), [longer, '/usr/lib/libSystem.B.dylib']);
    final view = ByteData.sublistView(rewritten);
    expect(view.getUint32(16, _le), 4, reason: 'same number of commands');
    expect(
      view.getUint32(20, _le),
      greaterThan(ByteData.sublistView(original).getUint32(20, _le)),
    );
    // The install name was seen with command 0xd.
    final seen = <int>[];
    renameDylibPaths(rewritten, (command, path) {
      seen.add(command);
      return null;
    });
    expect(seen, [0xd, 0xc, 0xc]);
  });

  test('a shorter path leaves zeros, and no change returns null', () {
    final original = _machO([_dylibCommand(0xc, longer)]);
    final rewritten = renameDylibPaths(
      original,
      (command, path) => '@rpath/a',
    )!;
    expect(_paths(rewritten), ['@rpath/a']);
    expect(renameDylibPaths(original, (command, path) => null), isNull);
    expect(renameDylibPaths(original, (command, path) => path), isNull);
  });

  test('the header padding must be free and big enough', () {
    // The section starts right after the commands: no room to grow.
    final tight = _machO([_dylibCommand(0xc, idPath)], sectionOffset: 0xf0);
    expect(
      () => renameDylibPaths(tight, (command, path) => longer),
      throwsFormatException,
    );
    // Padding that is not zeros is not ours to use.
    final used = _machO([_dylibCommand(0xc, idPath)]);
    used[32 + 48 + 152 + 4] = 1; // inside the 16 bytes the new path needs
    expect(
      () => renameDylibPaths(used, (command, path) => longer),
      throwsFormatException,
    );
  });

  test('fat and 32-bit files are refused, not damaged', () {
    final fat = Uint8List(64)..setRange(0, 4, [0xca, 0xfe, 0xba, 0xbe]);
    expect(
      () => renameDylibPaths(fat, (command, path) => 'x'),
      throwsFormatException,
    );
    expect(looksLikeMachO(fat), isTrue);
    expect(looksLikeMachO(Uint8List.fromList([1, 2, 3, 4])), isFalse);
  });
}
