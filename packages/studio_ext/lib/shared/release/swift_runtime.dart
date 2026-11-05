// studio: 018 — which Swift runtime libraries a build's binaries load, shared
// by the App Store build (which packs them into SwiftSupport) and the release
// check (which looks for them), AC-018-16.
import 'dart:typed_data';

import 'package:studio_ext/src/shared/release/macho_dylibs.dart';

/// A Swift runtime library a binary loads.
final class SwiftRuntimeLibrary {
  const SwiftRuntimeLibrary(
    this.fileName, {
    required this.viaRpath,
    this.weak = false,
  });

  /// `libswiftCore.dylib`.
  final String fileName;

  /// Some binary loads it as `@rpath/…`: the shape that needs a copy in the
  /// app or in SwiftSupport (the others name `/usr/lib/swift` directly).
  final bool viaRpath;

  /// Every binary loads it weakly: it may be absent (`libswiftXPC.dylib` is not
  /// in Xcode's iPhoneOS toolchain), so nothing is demanded of it.
  final bool weak;

  /// SwiftSupport has to hold it.
  bool get required => viaRpath && !weak;
}

/// The Swift runtime libraries loaded by the binaries [binaries], by file name.
/// A library any binary loads through the rpath is reported as `viaRpath`.
Map<String, SwiftRuntimeLibrary> swiftRuntimeLibraries(
  Iterable<Uint8List> binaries,
) {
  final found = <String, SwiftRuntimeLibrary>{};
  for (final bytes in binaries) {
    for (final library in MachODylib.read(bytes)) {
      if (!library.isSwiftRuntime) continue;
      final before = found[library.fileName];
      found[library.fileName] = SwiftRuntimeLibrary(
        library.fileName,
        viaRpath: library.viaRpath || (before?.viaRpath ?? false),
        weak: library.weak && (before?.weak ?? true),
      );
    }
  }
  return found;
}
