// studio: 004 — ported from xtool-org/AssetKit (MIT, see
// packages/studio_ext/THIRD_PARTY_NOTICES.md): CAR/CARWriter.swift,
// CAR/CARHeader.swift, CAR/CARLayout.swift, CAR/KeyFormat.swift,
// CAR/ExtendedMetadata.swift, CAR/FacetKeys.swift, CAR/AppearanceKeys.swift,
// CAR/BitmapKeys.swift.
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/assets/asset_byte_writer.dart';
import 'package:studio_ext/src/shared/assets/bom_writer.dart';
import 'package:studio_ext/src/shared/assets/csi_writer.dart';
import 'package:studio_ext/src/shared/assets/rendition.dart';

/// Writes an `Assets.car` (CoreUI 970, StorageVersion 17) for [renditions].
///
/// The variables table order is load-bearing (CARHEADER, RENDITIONS,
/// FACETKEYS, APPEARANCEKEYS, KEYFORMAT, EXTENDED_METADATA, BITMAPKEYS):
/// iOS rejects catalogs whose order differs from actool's.
@internal
final class CarWriter {
  CarWriter({
    required this.deploymentTarget,
    required List<Rendition> renditions,
  }) : renditions = _distinct(renditions);

  final String deploymentTarget;

  /// The renditions, first one kept when two share a rendition key.
  final List<Rendition> renditions;

  Uint8List write() {
    final assets = CarAssets.of(renditions);
    final iconSets = IconSets.entries(assets);
    final bom = BomWriter();
    bom.setVariable(
      'CARHEADER',
      bom.addBlock(
        CarHeaderBlock.data(
          renditionCount: renditions.length + iconSets.length,
        ),
      ),
    );

    bom.setVariable(
      'RENDITIONS',
      BomTree.insert(bom, [
        for (final rendition in renditions)
          BomTreeEntry(RenditionKey.of(rendition).encode(), _csi(rendition)),
        ...iconSets,
      ]),
    );

    bom.setVariable(
      'FACETKEYS',
      BomTree.insert(bom, [
        for (final asset in assets)
          BomTreeEntry(
            utf8.encode(asset.name),
            FacetKeys.value(asset.name, asset.kind),
          ),
      ]),
    );

    bom.setVariable(
      'APPEARANCEKEYS',
      BomTree.insert(
        bom,
        AppearanceKeys.entries(dark: renditions.any((r) => r.dark)),
      ),
    );

    bom.setVariable('KEYFORMAT', bom.addBlock(KeyFormatBlock.data()));
    bom.setVariable(
      'EXTENDED_METADATA',
      bom.addBlock(ExtendedMetadataBlock.data(deploymentTarget)),
    );

    final bitmapEntries = [
      for (final asset in assets)
        if (BitmapKeys.descriptor(asset) case final descriptor?)
          BomInlineKeyEntry(AssetNameHash.of(asset.name), descriptor),
    ];
    if (bitmapEntries.isNotEmpty) {
      bom.setVariable(
        'BITMAPKEYS',
        BomTree.insertInlineKey(bom, bitmapEntries),
      );
    }
    return bom.finalize();
  }

  static Uint8List _csi(Rendition rendition) {
    final scaleFactor = (rendition.scale?.factor ?? 1) * 100;
    return switch (rendition.body) {
      final BitmapBody body => CsiWriter.bitmap(body, scaleFactor: scaleFactor),
      final JpegBody body => CsiWriter.jpeg(body, scaleFactor: scaleFactor),
      final ColorBody body => CsiWriter.color(rendition.name, body),
    };
  }

  static List<Rendition> _distinct(List<Rendition> renditions) {
    final seen = <RenditionKey>{};
    return [
      for (final rendition in renditions)
        if (seen.add(RenditionKey.of(rendition))) rendition,
    ];
  }
}

/// The FACETKEYS category of an asset.
@internal
enum FacetKind { appIcon, image, color }

/// One asset (all renditions sharing a name), in name order.
@internal
final class CarAsset {
  const CarAsset(this.name, this.kind, this.renditions);

  final String name;
  final FacetKind kind;
  final List<Rendition> renditions;
}

