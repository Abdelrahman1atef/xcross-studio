// studio: 004 — compile `.xcassets` into `Assets.car` without Xcode, a
// pure-Dart port of xtool-org/AssetKit (MIT, see THIRD_PARTY_NOTICES.md).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/assets/app_icon_plist.dart';
import 'package:studio_ext/src/shared/assets/car_writer.dart';
import 'package:studio_ext/src/shared/assets/catalog_loader.dart';
import 'package:studio_ext/src/shared/assets/png_codec.dart';
import 'package:studio_ext/src/shared/assets/rendition.dart';

/// Why an asset was left out of the compiled catalog.
enum AssetCatalogIssueKind {
  /// A kind of asset or source this compiler does not handle (SVG/PDF
  /// images, data sets, system colour references, alternate app icons, …).
  unsupported,

  /// A broken asset: missing file, bad `Contents.json`, unreadable image.
  invalid,
}

/// One asset left out, with a message for the user.
final class AssetCatalogIssue {
  const AssetCatalogIssue(this.kind, this.subject, this.message);

  final AssetCatalogIssueKind kind;

  /// The asset or file the issue is about (deduplication key).
  final String subject;
  final String message;

  @override
  String toString() => '${kind.name}: $message';
}

/// A file for the app bundle root, next to `Assets.car`.
final class AssetLooseFile {
  const AssetLooseFile(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

/// A colour added to the catalog as a named colour set (components 0…1).
@immutable
final class CatalogColor {
  const CatalogColor({
    required this.red,
    required this.green,
    required this.blue,
    this.alpha = 1,
    this.displayP3 = false,
    this.dark,
  });

  final double red;
  final double green;
  final double blue;
  final double alpha;
  final bool displayP3;

  /// The dark-appearance variant, if it differs.
  final CatalogColor? dark;

  @override
  bool operator ==(Object other) =>
      other is CatalogColor &&
      other.red == red &&
      other.green == green &&
      other.blue == blue &&
      other.alpha == alpha &&
      other.displayP3 == displayP3 &&
      other.dark == dark;

  @override
  int get hashCode => Object.hash(red, green, blue, alpha, displayP3, dark);

  @override
  String toString() =>
      'CatalogColor($red, $green, $blue, $alpha'
      '${displayP3 ? ', P3' : ''}${dark == null ? '' : ', dark: $dark'})';
}

/// The launch image and the background it is drawn over.
@immutable
final class LaunchBackdrop {
  const LaunchBackdrop({
    required this.imageName,
    required this.color,
    this.colorName,
  });

  final String imageName;

  /// The colour set holding the background; wins over [color] when it exists.
  final String? colorName;

  /// The background when [colorName] is not a colour set.
  final CatalogColor color;
}

/// The compiled catalog and what the app bundle needs alongside it.
final class CompiledAssetCatalog {
  const CompiledAssetCatalog({
    required this.car,
    required this.infoPlistAdditions,
    required this.looseFiles,
    required this.imageNames,
    required this.colorNames,
    required this.appIconName,
    required this.renditionCount,
    required this.issues,
  });

  /// The `Assets.car` bytes.
  final Uint8List car;

  /// App icon keys to merge into Info.plist (empty without an app icon).
  final Map<String, Object> infoPlistAdditions;

  /// Loose icon PNGs for SpringBoard's fallback path.
  final List<AssetLooseFile> looseFiles;

  /// Image sets with at least one compiled image.
  final Set<String> imageNames;

  /// Colour sets (catalog and added) with at least one colour.
  final Set<String> colorNames;
  final String? appIconName;
  final int renditionCount;
  final List<AssetCatalogIssue> issues;
}

/// Compiles asset catalogs into one `Assets.car` (CoreUI 970 format).
///
/// Supported: `.imageset` (PNG, JPEG; 1x/2x/3x; dark appearance;
/// display-P3), `.colorset` and the app's `.appiconset` (including Xcode's
/// single 1024-point icon, scaled down to the slots iOS uses). Anything
/// else is skipped and reported in [CompiledAssetCatalog.issues]; the
/// compile itself only throws for programming errors.
final class AssetCatalogCompiler {
  AssetCatalogCompiler({
    required this.fileSystem,
    required this.paths,
    this.appIconName = 'AppIcon',
  });

  final HostFileSystemInterface fileSystem;
  final p.Context paths;

  /// The app icon set to compile (`ASSETCATALOG_COMPILER_APPICON_NAME`).
  final String appIconName;

  /// Compiles [catalogs] into one `Assets.car`.
  ///
  /// The image of [launch] is drawn over its background, in light and dark. On
  /// a real iPhone a launch image's transparent pixels showed as a black square
  /// (seen 2026-11-04), so it holds none: over the same colour, the result
  /// looks transparent. The files in the project keep their transparency.
  ///
  /// The names stay stable on purpose. iOS can keep an app's older catalog
  /// until the phone restarts (an iPhone drew a removed image into a fresh
  /// install's launch snapshots, seen 2026-11-04), and a name that catalog lacks
  /// comes out blank, which is worse on a user's phone than an older logo.
  CompiledAssetCatalog compile(
    List<String> catalogs, {
    required String deploymentTarget,
    Map<String, CatalogColor> extraColors = const {},
    LaunchBackdrop? launch,
  }) {
    final issues = <AssetCatalogIssue>[];
    final loaded = CatalogLoader(fileSystem, paths).load(catalogs, issues);
    final renditions = <Rendition>[];

    final colorSetNames = {
      for (final set in loaded.colorSets)
        if (set.colors.isNotEmpty) set.name,
    };
    final launchColor = launch == null ? null : _launchColor(launch, loaded);
    final imageNames = <String>{};
    for (final set in loaded.imageSets) {
      // A name has one kind in the catalog, and images are written first, so
      // this set would hide the colour from UIColor(named:) (a splash tool's
      // leftover `LaunchBackground.imageset` did).
      if (colorSetNames.contains(set.name)) {
        issues.add(
          AssetCatalogIssue(
            AssetCatalogIssueKind.invalid,
            set.name,
            'Image set "${set.name}" has the same name as a colour set, so it '
            'is not in the app. Delete ${set.name}.imageset or rename it.',
          ),
        );
        continue;
      }
      final over = set.name == launch?.imageName ? launchColor : null;
      final compiled = <CatalogImage>[];
      for (final image in set.images) {
        final rendition = _image(
          set.name,
          image,
          issues,
          over: image.dark ? over?.dark ?? over : over,
        );
        if (rendition == null) continue;
        renditions.add(rendition);
        compiled.add(image);
      }
      // A set with no dark image still needs one over a different dark colour.
      if (over?.dark case final dark?
          when !_sameColor(over!, dark) && !set.images.any((i) => i.dark)) {
        for (final image in compiled) {
          if (paths.extension(image.filename).toLowerCase() != '.png') continue;
          final rendition = _image(
            set.name,
            image,
            issues,
            over: dark,
            dark: true,
          );
          if (rendition != null) renditions.add(rendition);
        }
      }
      if (compiled.isNotEmpty) imageNames.add(set.name);
    }

    final colorNames = <String>{};
    for (final set in loaded.colorSets) {
      for (final color in set.colors) {
        renditions.add(
          Rendition(
            name: set.name,
            idiom: color.idiom,
            dark: color.dark,
            body: ColorBody(
              red: color.red,
              green: color.green,
              blue: color.blue,
              alpha: color.alpha,
              colorSpaceId: color.gamut.colorSpaceId,
            ),
          ),
        );
        colorNames.add(set.name);
      }
    }
    for (final MapEntry(key: name, value: color) in extraColors.entries) {
      if (colorNames.contains(name) || imageNames.contains(name)) continue;
      renditions.add(_color(name, color, dark: false));
      if (color.dark case final dark?) {
        renditions.add(_color(name, dark, dark: true));
      }
      colorNames.add(name);
    }

    final appIcon = _pickAppIcon(loaded.appIcons, issues);
    var files = const <AppIconFile>[];
    if (appIcon != null) {
      final decode = _iconDecoder(appIcon, issues);
      files = _appIconFiles(appIcon, decode, issues);
      // One rendition per (idiom, scale) fits the rendition key; keep the
      // largest size, the one the home screen asks for.
      final bySize = [...files]
        ..sort((a, b) => b.pointSize.compareTo(a.pointSize));
      for (final file in bySize) {
        renditions.add(
          Rendition(
            name: appIcon.name,
            idiom: file.idiom,
            scale: file.scale,
            body: BitmapBody(
              width: file.image.width,
              height: file.image.height,
              pixelsBgra: file.image.toPremultipliedBgra(),
              colorSpaceId: AssetGamut.srgb.colorSpaceId,
              kind: BitmapKind.appIcon,
              renditionName: file.sourceName,
            ),
          ),
        );
      }
      if (_appStoreIcon(appIcon, decode, issues) case final icon?) {
        renditions.add(icon);
      }
    }

    final writer = CarWriter(
      deploymentTarget: deploymentTarget,
      renditions: renditions,
    );
    final looseNames = <String>{};
    return CompiledAssetCatalog(
      car: writer.write(),
      infoPlistAdditions: files.isEmpty
          ? const {}
          : AppIconPlist.additions(appIcon!.name, files),
      looseFiles: [
        for (final file in files)
          if (looseNames.add(file.looseName))
            AssetLooseFile(file.looseName, file.png),
      ],
      imageNames: imageNames,
      colorNames: colorNames,
      appIconName: files.isEmpty ? null : appIcon!.name,
      renditionCount: writer.renditions.length,
      issues: issues,
    );
  }

  /// The single colour of image set [imageName] (every PNG one colour, the
  /// same at all scales), with its dark variant; `null` otherwise. Used to
  /// turn a full-screen launch background image into a colour.
  CatalogColor? uniformImageColor(List<String> catalogs, String imageName) {
    final loaded = CatalogLoader(fileSystem, paths).load(catalogs, []);
    final set = loaded.imageSets.where((set) => set.name == imageName);
    if (set.isEmpty) return null;
    (int, int, int, int)? light;
    (int, int, int, int)? dark;
    for (final image in set.first.images) {
      if (paths.extension(image.filename).toLowerCase() != '.png') return null;
      final file = fileSystem.file(image.path);
      if (!file.existsSync()) return null;
      final (int, int, int, int)? color;
      try {
        color = PngDecoder.decode(file.readAsBytesSync()).uniformColor;
      } on FormatException {
        return null;
      }
      if (color == null) return null;
      final seen = image.dark ? dark : light;
      if (seen != null && seen != color) return null;
      if (image.dark) {
        dark = color;
      } else {
        light = color;
      }
    }
    CatalogColor of((int, int, int, int) c, {CatalogColor? dark}) =>
        CatalogColor(
          red: c.$1 / 255,
          green: c.$2 / 255,
          blue: c.$3 / 255,
          alpha: c.$4 / 255,
          dark: dark,
        );
    final darkColor = dark == null ? null : of(dark);
    return light == null ? darkColor : of(light, dark: darkColor);
  }

  Rendition _color(String name, CatalogColor color, {required bool dark}) =>
      Rendition(
        name: name,
        idiom: AssetIdiom.universal,
        dark: dark,
        body: ColorBody(
          red: color.red,
          green: color.green,
          blue: color.blue,
          alpha: color.alpha,
          colorSpaceId: color.displayP3
              ? AssetGamut.displayP3.colorSpaceId
              : AssetGamut.srgb.colorSpaceId,
        ),
      );

  /// The background of [launch]: its colour set when there is one.
  CatalogColor _launchColor(LaunchBackdrop launch, LoadedCatalog loaded) {
    final colors = loaded.colorSets
        .where((set) => set.name == launch.colorName)
        .firstOrNull
        ?.colors;
    if (colors == null || colors.isEmpty) return launch.color;
    CatalogColor of(CatalogColorEntry entry, {CatalogColor? dark}) =>
        CatalogColor(
          red: entry.red,
          green: entry.green,
          blue: entry.blue,
          displayP3: entry.gamut == AssetGamut.displayP3,
          dark: dark,
        );
    final dark = colors.where((color) => color.dark).firstOrNull;
    final light = colors.where((color) => !color.dark).firstOrNull;
    final darkColor = dark == null ? null : of(dark);
    return light == null ? darkColor! : of(light, dark: darkColor);
  }

  static bool _sameColor(CatalogColor a, CatalogColor b) =>
      a.red == b.red &&
      a.green == b.green &&
      a.blue == b.blue &&
      a.displayP3 == b.displayP3;

  /// A launch image is drawn on a canvas the shape of the screen, with the
  /// picture in the middle.
  ///
  /// `UILaunchScreen` showed a small square logo stretched over the whole
  /// screen on an iPhone X (TestFlight, 2026-11-05; Apple's forums describe the
  /// same: centred on the first launch, stretched to fill after). A picture
  /// that already has the screen's shape and size looks right whether iOS
  /// centres it or fills the screen with it, and the colour around the logo is
  /// the colour behind it, so no edge shows. The canvas never gets smaller than
  /// the picture.
  static RgbaImage _launchCanvas(
    RgbaImage picture,
    CatalogImage image,
    CatalogColor over,
  ) {
    final (pointsWide, pointsHigh) = image.idiom == AssetIdiom.ipad
        ? launchCanvasPad
        : launchCanvasPhone;
    final scale = (image.scale ?? AssetScale.x1).factor;
    var width = pointsWide * scale;
    var height = pointsHigh * scale;
    if (picture.width > width || picture.height > height) {
      final grow = math.max(picture.width / width, picture.height / height);
      width = math.max(picture.width, (width * grow).ceil());
      height = math.max(picture.height, (height * grow).ceil());
    }
    return picture.centeredOn(
      width,
      height,
      _channel(over.red),
      _channel(over.green),
      _channel(over.blue),
    );
  }

  /// Points of the screens a launch canvas is shaped for: an iPhone X (every
  /// iPhone since shares its 19.5 : 9 shape) and a 9.7-inch iPad.
  static const launchCanvasPhone = (375, 812);
  static const launchCanvasPad = (768, 1024);

  static int _channel(double component) =>
      (component * 255).round().clamp(0, 255);

  /// The rendition of [image], drawn over [over] when given and marked as the
  /// dark variant when [dark] says so (default: as the catalog says).
  Rendition? _image(
    String asset,
    CatalogImage image,
    List<AssetCatalogIssue> issues, {
    CatalogColor? over,
    bool? dark,
  }) {
    final extension = paths.extension(image.filename).toLowerCase();
    void report(AssetCatalogIssueKind kind, String message) => issues.add(
      AssetCatalogIssue(kind, '$asset/${image.filename}', message),
    );
    if (extension != '.png' && extension != '.jpg' && extension != '.jpeg') {
      report(
        AssetCatalogIssueKind.unsupported,
        'Image "$asset" (${image.filename}): $extension sources are not '
        'compiled; export a PNG at 1x/2x/3x.',
      );
      return null;
    }
    final file = fileSystem.file(image.path);
    if (!file.existsSync()) {
      report(
        AssetCatalogIssueKind.invalid,
        'Image "$asset" lists ${image.filename}, which does not exist.',
      );
      return null;
    }
    final bytes = file.readAsBytesSync();
    try {
      if (extension == '.png') {
        final source = PngDecoder.decode(bytes);
        final decoded = over == null
            ? source
            : _launchCanvas(
                source.flattenedOver(
                  _channel(over.red),
                  _channel(over.green),
                  _channel(over.blue),
                ),
                image,
                over,
              );
        // Over a colour, the image takes the colour's space: its edge must not
        // show against the same colour behind it.
        final gamut = over == null
            ? image.gamut
            : over.displayP3
            ? AssetGamut.displayP3
            : AssetGamut.srgb;
        return Rendition(
          name: asset,
          idiom: image.idiom,
          scale: image.scale,
          dark: dark ?? image.dark,
          body: BitmapBody(
            width: decoded.width,
            height: decoded.height,
            pixelsBgra: decoded.toPremultipliedBgra(),
            colorSpaceId: gamut.colorSpaceId,
            kind: BitmapKind.image,
            renditionName: image.filename,
          ),
        );
      }
      final (width, height) = JpegDimensions.read(bytes);
      return Rendition(
        name: asset,
        idiom: image.idiom,
        scale: image.scale,
        dark: image.dark,
        body: JpegBody(
          width: width,
          height: height,
          source: bytes,
          renditionName: image.filename,
        ),
      );
    } on FormatException catch (error) {
      report(
        AssetCatalogIssueKind.invalid,
        'Image "$asset" (${image.filename}) cannot be read: '
        '${error.message}.',
      );
      return null;
    }
  }

  LoadedAppIcon? _pickAppIcon(
    List<LoadedAppIcon> sets,
    List<AssetCatalogIssue> issues,
  ) {
    if (sets.isEmpty) return null;
    final named = sets.where((set) => set.name == appIconName).toList();
    final chosen = named.isNotEmpty
        ? named.first
        : sets.length == 1
        ? sets.single
        : null;
    for (final set in sets) {
      if (identical(set, chosen)) continue;
      issues.add(
        AssetCatalogIssue(
          AssetCatalogIssueKind.unsupported,
          set.name,
          'App icon set "${set.name}" is not the app icon ($appIconName); '
          'alternate app icons are not compiled.',
        ),
      );
    }
    return chosen;
  }

  /// Reads the icons of [set], each once, so a bad file is reported once.
  RgbaImage? Function(AppIconImage) _iconDecoder(
    LoadedAppIcon set,
    List<AssetCatalogIssue> issues,
  ) {
    final decoded = <String, RgbaImage?>{};
    RgbaImage? decode(AppIconImage image) {
      void report(AssetCatalogIssueKind kind, String message) => issues.add(
        AssetCatalogIssue(kind, '${set.name}/${image.filename}', message),
      );
      if (paths.extension(image.filename).toLowerCase() != '.png') {
        report(
          AssetCatalogIssueKind.unsupported,
          'App icon ${image.filename}: only PNG icons are supported.',
        );
        return null;
      }
      final file = fileSystem.file(image.path);
      if (!file.existsSync()) {
        report(
          AssetCatalogIssueKind.invalid,
          'App icon ${image.filename} does not exist.',
        );
        return null;
      }
      try {
        return PngDecoder.decode(file.readAsBytesSync());
      } on FormatException catch (error) {
        report(
          AssetCatalogIssueKind.invalid,
          'App icon ${image.filename} cannot be read: ${error.message}.',
        );
        return null;
      }
    }

    return (image) => decoded.putIfAbsent(image.path, () => decode(image));
  }

  /// The 1024 px icon, in the marketing slot App Store Connect reads it from:
  /// without it the upload fails with error 91111. It never reaches the home
  /// screen, so it has no loose file and no `CFBundleIconFiles` entry.
  ///
  /// A set without one still builds: an app for a device does not need it, and
  /// `release.marketing_icon` stops the release.
  Rendition? _appStoreIcon(
    LoadedAppIcon set,
    RgbaImage? Function(AppIconImage) decode,
    List<AssetCatalogIssue> issues,
  ) {
    final source =
        AppIconPlist.singleSizeSource(set) ??
        set.images
            .where(
              (image) =>
                  image.idiom == AssetIdiom.marketing && !image.hasAppearance,
            )
            .firstOrNull;
    if (source == null) return null;
    final image = decode(source);
    if (image == null) return null;
    if (image.width != 1024 || image.height != 1024) {
      issues.add(
        AssetCatalogIssue(
          AssetCatalogIssueKind.invalid,
          '${set.name}/${source.filename}',
          'App Store icon ${source.filename} is '
              '${image.width}×${image.height}; App Store Connect needs a '
              '1024×1024 PNG, so it is not in the app.',
        ),
      );
      return null;
    }
    return Rendition(
      name: set.name,
      idiom: AssetIdiom.marketing,
      scale: AssetScale.x1,
      body: BitmapBody(
        width: image.width,
        height: image.height,
        pixelsBgra: image.toPremultipliedBgra(),
        colorSpaceId: AssetGamut.srgb.colorSpaceId,
        kind: BitmapKind.appIcon,
        renditionName: source.filename,
        opaque: image.isOpaque,
      ),
    );
  }

  List<AppIconFile> _appIconFiles(
    LoadedAppIcon set,
    RgbaImage? Function(AppIconImage) decode,
    List<AssetCatalogIssue> issues,
  ) {
    final single = AppIconPlist.singleSizeSource(set);
    if (single != null) {
      final source = decode(single);
      if (source == null) return const [];
      return [
        for (final (idiom, slots) in [
          (AssetIdiom.iphone, AppIconSizes.iphone),
          (AssetIdiom.ipad, AppIconSizes.ipad),
        ])
          for (final (points, scale) in slots)
            _generated(set.name, single.filename, source, idiom, points, scale),
      ];
    }

    final files = <AppIconFile>[];
    for (final image in set.images) {
      final size = image.size;
      final scale = image.scale;
      // The App Store icon (ios-marketing) is not used on the device; see
      // [_appStoreIcon] for where it goes.
      if (image.idiom != AssetIdiom.iphone && image.idiom != AssetIdiom.ipad) {
        continue;
      }
      if (image.hasAppearance) continue;
      if (size == null || scale == null) {
        issues.add(
          AssetCatalogIssue(
            AssetCatalogIssueKind.invalid,
            '${set.name}/${image.filename}',
            'App icon ${image.filename} has no valid size or scale in '
                'Contents.json.',
          ),
        );
        continue;
      }
      final decoded = decode(image);
      if (decoded == null) continue;
      final outputName = AppIconPlist.outputName(set.name, size);
      files.add(
        AppIconFile(
          idiom: image.idiom,
          pointSize: size,
          scale: scale,
          outputName: outputName,
          looseName: AppIconPlist.looseName(outputName, scale, image.idiom),
          png: fileSystem.file(image.path).readAsBytesSync(),
          image: decoded,
          sourceName: image.filename,
        ),
      );
    }
    return files;
  }

  AppIconFile _generated(
    String name,
    String sourceName,
    RgbaImage source,
    AssetIdiom idiom,
    double points,
    AssetScale scale,
  ) {
    final pixels = (points * scale.factor).round();
    final image = source.resized(pixels, pixels);
    final outputName = AppIconPlist.outputName(name, points);
    return AppIconFile(
      idiom: idiom,
      pointSize: points,
      scale: scale,
      outputName: outputName,
      looseName: AppIconPlist.looseName(outputName, scale, idiom),
      png: PngEncoder.encode(image),
      image: image,
      sourceName: sourceName,
    );
  }
}
