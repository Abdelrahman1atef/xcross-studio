import 'dart:typed_data';

import 'package:meta/meta.dart';

/// One architecture slice of a (possibly universal) Mach-O file.
@internal
final class MachOSlice {
  const MachOSlice({
    required this.architecture,
    required this.offset,
    required this.size,
    required this.codeSignatureOffset,
    required this.codeSignatureSize,
  });

  /// Name per research R4, e.g. `arm64`, or `cpu:<type>/<subtype>`.
  final String architecture;

  /// Slice start within the file (0 for thin files).
  final int offset;

  /// Slice length in bytes.
  final int size;

  /// Absolute file offset of the code signature, if `LC_CODE_SIGNATURE`
  /// exists.
  final int? codeSignatureOffset;

  /// Code signature length in bytes, if present.
  final int? codeSignatureSize;

  bool get hasCodeSignature => codeSignatureOffset != null;
}

/// The slices of a Mach-O file.
@internal
final class MachOInfo {
  const MachOInfo(this.slices);

  final List<MachOSlice> slices;

  List<String> get architectures => [for (final s in slices) s.architecture];

  /// The first arm64-family slice, else the first slice.
  MachOSlice get preferredSlice => slices.firstWhere(
    (s) => s.architecture == 'arm64' || s.architecture == 'arm64e',
    orElse: () => slices.first,
  );
}

const _mhMagic = 0xfeedface;
const _mhMagic64 = 0xfeedfacf;
const _mhCigam = 0xcefaedfe;
const _mhCigam64 = 0xcffaedfe;
const _fatMagic = 0xcafebabe;
const _fatMagic64 = 0xcafebabf;
const _fatCigam = 0xbebafeca;
const _fatCigam64 = 0xbfbafeca;
const _lcCodeSignature = 0x1d;
const _maxFatArchs = 32;

/// Whether [head] (at least 4 bytes) starts with any Mach-O or fat magic.
@internal
bool hasMachOMagic(Uint8List head) {
  if (head.length < 4) return false;
  final data = ByteData.sublistView(head);
  final big = data.getUint32(0);
  final little = data.getUint32(0, Endian.little);
  return {_fatMagic, _fatMagic64, _fatCigam, _fatCigam64}.contains(big) ||
      {_mhMagic, _mhMagic64, _mhCigam, _mhCigam64}.contains(little);
}

/// Parses the slices of a thin or fat Mach-O file (research R4).
///
/// Throws [FormatException] for unknown magic or truncated structures.
@internal
MachOInfo readMachO(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  _require(bytes.length >= 4, 'truncated Mach-O header');
  final big = data.getUint32(0);
  if (big == _fatMagic ||
      big == _fatMagic64 ||
      big == _fatCigam ||
      big == _fatCigam64) {
    return MachOInfo(_readFat(bytes, data, big));
  }
  return MachOInfo([_readThin(bytes, data, 0, bytes.length)]);
}

List<MachOSlice> _readFat(Uint8List bytes, ByteData data, int magic) {
  final endian = magic == _fatMagic || magic == _fatMagic64
      ? Endian.big
      : Endian.little;
  final wide = magic == _fatMagic64 || magic == _fatCigam64;
  _require(bytes.length >= 8, 'truncated fat header');
  final count = data.getUint32(4, endian);
  _require(count > 0 && count <= _maxFatArchs, 'invalid fat arch count');
  final entrySize = wide ? 32 : 20;
  _require(bytes.length >= 8 + count * entrySize, 'truncated fat header');
  final slices = <MachOSlice>[];
  for (var i = 0; i < count; i++) {
    final base = 8 + i * entrySize;
    final offset = wide
        ? data.getUint64(base + 8, endian)
        : data.getUint32(base + 8, endian);
    final size = wide
        ? data.getUint64(base + 16, endian)
        : data.getUint32(base + 12, endian);
    _require(
      offset >= 0 && size > 0 && offset + size <= bytes.length,
      'truncated fat slice',
    );
    slices.add(_readThin(bytes, data, offset, size));
  }
  return slices;
}

MachOSlice _readThin(Uint8List bytes, ByteData data, int offset, int size) {
  _require(size >= 28 && offset + 28 <= bytes.length, 'truncated Mach-O');
  final raw = data.getUint32(offset, Endian.little);
  final Endian endian;
  final bool is64;
  switch (raw) {
    case _mhMagic:
      endian = Endian.little;
      is64 = false;
    case _mhMagic64:
      endian = Endian.little;
      is64 = true;
    case _mhCigam:
      endian = Endian.big;
      is64 = false;
    case _mhCigam64:
      endian = Endian.big;
      is64 = true;
    default:
      throw const FormatException('not a Mach-O file');
  }
  final headerSize = is64 ? 32 : 28;
  _require(size >= headerSize, 'truncated Mach-O header');
  final cpuType = data.getInt32(offset + 4, endian);
  final cpuSubtype = data.getInt32(offset + 8, endian);
  final commandCount = data.getUint32(offset + 16, endian);
  final commandsSize = data.getUint32(offset + 20, endian);
  final commandsEnd = offset + headerSize + commandsSize;
  _require(
    commandsEnd <= offset + size && commandsEnd <= bytes.length,
    'truncated load commands',
  );

  int? signatureOffset;
  int? signatureSize;
  var cursor = offset + headerSize;
  for (var i = 0; i < commandCount; i++) {
    _require(cursor + 8 <= commandsEnd, 'truncated load commands');
    final command = data.getUint32(cursor, endian);
    final commandSize = data.getUint32(cursor + 4, endian);
    _require(
      commandSize >= 8 && cursor + commandSize <= commandsEnd,
      'invalid load command size',
    );
    if (command == _lcCodeSignature) {
      _require(commandSize >= 16, 'invalid LC_CODE_SIGNATURE');
      final dataOffset = data.getUint32(cursor + 8, endian);
      final dataSize = data.getUint32(cursor + 12, endian);
      _require(
        dataOffset + dataSize <= size &&
            offset + dataOffset + dataSize <= bytes.length,
        'truncated code signature',
      );
      signatureOffset = offset + dataOffset;
      signatureSize = dataSize;
    }
    cursor += commandSize;
  }

  return MachOSlice(
    architecture: architectureName(cpuType, cpuSubtype),
    offset: offset,
    size: size,
    codeSignatureOffset: signatureOffset,
    codeSignatureSize: signatureSize,
  );
}

/// Architecture name for a Mach-O cputype/cpusubtype pair (research R4).
@internal
String architectureName(int cpuType, int cpuSubtype) {
  final subtype = cpuSubtype & 0x00ffffff;
  switch (cpuType) {
    case 0x0100000c:
      return subtype == 2 ? 'arm64e' : 'arm64';
    case 12:
      if (subtype == 9) return 'armv7';
      if (subtype == 11) return 'armv7s';
    case 0x01000007:
      return 'x86_64';
    case 7:
      return 'i386';
  }
  return 'cpu:$cpuType/$subtype';
}

void _require(bool condition, String message) {
  if (!condition) throw FormatException(message);
}
