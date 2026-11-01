// studio: 004 — ported from xtool-org/AssetKit (MIT, see
// packages/studio_ext/THIRD_PARTY_NOTICES.md): Schema/Contents.swift,
// Rendition/Rendition.swift, CAR/KeyFormat.swift, CAR/RenditionKey.swift.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/assets/asset_byte_writer.dart';

/// Asset catalog idioms with their CoreUI 970 rendition-key values.
@internal
enum AssetIdiom {
  universal(0, 'universal'),
  iphone(1, 'iphone'),
  ipad(2, 'ipad'),
  tv(3, 'tv'),
  car(4, 'car'),
  watch(5, 'watch'),
  marketing(6, 'ios-marketing'),
  mac(7, 'mac');

  const AssetIdiom(this.code, this.json);

  final int code;
  final String json;

  static AssetIdiom? parse(Object? value) {
    for (final idiom in values) {
      if (idiom.json == value) return idiom;
    }
    return null;
  }

  /// Idioms an iPhone/iPad app bundle uses at runtime.
  static const runtime = {universal, iphone, ipad};
}

@internal
enum AssetScale {
  x1(1),
  x2(2),
  x3(3);

  const AssetScale(this.factor);

  final int factor;

  static AssetScale? parse(Object? value) => switch (value) {
    '1x' => x1,
    '2x' => x2,
    '3x' => x3,
    _ => null,
  };
}

/// Display gamut; the value is CoreUI's per-rendition colour space id.
@internal
enum AssetGamut {
  srgb(1),
  displayP3(2);

  const AssetGamut(this.colorSpaceId);

  final int colorSpaceId;
}

/// Which CoreUI category a bitmap belongs to: `(85, 220)` app icons for
/// SpringBoard, `(85, 181)` images for `UIImage(named:)`.
@internal
enum BitmapKind { appIcon, image }

@internal
sealed class RenditionBody {
  const RenditionBody();
}

/// Decoded pixels, BGRA with premultiplied alpha, `width * 4` bytes a row.
@internal
final class BitmapBody extends RenditionBody {
  const BitmapBody({
    required this.width,
    required this.height,
    required this.pixelsBgra,
    required this.colorSpaceId,
    required this.kind,
    required this.renditionName,
  });

  final int width;
  final int height;
  final Uint8List pixelsBgra;
  final int colorSpaceId;
  final BitmapKind kind;

  /// The source file name; actool stores it in the CSI name field.
  final String renditionName;
}

@internal
final class ColorBody extends RenditionBody {
  const ColorBody({
    required this.red,
    required this.green,
    required this.blue,
    required this.alpha,
    required this.colorSpaceId,
  });

  final double red;
  final double green;
  final double blue;
  final double alpha;
  final int colorSpaceId;
}

/// A JPEG kept verbatim (DWAR envelope); CoreUI decodes it at draw time.
@internal
final class JpegBody extends RenditionBody {
  const JpegBody({
    required this.width,
    required this.height,
    required this.source,
    required this.renditionName,
  });

  final int width;
  final int height;
  final Uint8List source;
  final String renditionName;
}

@internal
final class Rendition {
  const Rendition({
    required this.name,
    required this.idiom,
    required this.body,
    this.scale,
    this.dark = false,
  });

  /// The asset name (`AppIcon`, `LaunchImage`, `Folder/Name`, …).
  final String name;
  final AssetIdiom idiom;
  final AssetScale? scale;

  /// The `luminosity: dark` variant.
  final bool dark;
  final RenditionBody body;
}

/// `kThemeRenditionAttribute` ids for CoreUI 970 (StorageVersion 17).
@internal
abstract final class AttributeIds {
  static const element = 1;
  static const part = 2;
  static const appearance = 7;
  static const dimension2 = 9;
  static const scale = 12;
  static const localization = 13;
  static const idiom = 15;
  static const subtype = 16;
  static const identifier = 17;

  /// KEYFORMAT order; rendition keys pack one `u16` per slot in this order.
  static const keyFormat = [
    appearance,
    localization,
    scale,
    idiom,
    subtype,
    dimension2,
    identifier,
    element,
    part,
  ];
}

/// The asset's `NameIdentifier`: CRC32 (IEEE) of the UTF-8 name, low 16
/// bits. It only has to agree between this catalog's own trees.
@internal
abstract final class AssetNameHash {
  static int of(String name) => getCrc32(utf8.encode(name)) & 0xffff;
}

/// Packed 18-byte rendition key (9 little-endian `u16`s, KEYFORMAT order).
@internal
@immutable
final class RenditionKey {
  const RenditionKey({
    this.appearance = 0,
    this.localization = 0,
    this.scale = 0,
    this.idiom = 0,
    this.subtype = 0,
    this.dimension2 = 0,
    this.identifier = 0,
    this.element = 0,
    this.part = 0,
  });

  factory RenditionKey.of(Rendition rendition) {
    final identifier = AssetNameHash.of(rendition.name);
    final appearance = rendition.dark ? 1 : 0;
    final scale = rendition.scale?.factor ?? 0;
    final idiom = rendition.idiom.code;
    return switch (rendition.body) {
      BitmapBody(kind: BitmapKind.appIcon) => RenditionKey(
        appearance: appearance,
        scale: scale,
        idiom: idiom,
        // The app icon "Icon Index" slot; one logical icon per set.
        dimension2: 1,
        identifier: identifier,
        element: elementBitmap,
        part: partAppIcon,
      ),
      BitmapBody() || JpegBody() => RenditionKey(
        appearance: appearance,
        scale: scale,
        idiom: idiom,
        identifier: identifier,
        element: elementBitmap,
        part: partImage,
      ),
      ColorBody() => RenditionKey(
        appearance: appearance,
        scale: scale,
        idiom: idiom,
        identifier: identifier,
      ),
    };
  }

  static const elementBitmap = 85;
  static const partAppIcon = 220;
  static const partImage = 181;

  final int appearance;
  final int localization;
  final int scale;
  final int idiom;
  final int subtype;
  final int dimension2;
  final int identifier;
  final int element;
  final int part;

  List<int> get slots => [
    appearance,
    localization,
    scale,
    idiom,
    subtype,
    dimension2,
    identifier,
    element,
    part,
  ];

  Uint8List encode() {
    final writer = AssetByteWriter();
    for (final slot in slots) {
      writer.u16le(slot);
    }
    return writer.toBytes();
  }

  static RenditionKey? decode(List<int> bytes) {
    if (bytes.length != 18) return null;
    int u16(int offset) => bytes[offset] | bytes[offset + 1] << 8;
    return RenditionKey(
      appearance: u16(0),
      localization: u16(2),
      scale: u16(4),
      idiom: u16(6),
      subtype: u16(8),
      dimension2: u16(10),
      identifier: u16(12),
      element: u16(14),
      part: u16(16),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RenditionKey &&
      other.slots.indexed.every((slot) => slot.$2 == slots[slot.$1]);

  @override
  int get hashCode => Object.hashAll(slots);
}
