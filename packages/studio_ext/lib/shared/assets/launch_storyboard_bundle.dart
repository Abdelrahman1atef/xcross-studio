// studio: 032 — a real launch storyboard for the app bundle.
//
// `UILaunchScreen` drew a square logo stretched over the whole screen on an
// iPhone X from TestFlight (every open, also after a restart, 2026-11-08, build
// 1.0.12 (1), although the compiled launch image was already screen-shaped).
// Xcode's own apps do not use that path: they ship `LaunchScreen.storyboardc`
// and name it in `UILaunchStoryboardName`. This writes the same compiled
// storyboard without a Mac, and the logo as loose PNGs under a name of its own,
// so the launch screen does not depend on how Apple slices `Assets.car`.
import 'dart:typed_data';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/assets/asset_catalog_compiler.dart';
import 'package:studio_ext/shared/assets/launch_storyboard.dart';
import 'package:studio_ext/src/shared/assets/catalog_loader.dart';
import 'package:studio_ext/src/shared/assets/rendition.dart';
import 'package:studio_ext/src/shared/launch_storyboard/launch_storyboard_compiler.dart';

/// What goes into the app bundle for a compiled launch storyboard.
@immutable
final class LaunchStoryboardBundle {
  const LaunchStoryboardBundle({
    required this.storyboardFiles,
    required this.logoFiles,
  });

  /// Files inside `<Name>.storyboardc`, by file name.
  final Map<String, Uint8List> storyboardFiles;

  /// The logo as loose PNGs (`XCrossLaunchLogo@2x.png`, …) for the bundle root.
  final List<AssetLooseFile> logoFiles;
}

abstract final class LaunchStoryboardBundler {
  /// The image name the compiled storyboard loads. It is not the catalog's
  /// name on purpose: `UIImage(named:)` prefers the catalog, and the point is
  /// to leave the catalog out of the launch screen.
  static const logoName = 'XCrossLaunchLogo';

  /// Compiles the storyboard [spec] describes, or returns null when it needs
  /// something a storyboard of this kind cannot hold (several views, a
  /// full-screen image, a colour that differs in dark mode or is Display P3).
  /// [reason] says why when null.
  static LaunchStoryboardBundle? build({
    required HostFileSystemInterface fileSystem,
    required p.Context paths,
    required List<String> catalogs,
    required LaunchScreenSpec spec,
    void Function(String reason)? reason,
  }) {
    void no(String why) => reason?.call(why);
    if (spec.approximations.isNotEmpty) {
      no('it has ${spec.approximations.join(', ')}');
      return null;
    }
    if (spec.backgroundImageName != null) {
      no('it has a full-screen image');
      return null;
    }
    final loaded = CatalogLoader(fileSystem, paths).load(catalogs, []);

    final color = _background(spec, loaded, no);
    if (color == null) return null;

    String? image;
    final logos = <AssetLooseFile>[];
    final wanted = spec.imageName;
    if (wanted != null) {
      final set = loaded.imageSets.where((s) => s.name == wanted).firstOrNull;
      if (set == null) {
        no('the image "$wanted" is not in the asset catalog');
        return null;
      }
      for (final entry in set.images) {
        if (entry.dark ||
            paths.extension(entry.filename).toLowerCase() != '.png') {
          continue;
        }
        final file = fileSystem.file(entry.path);
        if (!file.existsSync()) continue;
        final bytes = file.readAsBytesSync();
        if (!_isPng(bytes)) continue;
        final name = _looseName(entry);
        if (name != null && logos.every((logo) => logo.name != name)) {
          logos.add(AssetLooseFile(name, bytes));
        }
      }
      if (logos.isEmpty) {
        no('the image "$wanted" has no PNG files');
        return null;
      }
      image = logoName;
    }

    final compiled = LaunchStoryboardCompiler.compile(
      StoryboardSpec(
        background: color,
        imageName: image,
        imageContentMode: spec.imageContentMode,
      ),
    );
    if (compiled == null) {
      no('its image view uses ${spec.imageContentMode}');
      return null;
    }
    return LaunchStoryboardBundle(
      storyboardFiles: compiled.files,
      logoFiles: logos,
    );
  }

  /// `XCrossLaunchLogo[@2x][~ipad].png` for one image of the set.
  static String? _looseName(CatalogImage entry) {
    final scale = entry.scale ?? AssetScale.x1;
    final suffix = switch (entry.idiom) {
      AssetIdiom.universal || AssetIdiom.iphone => '',
      AssetIdiom.ipad => '~ipad',
      _ => null,
    };
    if (suffix == null) return null;
    final at = scale == AssetScale.x1 ? '' : '@${scale.factor}x';
    return '$logoName$at$suffix.png';
  }

  static bool _isPng(Uint8List bytes) =>
      bytes.length > 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47;

  /// The one colour the storyboard paints, as sRGB, or null when it cannot be
  /// a plain colour (dark mode shows another, Display P3).
  static StoryboardColor? _background(
    LaunchScreenSpec spec,
    LoadedCatalog loaded,
    void Function(String) no,
  ) {
    final name = spec.backgroundColorName;
    if (name != null) {
      final colors = loaded.colorSets
          .where((set) => set.name == name)
          .firstOrNull
          ?.colors;
      if (colors == null || colors.isEmpty) {
        no('the colour "$name" is not in the asset catalog');
        return null;
      }
      final light = colors.where((c) => !c.dark).firstOrNull ?? colors.first;
      final dark = colors.where((c) => c.dark).firstOrNull;
      if (light.gamut == AssetGamut.displayP3 ||
          (dark != null &&
              (dark.red != light.red ||
                  dark.green != light.green ||
                  dark.blue != light.blue ||
                  dark.alpha != light.alpha))) {
        no('the colour "$name" is Display P3 or differs in dark mode');
        return null;
      }
      return StoryboardColor(
        red: light.red,
        green: light.green,
        blue: light.blue,
        alpha: light.alpha,
      );
    }
    final inline = spec.background ?? LaunchStoryboard.white;
    final dark = inline.dark;
    if (inline.displayP3 ||
        (dark != null &&
            (dark.red != inline.red ||
                dark.green != inline.green ||
                dark.blue != inline.blue))) {
      no('its background differs in dark mode or is Display P3');
      return null;
    }
    return StoryboardColor(
      red: inline.red,
      green: inline.green,
      blue: inline.blue,
      alpha: inline.alpha,
    );
  }
}