@internal
abstract final class CarAssets {
  static List<CarAsset> of(List<Rendition> renditions) {
    final grouped = <String, List<Rendition>>{};
    for (final rendition in renditions) {
      grouped.putIfAbsent(rendition.name, () => []).add(rendition);
    }
    final names = grouped.keys.toList()
      ..sort((a, b) => BomTree.compareBytes(utf8.encode(a), utf8.encode(b)));
    return [
      for (final name in names)
        CarAsset(name, _kind(grouped[name]!.first), grouped[name]!),
    ];
  }

  static FacetKind _kind(Rendition rendition) => switch (rendition.body) {
    BitmapBody(kind: BitmapKind.appIcon) => FacetKind.appIcon,
    BitmapBody() || JpegBody() => FacetKind.image,
    ColorBody() => FacetKind.color,
  };
}

/// The `SISM` icon set record of each `AppIcon`, one per idiom, as actool
/// writes them next to the icon images.
@internal
abstract final class IconSets {
  static List<BomTreeEntry> entries(List<CarAsset> assets) {
    final entries = <BomTreeEntry>[];
    for (final asset in assets) {
      if (asset.kind != FacetKind.appIcon) continue;
      // idiom → Icon Index → point size; the indices are unique per size.
      final byIdiom = <AssetIdiom, Map<int, int>>{};
      for (final rendition in asset.renditions) {
        final points = rendition.iconPoints;
        if (points == null || rendition.dark) continue;
        byIdiom.putIfAbsent(rendition.idiom, () => {})[AppIconIndex.of(
          points,
        )] = AppIconIndex.sismPoints(
          points,
        );
      }
      final idioms = byIdiom.keys.toList()
        ..sort((a, b) => a.code.compareTo(b.code));
      for (final idiom in idioms) {
        final key = RenditionKey(
          scale: 1,
          idiom: idiom.code,
          identifier: AssetNameHash.of(asset.name),
          element: RenditionKey.elementBitmap,
          part: RenditionKey.partIconSet,
        );
        entries.add(
          BomTreeEntry(
            key.encode(),
            CsiWriter.iconSet(asset.name, [
              for (final MapEntry(key: index, value: points)
                  in byIdiom[idiom]!.entries)
                (points, index),
            ]),
          ),
        );
      }
    }
    return entries;
  }
}

/// CARHEADER: 436 bytes.
@internal
abstract final class CarHeaderBlock {
  /// `'CTAR'` LE (bytes `R,A,T,C`).
  static const magic = 0x43544152;
  static const mainVersion = '@(#)PROGRAM:CoreUI  PROJECT:CoreUI-970.1';
  static const versionString =
      'xcross-studio asset catalog compiler (AssetKit port, Assets.car v1)';

  static Uint8List data({required int renditionCount}) {
    final writer = AssetByteWriter()
      ..u32le(magic)
      ..u32le(970) // coreuiVersion
      ..u32le(17) // storageVersion
      ..u32le(0) // timestamp
      ..u32le(renditionCount)
      ..padded(mainVersion, 128)
      ..padded(versionString, 256)
      ..zeros(16) // uuid
      ..u32le(0) // associatedChecksum
      ..u32le(2) // schemaVersion
      ..u32le(1) // colorSpaceID
      ..u32le(2); // keySemantics
    assert(writer.length == 436, 'CARHEADER is 436 bytes');
    return writer.toBytes();
  }
}

/// KEYFORMAT: `'kfmt'` LE, version 0, attribute count, attribute ids.
@internal
abstract final class KeyFormatBlock {
  static const magic = 0x6B666D74;

  static Uint8List data() {
    final writer = AssetByteWriter()
      ..u32le(magic)
      ..u32le(0)
      ..u32le(AttributeIds.keyFormat.length);
    for (final attribute in AttributeIds.keyFormat) {
      writer.u32le(attribute);
    }
    return writer.toBytes();
  }
}

/// EXTENDED_METADATA: 1028 bytes; `META` + 252 zeros, then deployment
/// target, platform and authoring tool slots (4 zero bytes + 252-byte
/// string each), then 4 zeros.
@internal
abstract final class ExtendedMetadataBlock {
  static const platform = 'ios';
  static const authoringTool = CarHeaderBlock.versionString;

