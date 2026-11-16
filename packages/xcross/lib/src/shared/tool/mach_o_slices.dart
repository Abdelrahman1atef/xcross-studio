import 'dart:convert';
import 'dart:typed_data';
import 'package:meta/meta.dart';

@internal
final class MachOSliceRange {
  const MachOSliceRange(this.cpuType, this.cpuSubtype, this.start, this.end);
  final int cpuType;
  final int cpuSubtype;
  final int start;
  final int end;
}

@internal
final class MachOFileInfo {
  const MachOFileInfo(this.cpuType, this.platform, {required this.dynamic});
  final int cpuType;
  final String? platform;
  final bool dynamic;
}

/// Inspects a thin 64-bit Mach-O's load commands without executing it.
@internal
MachOFileInfo? machOFileInfo(Uint8List bytes) {
  if (bytes.length < 32) return null;
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(0, Endian.little) != 0xfeedfacf) return null;
  final cpu = data.getUint32(4, Endian.little);
  final fileType = data.getUint32(12, Endian.little);
  final commandCount = data.getUint32(16, Endian.little);
  final commandBytes = data.getUint32(20, Endian.little);
  if (commandBytes > bytes.length - 32 || commandCount > commandBytes ~/ 8) {
    return null;
  }
  String? platform;
  var cursor = 32;
  final end = cursor + commandBytes;
  for (var index = 0; index < commandCount; index++) {
    if (cursor + 8 > end) return null;
    final command = data.getUint32(cursor, Endian.little);
    final size = data.getUint32(cursor + 4, Endian.little);
    if (size < 8 || size > end - cursor) return null;
    if (command == 0x32 && size >= 24) {
      platform = switch (data.getUint32(cursor + 8, Endian.little)) {
        2 => 'ios',
        7 => 'ios-simulator',
        _ => null,
      };
    } else if (command == 0x25 && size >= 16) {
      platform ??= 'ios';
    }
    cursor += size;
  }
  return MachOFileInfo(cpu, platform, dynamic: fileType == 6);
}

/// Only an embedded dynamic dylib can carry a `__LLVM` segment into the app.
@internal
bool dynamicMachOHasBitcode(Uint8List bytes) {
  final info = machOFileInfo(bytes);
  if (info == null || !info.dynamic) return false;
  final data = ByteData.sublistView(bytes);
  final count = data.getUint32(16, Endian.little);
  final commandBytes = data.getUint32(20, Endian.little);
  var cursor = 32;
  final end = cursor + commandBytes;
  for (var index = 0; index < count; index++) {
    final command = data.getUint32(cursor, Endian.little);
    final size = data.getUint32(cursor + 4, Endian.little);
    if (command == 0x19 && size >= 72) {
      final name = ascii
          .decode(bytes.sublist(cursor + 8, cursor + 24))
          .split('\x00')
          .first;
      if (name == '__LLVM') return true;
    }
    cursor += size;
    if (cursor > end) return false;
  }
  return false;
}

/// Reads the first Mach-O object in a BSD/Unix static archive.
@internal
MachOFileInfo? machOArchiveMemberInfo(Uint8List bytes) {
  if (bytes.length < 8 || ascii.decode(bytes.sublist(0, 8)) != '!<arch>\n') {
    return null;
  }
  var cursor = 8;
  while (cursor + 60 <= bytes.length) {
    final header = bytes.sublist(cursor, cursor + 60);
    if (header[58] != 0x60 || header[59] != 0x0a) return null;
    final name = ascii.decode(header.sublist(0, 16)).trim();
    final size = int.tryParse(ascii.decode(header.sublist(48, 58)).trim());
    if (size == null || size < 0 || size > bytes.length - cursor - 60) {
      return null;
    }
    var start = cursor + 60;
    final end = start + size;
    if (name.startsWith('#1/')) {
      final nameLength = int.tryParse(name.substring(3));
      if (nameLength == null || nameLength > size) return null;
      start += nameLength;
    }
    if (start < end) {
      final info = machOFileInfo(Uint8List.sublistView(bytes, start, end));
      if (info != null) return info;
    }
    cursor = end + (size.isOdd ? 1 : 0);
  }
  return null;
}

/// Reads validated ranges from 32-bit or 64-bit universal Mach-O headers.
@internal
List<MachOSliceRange> machOSliceRanges(Uint8List bytes, {int? fileLength}) {
  if (bytes.length < 8) return const [];
  final data = ByteData.sublistView(bytes);
  final magic = data.getUint32(0);
  final width = switch (magic) {
    0xcafebabe => 20,
    0xcafebabf => 32,
    _ => 0,
  };
  if (width == 0) return const [];
  final count = data.getUint32(4);
  if (count > (bytes.length - 8) ~/ width) return const [];
  final headerEnd = 8 + count * width;
  final limit = fileLength ?? bytes.length;
  final slices = <MachOSliceRange>[];
  for (var index = 0; index < count; index++) {
    final base = 8 + index * width;
    final offset = width == 20
        ? data.getUint32(base + 8)
        : data.getUint64(base + 8);
    final length = width == 20
        ? data.getUint32(base + 12)
        : data.getUint64(base + 16);
    if (offset < headerEnd || offset > limit || length > limit - offset) {
      return const [];
    }
    slices.add(
      MachOSliceRange(
        data.getUint32(base),
        data.getUint32(base + 4),
        offset,
        offset + length,
      ),
    );
  }
  return slices;
}

@internal
(int, int)? arm64SliceRange(Uint8List bytes, {int? fileLength}) {
  for (final slice in machOSliceRanges(bytes, fileLength: fileLength)) {
    if (slice.cpuType == 0x0100000c) return (slice.start, slice.end);
  }
  return null;
}
