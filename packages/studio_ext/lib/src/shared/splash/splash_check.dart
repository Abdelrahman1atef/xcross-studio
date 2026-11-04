// studio: 024 — what an app shows at launch, and what is wrong with it
// (specs/024-icon-splash-studio, AC-024-9).
import 'dart:convert';
import 'dart:math' as math;

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/assets/launch_storyboard.dart';
import 'package:studio_ext/src/shared/assets/png_codec.dart';
import 'package:studio_ext/src/shared/icons/icon_analysis.dart';
import 'package:studio_ext/src/shared/icons/icon_check.dart';
import 'package:studio_ext/src/shared/icons/icon_generator.dart';
import 'package:studio_ext/src/shared/splash/splash_design.dart';

/// One platform's launch screen, as far as the files say.
@internal
@immutable
final class SplashPlatform {
  const SplashPlatform({
    this.background,
    this.darkBackground,
    this.logo,
    this.logoSize,
    this.dark = false,
    this.android12 = false,
  });

  final String? background;
  final String? darkBackground;

  /// The image's name.
  final String? logo;

  /// In points (iOS) or dp (Android).
  final (int, int)? logoSize;
  final bool dark;
  final bool android12;

  Map<String, Object?> toJson() => {
    'background': background,
    'darkBackground': darkBackground,
    'logo': logo,
    'logoSize': logoSize == null ? null : [logoSize!.$1, logoSize!.$2],
    'dark': dark,
    'android12': android12,
  };
}

/// The result of `xcross splash check`.
@internal
@immutable
final class SplashReport {
  const SplashReport({required this.issues, this.ios, this.android});

  final SplashPlatform? ios;
  final SplashPlatform? android;
  final List<IconIssue> issues;

  int get errors => issues.where((i) => i.severity == 'error').length;
  int get warnings => issues.where((i) => i.severity == 'warning').length;

  Map<String, Object?> toJson() => {
    'v': 1,
    'type': 'splash_check',
    'ios': ios?.toJson(),
    'android': android?.toJson(),
    'issues': [
      for (final issue in issues)
        {
          'code': issue.code,
          'severity': issue.severity,
          'message': issue.message,
          'hint': issue.hint,
        },
    ],
    'errors': errors,
    'warnings': warnings,
  };

  String render() {
    final out = StringBuffer();
    void platform(String name, SplashPlatform? value) {
      if (value == null) return;
      final size = value.logoSize;
      out.writeln(
        '$name: background ${value.background ?? '?'}'
        '${value.darkBackground == null ? '' : ' (dark ${value.darkBackground})'}, '
        'logo ${value.logo ?? 'none'}'
        '${size == null ? '' : ' ${size.$1}×${size.$2}'}',
      );
    }

    platform('iOS', ios);
    platform('Android', android);
    for (final issue in issues) {
      out
        ..writeln('${issue.severity}: [${issue.code}] ${issue.message}')
        ..writeln('  hint: ${issue.hint}');
    }
    if (issues.isEmpty) out.writeln('No problems found.');
    return out.toString();
  }
}

/// Reads a project's splash files.
@internal
final class SplashCheck {
  const SplashCheck({required this.fileSystem, required this.projectRoot});

  final HostFileSystemInterface fileSystem;
  final String projectRoot;

  /// Below this contrast ratio a logo is hard to see on its background.
  static const minimumContrast = 1.5;

  /// The narrowest supported iPhone, in points.
  static const narrowestScreen = 320;

  /// The shortest supported iPhone, in points.
  static const shortestScreen = 568;

  static const _generateHint =
      'Make one with `xcross splash generate <logo.png>`.';

