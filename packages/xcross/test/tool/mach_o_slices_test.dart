import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:xcross/src/shared/tool/mach_o_slices.dart';

void main() {
  test('AC-046-8 reads every FAT_MAGIC_64 slice', () {
    final bytes = Uint8List(96);
    final data = ByteData.sublistView(bytes);
    data.setUint32(0, 0xcafebabf);
    data.setUint32(4, 2);
    data.setUint32(8, 0x0100000c);
    data.setUint32(12, 0);
    data.setUint64(16, 72);
    data.setUint64(24, 12);
    data.setUint32(40, 0x01000007);
    data.setUint32(44, 0);
    data.setUint64(48, 84);
    data.setUint64(56, 12);
    final slices = machOSliceRanges(bytes);
    expect(slices, hasLength(2));
    expect((slices.first.start, slices.first.end), (72, 84));
    expect((slices.last.start, slices.last.end), (84, 96));
    expect(arm64SliceRange(bytes), (72, 84));
  });

  test('AC-046-8 rejects a slice beyond the file', () {
    final bytes = Uint8List(40);
    final data = ByteData.sublistView(bytes);
    data.setUint32(0, 0xcafebabe);
    data.setUint32(4, 1);
    data.setUint32(8, 0x0100000c);
    data.setUint32(16, 32);
    data.setUint32(20, 20);
    expect(machOSliceRanges(bytes), isEmpty);
    expect(arm64SliceRange(bytes), isNull);
  });

  test('AC-046-8 reads thin device and simulator load commands', () {
    Uint8List thin(int platform, int fileType) {
      final bytes = Uint8List(56);
      final data = ByteData.sublistView(bytes);
      data.setUint32(0, 0xfeedfacf, Endian.little);
      data.setUint32(4, 0x0100000c, Endian.little);
      data.setUint32(12, fileType, Endian.little);
      data.setUint32(16, 1, Endian.little);
      data.setUint32(20, 24, Endian.little);
      data.setUint32(32, 0x32, Endian.little);
      data.setUint32(36, 24, Endian.little);
      data.setUint32(40, platform, Endian.little);
      return bytes;
    }

    final device = machOFileInfo(thin(2, 6))!;
    expect(device.platform, 'ios');
    expect(device.dynamic, isTrue);
    final simulator = machOFileInfo(thin(7, 1))!;
    expect(simulator.platform, 'ios-simulator');
    expect(simulator.dynamic, isFalse);
    expect(machOFileInfo(Uint8List(12)), isNull);
  });

  test('AC-046-8 reads a Mach-O object after archive symbol table', () {
    final object = Uint8List(56);
    final data = ByteData.sublistView(object);
    data.setUint32(0, 0xfeedfacf, Endian.little);
    data.setUint32(4, 0x0100000c, Endian.little);
    data.setUint32(12, 1, Endian.little);
    data.setUint32(16, 1, Endian.little);
    data.setUint32(20, 24, Endian.little);
    data.setUint32(32, 0x32, Endian.little);
    data.setUint32(36, 24, Endian.little);
    data.setUint32(40, 7, Endian.little);
    List<int> member(String name, List<int> content) => [
      ...ascii.encode(name.padRight(16)),
      ...ascii.encode('0'.padRight(12)),
      ...ascii.encode('0'.padRight(6)),
      ...ascii.encode('0'.padRight(6)),
      ...ascii.encode('100644'.padRight(8)),
      ...ascii.encode('${content.length}'.padRight(10)),
      0x60,
      0x0a,
      ...content,
      if (content.length.isOdd) 0x0a,
    ];
    final archive = Uint8List.fromList([
      ...ascii.encode('!<arch>\n'),
      ...member('__.SYMDEF/', [0, 0]),
      ...member('file.o/', object),
    ]);
    final info = machOArchiveMemberInfo(archive)!;
    expect(info.platform, 'ios-simulator');
    expect(info.dynamic, isFalse);
  });

  test('AC-046-11 finds bitcode only in dynamic Mach-O', () {
    Uint8List fixture(int type) {
      final bytes = Uint8List(104);
      final data = ByteData.sublistView(bytes);
      data.setUint32(0, 0xfeedfacf, Endian.little);
      data.setUint32(4, 0x0100000c, Endian.little);
      data.setUint32(12, type, Endian.little);
      data.setUint32(16, 1, Endian.little);
      data.setUint32(20, 72, Endian.little);
      data.setUint32(32, 0x19, Endian.little);
      data.setUint32(36, 72, Endian.little);
      bytes.setRange(40, 46, ascii.encode('__LLVM'));
      return bytes;
    }

    expect(dynamicMachOHasBitcode(fixture(6)), isTrue);
    expect(dynamicMachOHasBitcode(fixture(1)), isFalse);
  });
}
