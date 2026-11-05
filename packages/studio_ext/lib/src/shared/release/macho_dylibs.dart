// studio: 018 — the dynamic libraries a binary loads, for the Swift runtime
// ones an App Store IPA has to carry in SwiftSupport (AC-018-16).
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/inspect/macho_reader.dart';

/// One `LC_LOAD_DYLIB`, `LC_LOAD_WEAK_DYLIB` or `LC_REEXPORT_DYLIB`.
@internal
@immutable
final class MachODylib {
  const MachODylib(this.path, {required this.weak});

  /// As recorded: `@rpath/libswiftCore.dylib`, `/usr/lib/swift/libswiftCore.dylib`.
  final String path;
  final bool weak;

  String get fileName => path.split('/').last;

  /// A Swift runtime library (`libswiftCore.dylib`, `libswift_Concurrency.dylib`).
  bool get isSwiftRuntime =>
      fileName.startsWith('libswift') && fileName.endsWith('.dylib');

  /// Found through the app's own rpath, so it has to ship with the app (or be
  /// in the OS at one of the rpaths): the ones App Store Connect expects in
  /// SwiftSupport.
  bool get viaRpath => path.startsWith('@rpath/');

  /// The libraries the arm64 slice of [bytes] (a thin or fat Mach-O) loads;
  /// empty when it cannot be parsed.
  static List<MachODylib> read(Uint8List bytes) {
    final MachOInfo info;
    try {
      info = readMachO(bytes);
    } on FormatException {
      return const [];
    }
    if (info.slices.isEmpty) return const [];
    final slice = info.preferredSlice;
    if (slice.offset < 0 || slice.offset + 32 > bytes.length) return const [];
    final data = ByteData.sublistView(bytes, slice.offset);
    final Endian endian;
    final bool is64;
    switch (data.getUint32(0, Endian.little)) {
      case 0xfeedfacf:
        (endian, is64) = (Endian.little, true);
      case 0xfeedface:
        (endian, is64) = (Endian.little, false);
      case 0xcffaedfe:
        (endian, is64) = (Endian.big, true);
      case 0xcefaedfe:
        (endian, is64) = (Endian.big, false);
      default:
        return const [];
    }
    final count = data.getUint32(16, endian);
    var offset = is64 ? 32 : 28;
    final libraries = <MachODylib>[];
    for (var i = 0; i < count; i++) {
      if (offset + 8 > data.lengthInBytes) break;
      final command = data.getUint32(offset, endian);
      final size = data.getUint32(offset + 4, endian);
      if (size < 8 || offset + size > data.lengthInBytes) break;
      if ((command == _lcLoadDylib ||
              command == _lcLoadWeakDylib ||
              command == _lcReexportDylib) &&
          size > 24) {
        final nameOffset = data.getUint32(offset + 8, endian);
        if (nameOffset >= 12 && nameOffset < size) {
          final raw = data.buffer.asUint8List(
            data.offsetInBytes + offset + nameOffset,
            size - nameOffset,
          );
          final end = raw.indexOf(0);
          libraries.add(
            MachODylib(
              String.fromCharCodes(end < 0 ? raw : raw.sublist(0, end)),
              weak: command == _lcLoadWeakDylib,
            ),
          );
        }
      }
      offset += size;
    }
    return libraries;
  }

  static const _lcLoadDylib = 0xc;
  static const _lcLoadWeakDylib = 0x80000018;
  static const _lcReexportDylib = 0x8000001f;
}