  SplashReport run() {
    final issues = <IconIssue>[];
    final ios = _exists('ios') ? _ios(issues) : null;
    final android = _exists('android') ? _android(issues) : null;
    final pubspec = fileSystem.file(p.join(projectRoot, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('flutter_native_splash')) {
      issues.add(
        const IconIssue(
          'splash.other_tool',
          'warning',
          'flutter_native_splash is set up in pubspec.yaml; running it again '
              'will overwrite these files.',
          hint: 'Use one of them for the splash.',
        ),
      );
    }
    return SplashReport(ios: ios, android: android, issues: issues);
  }

  bool _exists(String folder) =>
      fileSystem.directory(p.join(projectRoot, folder)).existsSync();

  String _path(String relative) =>
      p.joinAll([projectRoot, ...relative.split('/')]);

  SplashPlatform? _ios(List<IconIssue> issues) {
    final storyboard = fileSystem.file(_path(SplashFiles.iosStoryboard));
    if (!storyboard.existsSync()) {
      issues.add(
        const IconIssue(
          'splash.missing',
          'warning',
          'iOS has no LaunchScreen.storyboard, so the app starts on a blank '
              'screen.',
          hint: _generateHint,
        ),
      );
      return null;
    }
    final LaunchScreenSpec spec;
    try {
      spec = LaunchStoryboard.parse(storyboard.readAsStringSync());
    } on FormatException catch (error) {
      issues.add(
        IconIssue(
          'splash.missing',
          'warning',
          'LaunchScreen.storyboard cannot be read: ${error.message}.',
          hint: _generateHint,
        ),
      );
      return null;
    }

    IconColor? light;
    IconColor? dark;
    final colorName = spec.backgroundColorName;
    if (colorName != null) {
      (light, dark) = _colorSet(colorName);
      final clash = 'ios/Runner/Assets.xcassets/$colorName.imageset';
      if (fileSystem.directory(_path(clash)).existsSync()) {
        issues.add(
          IconIssue(
            'splash.name_clash',
            'warning',
            '$clash has the same name as the background colour, so xcross '
                'leaves it out of the app and Xcode may not find the colour.',
            hint:
                'Delete that folder, or run `xcross splash generate`, which '
                'backs it up and removes it.',
          ),
        );
      }
    } else if (spec.background case final color?) {
      light = (
        (color.red * 255).round(),
        (color.green * 255).round(),
        (color.blue * 255).round(),
      );
    }

    final info = fileSystem.file(_path('ios/Runner/Info.plist'));
    if (info.existsSync() &&
        !info.readAsStringSync().contains('UILaunchStoryboardName')) {
      issues.add(
        const IconIssue(
          'splash.not_referenced',
          'warning',
          'ios/Runner/Info.plist has no UILaunchStoryboardName, so iOS does '
              'not show LaunchScreen.storyboard.',
          hint: 'Add UILaunchStoryboardName with the value LaunchScreen.',
        ),
      );
    }

    final imageName = spec.imageName;
    (int, int)? size;
    var darkImage = false;
    if (imageName != null) {
      final folder = 'ios/Runner/Assets.xcassets/$imageName.imageset';
      final image = _firstImage(_path(folder));
      if (image == null) {
        issues.add(
          IconIssue(
            'splash.logo_missing',
            'error',
            'LaunchScreen.storyboard shows "$imageName", but $folder has no '
                'image.',
            hint: _generateHint,
          ),
        );
      } else {
        final (decoded, scale, hasDark) = image;
        darkImage = hasDark;
        size = (decoded.width ~/ scale, decoded.height ~/ scale);
        _checkLogo(decoded, light, issues, 'iOS');
        // iOS centres the image at its own size, so the ends of a tall one,
        // where branding sits, fall outside a shorter screen (AC-026-22).
        if (size.$2 > shortestScreen) {
          issues.add(
            IconIssue(
              'splash.branding_clipped',
              'warning',
              'The launch image is ${size.$2} points tall, so its top and '
                  'bottom, where branding sits, are cut off on iPhones shorter '
                  'than that. The shortest is $shortestScreen points.',
              hint:
                  'Check it in the studio on the small iPhones, or use a '
                  'smaller logo or no branding on iOS.',
            ),
          );
        }
        if (size.$1 > narrowestScreen) {
          issues.add(
            IconIssue(
              'splash.logo_too_large',
              'warning',
              'The iOS launch image is ${size.$1} points wide; a '
                  '$narrowestScreen-point iPhone cuts it.',
              hint: 'Use a smaller --logo-width.',
            ),
          );
        }
      }
    }
    return SplashPlatform(
      background: light == null ? null : splashHex(light),
      darkBackground: dark == null ? null : splashHex(dark),
      logo: imageName,
      logoSize: size,
      dark: dark != null || darkImage,
    );
  }

  /// The light and dark colours of an asset catalog colour set.
  (IconColor?, IconColor?) _colorSet(String name) {
    final file = fileSystem.file(
      _path('ios/Runner/Assets.xcassets/$name.colorset/Contents.json'),
    );
    if (!file.existsSync()) return (null, null);
    final Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException {
      return (null, null);
    }
    if (decoded is! Map<String, Object?>) return (null, null);
    IconColor? light;
    IconColor? dark;
    for (final entry in (decoded['colors'] as List<Object?>?) ?? const []) {
      if (entry is! Map<String, Object?>) continue;
      final color = _catalogColor(entry['color']);
      final appearances = entry['appearances'];
      final isDark =
          appearances is List &&
          appearances.any((a) => a is Map && a['value'] == 'dark');
      if (isDark) {
        dark = color;
      } else {
        light = color;
      }
    }
    return (light, dark);
  }

  static IconColor? _catalogColor(Object? color) {
    if (color is! Map<String, Object?>) return null;
    final components = color['components'];
    if (components is! Map<String, Object?>) return null;
    int? channel(String key) {
      final text = '${components[key]}';
      if (text.startsWith('0x')) {
        return int.tryParse(text.substring(2), radix: 16);
      }
      final value = double.tryParse(text);
      if (value == null) return null;
      return value > 1 ? value.round() : (value * 255).round();
    }

    final red = channel('red');
    final green = channel('green');
    final blue = channel('blue');
    if (red == null || green == null || blue == null) return null;
    return (red, green, blue);
  }

  /// The largest scale's image of an image set, its scale, and whether it has
  /// a dark variant.
  (RgbaImage, int, bool)? _firstImage(String folder) {
    final file = fileSystem.file(p.join(folder, 'Contents.json'));
    if (!file.existsSync()) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    var hasDark = false;
    (RgbaImage, int)? best;
    for (final entry in (decoded['images'] as List<Object?>?) ?? const []) {
      if (entry is! Map<String, Object?>) continue;
      final name = entry['filename'];
      if (name is! String) continue;
      if (entry['appearances'] != null) {
        hasDark = true;
        continue;
      }
      final scale = int.tryParse('${entry['scale']}'.replaceAll('x', '')) ?? 1;
      if (best != null && best.$2 >= scale) continue;
      final image = fileSystem.file(p.join(folder, name));
      if (!image.existsSync()) continue;
      final bytes = image.readAsBytesSync();
      if (!PngDecoder.isPng(bytes)) continue;
      try {
        best = (PngDecoder.decode(bytes), scale);
      } on FormatException {
        continue;
      }
    }
    return best == null ? null : (best.$1, best.$2, hasDark);
  }

  void _checkLogo(
    RgbaImage logo,
    IconColor? background,
    List<IconIssue> issues,
    String platform,
  ) {
    final mean = _meanVisible(logo);
    if (mean == null) {
      issues.add(
        IconIssue(
          'splash.missing',
          'warning',
          "$platform's launch image is empty (Flutter's placeholder), so the "
              'app starts on a plain colour.',
          hint: _generateHint,
        ),
      );
      return;
    }
    if (background == null) return;
    if (_contrast(mean, background) < minimumContrast) {
      issues.add(
        IconIssue(
          'splash.low_contrast',
          'warning',
          "$platform's logo (${splashHex(mean)}) is hard to see on its "
              'background (${splashHex(background)}).',
          hint: 'Change one of the two colours.',
        ),
      );
    }
  }

  /// The mean colour of the visible pixels; null when there are too few to be
  /// a logo.
  static IconColor? _meanVisible(RgbaImage image) {
    var r = 0;
    var g = 0;
    var b = 0;
    var count = 0;
    for (var i = 0; i < image.rgba.length; i += 4) {
      if (image.rgba[i + 3] < 128) continue;
      r += image.rgba[i];
      g += image.rgba[i + 1];
      b += image.rgba[i + 2];
      count++;
    }
    if (count < 16) return null;
    return (r ~/ count, g ~/ count, b ~/ count);
  }

  static double _contrast(IconColor a, IconColor b) {
    double luminance(IconColor color) {
      double channel(int value) {
        final v = value / 255;
        return v <= 0.03928
            ? v / 12.92
            : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      }

      return 0.2126 * channel(color.$1) +
          0.7152 * channel(color.$2) +
          0.0722 * channel(color.$3);
    }

    final la = luminance(a);
    final lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  static const _res = 'android/app/src/main/res';

  SplashPlatform? _android(List<IconIssue> issues) {
    final launch = fileSystem.file(
      _path('$_res/drawable-v21/launch_background.xml'),
    );
    final fallback = fileSystem.file(
      _path('$_res/drawable/launch_background.xml'),
    );
    final file = launch.existsSync() ? launch : fallback;
    if (!file.existsSync()) {
      issues.add(
        const IconIssue(
          'splash.missing',
          'warning',
          'Android has no launch_background.xml, so the app starts on a blank '
              'screen.',
          hint: _generateHint,
        ),
      );
      return null;
    }
    final xml = file.readAsStringSync();
    final colorText = RegExp(
      'android:color="(#[0-9a-fA-F]{6})"',
    ).firstMatch(xml)?.group(1);
    final background = colorText == null
        ? null
        : IconGenerator.parseColor(colorText);
    final darkFile = fileSystem.file(
      _path('$_res/drawable-night-v21/launch_background.xml'),
    );
    final darkText = darkFile.existsSync()
        ? RegExp(
            'android:color="(#[0-9a-fA-F]{6})"',
          ).firstMatch(darkFile.readAsStringSync())?.group(1)
        : null;

    final styles = fileSystem.file(_path('$_res/values/styles.xml'));
    if (styles.existsSync() &&
        !styles.readAsStringSync().contains('launch_background')) {
      issues.add(
        const IconIssue(
          'splash.not_referenced',
          'warning',
          "android's values/styles.xml LaunchTheme does not use "
              '@drawable/launch_background, so Android does not show it.',
          hint:
              'Set android:windowBackground to @drawable/launch_background in '
              'LaunchTheme.',
        ),
      );
    }

    final logoName = RegExp(
      r'android:src="@drawable/(\w+)"',
    ).firstMatch(xml)?.group(1);
    (int, int)? size;
    if (logoName == null) {
      issues.add(
        const IconIssue(
          'splash.missing',
          'warning',
          'launch_background.xml shows no logo, only a colour.',
          hint: _generateHint,
        ),
      );
    } else {
      final image = _androidImage(logoName);
      if (image == null) {
        issues.add(
          IconIssue(
            'splash.logo_missing',
            'error',
            'launch_background.xml shows "$logoName", but no drawable folder '
                'has that image.',
            hint: _generateHint,
          ),
        );
      } else {
        final (decoded, scale) = image;
        size = (
          (decoded.width / scale).round(),
          (decoded.height / scale).round(),
        );
        _checkLogo(decoded, background, issues, 'Android');
      }
    }

    final styles31 = fileSystem.file(_path('$_res/values-v31/styles.xml'));
    final android12 =
        styles31.existsSync() &&
        styles31.readAsStringSync().contains('windowSplashScreen');
    if (!android12) {
      issues.add(
        const IconIssue(
          'splash.android12_missing',
          'warning',
          'Android 12 and later ignore launch_background.xml and show the app '
              'icon on a plain colour.',
          hint: _generateHint,
        ),
      );
    }
    return SplashPlatform(
      background: colorText,
      darkBackground: darkText,
      logo: logoName,
      logoSize: size,
      dark: darkText != null,
      android12: android12,
    );
  }

  (RgbaImage, double)? _androidImage(String name) {
    for (final (density, scale) in const [
      ('xxxhdpi', 4.0),
      ('xxhdpi', 3.0),
      ('xhdpi', 2.0),
      ('hdpi', 1.5),
      ('mdpi', 1.0),
    ]) {
      final file = fileSystem.file(_path('$_res/drawable-$density/$name.png'));
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      if (!PngDecoder.isPng(bytes)) continue;
      try {
        return (PngDecoder.decode(bytes), scale);
      } on FormatException {
        continue;
      }
    }
    return null;
  }
}
