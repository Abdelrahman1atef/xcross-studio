// studio: 004 — ported from xtool-org/AssetKit (MIT, see
// packages/studio_ext/THIRD_PARTY_NOTICES.md): AppIcon/AppIconPlist.swift.
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/assets/catalog_loader.dart';
import 'package:studio_ext/src/shared/assets/png_codec.dart';
import 'package:studio_ext/src/shared/assets/rendition.dart';

/// One app icon size ready for the bundle: its `CFBundleIconFiles` name,
/// the loose PNG written next to `Assets.car`, and its pixels.
@internal
final class AppIconFile {
  const AppIconFile({
    required this.idiom,
    required this.pointSize,
    required this.scale,
    required this.outputName,
    required this.looseName,
    required this.png,
    required this.image,
    required this.sourceName,
  });

  final AssetIdiom idiom;
  final double pointSize;
  final AssetScale scale;

  /// `AppIcon60x60`.
  final String outputName;

  /// `AppIcon60x60@2x.png`; iPad files carry actool's `~ipad` suffix.
  final String looseName;
  final Uint8List png;
  final RgbaImage image;

  /// The source file name, stored in the CSI name field.
  final String sourceName;
}

/// The icon slots an iOS app needs, generated from a single 1024-point
/// universal icon (Xcode 14+ "single size" app icons).
@internal
abstract final class AppIconSizes {
  static const iphone = [
    (20.0, AssetScale.x2),
    (20.0, AssetScale.x3),
    (29.0, AssetScale.x2),
    (29.0, AssetScale.x3),
    (40.0, AssetScale.x2),
    (40.0, AssetScale.x3),
    (60.0, AssetScale.x2),
    (60.0, AssetScale.x3),
  ];
  static const ipad = [
    (20.0, AssetScale.x1),
    (20.0, AssetScale.x2),
    (29.0, AssetScale.x1),
    (29.0, AssetScale.x2),
    (40.0, AssetScale.x1),
    (40.0, AssetScale.x2),
    (76.0, AssetScale.x1),
    (76.0, AssetScale.x2),
    (83.5, AssetScale.x2),
  ];
}

/// Info.plist keys for an app icon set, as AssetKit (and actool) emit
/// them: `CFBundleIconName`, `CFBundleIcons`, `CFBundleIcons~ipad` and the
/// flat `CFBundleIconFiles` fallback.
@internal
abstract final class AppIconPlist {
  static Map<String, Object> additions(String name, List<AppIconFile> files) {
    final iphone = <String>[];
    final ipad = <String>[];
    for (final file in files) {
      final list = file.idiom == AssetIdiom.ipad ? ipad : iphone;
      if (!list.contains(file.outputName)) list.add(file.outputName);
    }
    final fallback = {...iphone, ...ipad}.toList()..sort();
    return {
      'CFBundleIconName': name,
      'CFBundleIcons': <String, Object>{
        'CFBundleIconName': name,
        if (iphone.isNotEmpty)
          'CFBundlePrimaryIcon': <String, Object>{
            'CFBundleIconName': name,
            'CFBundleIconFiles': iphone,
          },
      },
      if (ipad.isNotEmpty)
        'CFBundleIcons~ipad': <String, Object>{
          'CFBundleIconName': name,
          'CFBundlePrimaryIcon': <String, Object>{
            'CFBundleIconName': name,
            'CFBundleIconFiles': ipad,
          },
        },
      if (fallback.isNotEmpty) 'CFBundleIconFiles': fallback,
    };
  }

  /// `AppIcon60x60`, `AppIcon83.5x83.5`.
  static String outputName(String name, double pointSize) {
    final size = pointSize == pointSize.roundToDouble()
        ? pointSize.toInt().toString()
        : pointSize.toString();
    return '$name${size}x$size';
  }

  static String looseName(
    String outputName,
    AssetScale scale,
    AssetIdiom idiom,
  ) {
    final suffix = scale == AssetScale.x1 ? '' : '@${scale.factor}x';
    final device = idiom == AssetIdiom.ipad ? '~ipad' : '';
    return '$outputName$suffix$device.png';
  }

  /// The single 1024-point universal image of [set], if that is how the
  /// set is authored.
  static AppIconImage? singleSizeSource(LoadedAppIcon set) {
    final universal = [
      for (final image in set.images)
        if (image.idiom == AssetIdiom.universal &&
            !image.hasAppearance &&
            image.size == 1024)
          image,
    ];
    final slotted = set.images.any(
      (image) =>
          image.idiom == AssetIdiom.iphone || image.idiom == AssetIdiom.ipad,
    );
    return universal.isNotEmpty && !slotted ? universal.first : null;
  }
}