  static Uint8List data(String deploymentTarget) {
    final writer = AssetByteWriter()
      ..fourCC('META')
      ..zeros(252);
    for (final value in [deploymentTarget, platform, authoringTool]) {
      writer
        ..zeros(4)
        ..padded(value, 252);
    }
    writer.zeros(4);
    assert(writer.length == 1028, 'EXTENDED_METADATA is 1028 bytes');
    return writer.toBytes();
  }
}

/// FACETKEYS value: hot spot `(0, 0)`, attribute count, `(id, value)`
/// pairs.
@internal
abstract final class FacetKeys {
  static Uint8List value(String name, FacetKind kind) {
    final identifier = AssetNameHash.of(name);
    final pairs = switch (kind) {
      FacetKind.appIcon => [
        (AttributeIds.element, RenditionKey.elementBitmap),
        (AttributeIds.part, RenditionKey.partAppIcon),
        (AttributeIds.identifier, identifier),
      ],
      FacetKind.image => [
        (AttributeIds.element, RenditionKey.elementBitmap),
        (AttributeIds.part, RenditionKey.partImage),
        (AttributeIds.identifier, identifier),
      ],
      FacetKind.color => [
        (AttributeIds.element, RenditionKey.elementBitmap),
        (AttributeIds.part, RenditionKey.partColor),
        (AttributeIds.identifier, identifier),
      ],
    };
    final writer = AssetByteWriter()
      ..u16le(0)
      ..u16le(0)
      ..u16le(pairs.length);
    for (final (attribute, value) in pairs) {
      writer
        ..u16le(attribute)
        ..u16le(value);
    }
    return writer.toBytes();
  }
}

/// APPEARANCEKEYS: iOS names; `UIAppearanceAny` (0) always, and
/// `UIAppearanceDark` (1) only when a dark rendition exists.
@internal
abstract final class AppearanceKeys {
  static List<BomTreeEntry> entries({required bool dark}) => [
    BomTreeEntry(utf8.encode('UIAppearanceAny'), _id(0)),
    if (dark) BomTreeEntry(utf8.encode('UIAppearanceDark'), _id(1)),
  ];

  static Uint8List _id(int id) => (AssetByteWriter()..u16le(id)).toBytes();
}

/// BITMAPKEYS: a 52-byte descriptor per bitmap asset, keyed inline by the
/// asset's `NameIdentifier`. `UIImage(named:)` needs it.
@internal
abstract final class BitmapKeys {
  /// The descriptor for [asset], or `null` for colour-only assets.
  static Uint8List? descriptor(CarAsset asset) {
    if (asset.kind == FacetKind.color) return null;
    final appIcon = asset.kind == FacetKind.appIcon;
    final idioms = {for (final rendition in asset.renditions) rendition.idiom};
    // For an app icon the descriptor lists what exists, as masks: scales
    // (bit n = n×), idioms (bit n = idiom n) and Icon Indices (bit n = index n,
    // bit 0 always). Read from Xcode 26.2 catalogs: 0x0e / 0x46 / 0x0fff for a
    // set with 1×–3×, iPhone, iPad and marketing icons, indices 1 to 11.
    var scaleMask = 0;
    var idiomMask = 0;
    var indexMask = 1;
    final indices = <int>{};
    for (final rendition in asset.renditions) {
      scaleMask |= 1 << (rendition.scale?.factor ?? 0);
      idiomMask |= 1 << rendition.idiom.code;
      final index = AppIconIndex.of(rendition.iconPoints);
      indices.add(index);
      if (index < 32) indexMask |= 1 << index;
    }
    final writer = AssetByteWriter()
      ..u32le(1)
      ..u32le(0)
      ..u32le(0x28)
      ..u32le(9)
      ..u32le(0xFFFFFFFF)
      ..u32le(1)
      ..u32le(appIcon ? scaleMask : 0x04) // asset-kind marker
      ..u32le(appIcon ? idiomMask : idioms.length)
      ..u16le(1)
      ..u16le(appIcon && indices.length > 1 ? 1 : 0)
      ..u32le(appIcon ? indexMask : 1)
      ..u32le(0xFFFFFFFF)
      ..u32le(0xFFFFFFFF)
      ..u32le(0xFFFFFFFF);
    assert(writer.length == 52, 'BITMAPKEYS descriptor is 52 bytes');
    return writer.toBytes();
  }
}
