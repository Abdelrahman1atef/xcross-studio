// studio: 018 — the SDK and minimum OS a binary was linked with
// (specs/018-app-store-build, AC-018-10).
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/inspect/macho_reader.dart';

/// `LC_BUILD_VERSION` (or the older `LC_VERSION_MIN_IPHONEOS`) of one slice.
@internal
@immutable
final class MachOBuildVersion {
  const MachOBuildVersion({
    required this.platform,
    required this.minimumOS,
    required this.sdk,
  });

  /// `PLATFORM_*` number: 2 is iOS, 7 the iOS simulator.
  final int platform;

  /// Minimum OS as `major.minor[.patch]`.
  final String minimumOS;

  /// SDK version as `major.minor[.patch]`.
  final String sdk;

  /// The SDK's major version.
  int get sdkMajor => int.parse(sdk.split('.').first);

  /// Reads the arm64 slice of [bytes] (a thin or fat Mach-O), or `null` when
  /// the binary has neither load command or cannot be parsed.
  static MachOBuildVersion? read(Uint8List bytes) {
    final MachOInfo info;
    try {
      info = readMachO(bytes);
    } on FormatException {
      return null;
    }
    if (info.slices.isEmpty) return null;
    final slice = info.preferredSlice;
    if (slice.offset < 0 || slice.offset + 32 > bytes.length) return null;
    final data = ByteData.sublistView(bytes, slice.offset);
    final magicLittle = data.getUint32(0, Endian.little);
    final Endian endian;
    final bool is64;
    switch (magicLittle) {
      case 0xfeedfacf:
        (endian, is64) = (Endian.little, true);
      case 0xfeedface:
        (endian, is64) = (Endian.little, false);
      case 0xcffaedfe:
        (endian, is64) = (Endian.big, true);
      case 0xcefaedfe:
        (endian, is64) = (Endian.big, false);
      default:
        return null;
    }
    final commandCount = data.getUint32(16, endian);
    var offset = is64 ? 32 : 28;
    for (var i = 0; i < commandCount; i++) {
      if (offset + 8 > data.lengthInBytes) return null;
      final command = data.getUint32(offset, endian);
      final size = data.getUint32(offset + 4, endian);
      if (size < 8 || offset + size > data.lengthInBytes) return null;
      if (command == _lcBuildVersion && size >= 24) {
        return MachOBuildVersion(
          platform: data.getUint32(offset + 8, endian),
          minimumOS: format(data.getUint32(offset + 12, endian)),
          sdk: format(data.getUint32(offset + 16, endian)),
        );
      }
      if (command == _lcVersionMinIphoneos && size >= 16) {
        return MachOBuildVersion(
          platform: 2,
          minimumOS: format(data.getUint32(offset + 8, endian)),
          sdk: format(data.getUint32(offset + 12, endian)),
        );
      }
      offset += size;
    }
    return null;
  }

  /// `xxxx.yy.zz` nibble encoding → `x.y[.z]`.
  @visibleForTesting
  static String format(int encoded) {
    final major = encoded >> 16;
    final minor = (encoded >> 8) & 0xff;
    final patch = encoded & 0xff;
    return patch == 0 ? '$major.$minor' : '$major.$minor.$patch';
  }

  static const _lcBuildVersion = 0x32;
  static const _lcVersionMinIphoneos = 0x25;
}
