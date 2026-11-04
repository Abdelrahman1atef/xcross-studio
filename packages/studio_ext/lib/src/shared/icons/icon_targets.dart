// studio: 024 — the files each platform needs from one icon design
// (specs/024-icon-splash-studio, User Stories 3 and 4).
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/assets/png_codec.dart';
import 'package:studio_ext/src/shared/icons/icon_check.dart';
import 'package:studio_ext/src/shared/icons/icon_composer.dart';
import 'package:studio_ext/src/shared/icons/icon_design.dart';
import 'package:studio_ext/src/shared/icons/icon_slots.dart';

/// `--targets`.
@internal
enum IconTarget {
  ios('ios', 'ios'),
  android('android', 'android'),
  notification('notification', 'android'),
  web('web', 'web'),
  macos('macos', 'macos'),
  watchos('watchos', null),
  tvos('tvos', null),
  androidTv('android-tv', null),
  playBanner('play-banner', null);

  const IconTarget(this.option, this.projectFolder);

  final String option;

  /// The project folder it is written under; null for targets a Flutter
  /// project has no place for, which need `--output` or `--zip`.
  final String? projectFolder;

  static IconTarget? parse(String text) {
    for (final value in values) {
      if (value.option == text) return value;
    }
    return null;
  }

  /// `all`: what a Flutter project has folders for.
  static const projectTargets = [ios, android, web, macos];
}

/// What [IconTargets.build] made for one target: files by project-relative
/// path, with `/` separators.
@internal
@immutable
final class IconTargetFiles {
  const IconTargetFiles(this.files, {this.issues = const []});

  final Map<String, Uint8List> files;
  final List<IconIssue> issues;
}

/// Android's density folders, with the launcher, adaptive and notification
/// pixel sizes at each.
const _androidDensities = [
  ('mdpi', 48, 108, 24),
  ('hdpi', 72, 162, 36),
  ('xhdpi', 96, 216, 48),
  ('xxhdpi', 144, 324, 72),
  ('xxxhdpi', 192, 432, 96),
];

const _androidRes = 'android/app/src/main/res';

/// The share of an adaptive layer visible through the launcher's mask
/// (72 dp of 108 dp), where the logo box goes.
const _adaptiveViewport = 72 / 108;

/// The safe circle of a maskable web icon.
const _maskableViewport = 0.8;

@internal
abstract final class IconTargets {
  static const defaultName = 'ic_launcher';

  /// The files of [target]. `ios` is the set of feature 023.
  static IconTargetFiles build(
    IconTarget target,
    IconComposer composer, {
    String name = defaultName,
    IconShape shape = IconShape.squircle,
    bool themed = false,
  }) => switch (target) {
    IconTarget.ios => _ios(composer),
    IconTarget.android => _android(composer, name, shape, themed: themed),
    IconTarget.notification => _notification(composer, name),
    IconTarget.web => _web(composer),
    IconTarget.macos => _macos(composer),
    IconTarget.watchos => _watchos(composer),
    IconTarget.tvos => _tvos(composer),
    IconTarget.androidTv => IconTargetFiles({
      'android-tv/drawable-xhdpi/banner.png': PngEncoder.encodeOpaque(
        composer.draw(320, 180),
      ),
    }),
    IconTarget.playBanner => IconTargetFiles({
      'play-store/feature-graphic.png': PngEncoder.encodeOpaque(
        composer.draw(1024, 500),
      ),
    }),
  };

  static const _iosSet = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';

  static IconTargetFiles _ios(IconComposer composer) {
    final master = composer.draw(1024, 1024);
    return IconTargetFiles({
      for (final MapEntry(key: file, value: pixels) in IconSlots.files.entries)
        '$_iosSet/$file': PngEncoder.encodeOpaque(
          pixels == 1024 ? master : master.resized(pixels, pixels),
        ),
      '$_iosSet/Contents.json': _utf8(IconSlots.contentsJson()),
    });
  }

  static IconTargetFiles _android(
    IconComposer composer,
    String name,
    IconShape shape, {
    required bool themed,
  }) {
    final files = <String, Uint8List>{};
    final issues = <IconIssue>[];
    // Drawn large once, then reduced: the masks stay smooth at every size.
    const large = 384;
    final full = composer.draw(large, large);
    final launcher = _masked(full, shape);
    final round = _masked(full, IconShape.circle);
    final foreground = composer.foreground(
      432,
      432,
      viewport: _adaptiveViewport,
    );
    final background = composer.backgroundLayer(432, 432);
    final monochrome = themed
        ? composer.silhouette(432, 432, viewport: _adaptiveViewport)
        : null;
    if (themed && monochrome == null) {
      issues.add(
        const IconIssue(
          'icons.notification_no_shape',
          'warning',
          'The logo has no transparency and no one-colour border, so no '
              'themed icon was written.',
          hint: 'Use a logo on a transparent background.',
        ),
      );
    }
    for (final (density, launcherSize, layerSize, _) in _androidDensities) {
      final folder = '$_androidRes/mipmap-$density';
      files['$folder/$name.png'] = PngEncoder.encode(
        launcher.resized(launcherSize, launcherSize),
      );
      files['$folder/${name}_round.png'] = PngEncoder.encode(
        round.resized(launcherSize, launcherSize),
      );
      files['$folder/${name}_foreground.png'] = PngEncoder.encode(
        foreground.resized(layerSize, layerSize),
      );
      files['$folder/${name}_background.png'] = PngEncoder.encodeOpaque(
        background.resized(layerSize, layerSize),
      );
      if (monochrome != null) {
        files['$folder/${name}_monochrome.png'] = PngEncoder.encode(
          monochrome.resized(layerSize, layerSize),
        );
      }
    }
    final xml = _adaptiveXml(name, monochrome: monochrome != null);
    files['$_androidRes/mipmap-anydpi-v26/$name.xml'] = _utf8(xml);
    files['$_androidRes/mipmap-anydpi-v26/${name}_round.xml'] = _utf8(xml);
    files['android/app/src/main/$name-playstore.png'] = PngEncoder.encodeOpaque(
      composer.draw(512, 512),
    );
    return IconTargetFiles(files, issues: issues);
  }

  /// The drawable a launcher mask cuts into any shape.
  @visibleForTesting
  static String adaptiveXml(String name, {required bool monochrome}) =>
      _adaptiveXml(name, monochrome: monochrome);

  static String _adaptiveXml(String name, {required bool monochrome}) =>
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
      '    <background android:drawable="@mipmap/${name}_background"/>\n'
      '    <foreground android:drawable="@mipmap/${name}_foreground"/>\n'
      '${monochrome ? '    <monochrome android:drawable="@mipmap/${name}_monochrome"/>\n' : ''}'
      '</adaptive-icon>\n';

  /// `ic_stat_<name>`, or `ic_stat_notification` for the default launcher
  /// name, which would read `ic_stat_ic_launcher`.
  @visibleForTesting
  static String notificationName(String name) =>
      'ic_stat_${name == defaultName ? 'notification' : name}';

  static IconTargetFiles _notification(IconComposer composer, String name) {
    final shape = composer.silhouette(192, 192);
    if (shape == null) {
      return const IconTargetFiles(
        {},
        issues: [
          IconIssue(
            'icons.notification_no_shape',
            'error',
            'The logo has no transparency and no one-colour border, so a '
                'notification icon would be a white square.',
            hint: 'Use a logo on a transparent background.',
          ),
        ],
      );
    }
    final stat = notificationName(name);
    return IconTargetFiles({
      for (final (density, _, _, size) in _androidDensities)
        '$_androidRes/drawable-$density/$stat.png': PngEncoder.encode(
          shape.resized(size, size),
        ),
    });
  }

  /// The icon list a web manifest should have.
  @visibleForTesting
  static List<Map<String, String>> manifestIcons() => [
    for (final size in const [192, 512])
      {
        'src': 'icons/Icon-$size.png',
        'sizes': '${size}x$size',
        'type': 'image/png',
      },
    for (final size in const [192, 512])
      {
        'src': 'icons/Icon-maskable-$size.png',
        'sizes': '${size}x$size',
        'type': 'image/png',
        'purpose': 'maskable',
      },
  ];

  /// [manifest] (the text of `web/manifest.json`) with its icons replaced,
  /// other fields and their order kept; null when it is not a JSON object.
  static String? updatedManifest(String manifest) {
    final Object? decoded;
    try {
      decoded = jsonDecode(manifest);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final updated = {...decoded, 'icons': manifestIcons()};
    return '${const JsonEncoder.withIndent('    ').convert(updated)}\n';
  }

  static IconTargetFiles _web(IconComposer composer) {
    final full = composer.draw(512, 512);
    final maskable = composer.draw(512, 512, viewport: _maskableViewport);
    return IconTargetFiles({
      'web/favicon.png': PngEncoder.encodeOpaque(full.resized(32, 32)),
      'web/favicon.ico': icoFile(
        [
          PngEncoder.encode(full.resized(16, 16)),
          PngEncoder.encode(full.resized(32, 32)),
          PngEncoder.encode(full.resized(48, 48)),
        ],
        const [16, 32, 48],
      ),
      'web/icons/Icon-192.png': PngEncoder.encodeOpaque(full.resized(192, 192)),
      'web/icons/Icon-512.png': PngEncoder.encodeOpaque(full),
      'web/icons/Icon-maskable-192.png': PngEncoder.encodeOpaque(
        maskable.resized(192, 192),
      ),
      'web/icons/Icon-maskable-512.png': PngEncoder.encodeOpaque(maskable),
    });
  }

  /// An `.ico` holding PNG images, which every current browser reads.
  @visibleForTesting
  static Uint8List icoFile(List<Uint8List> pngs, List<int> sizes) {
    final length = pngs.fold<int>(22 - 16, (sum, png) => sum + 16 + png.length);
    final out = Uint8List(length);
    final data = ByteData.sublistView(out)
      ..setUint16(2, 1, Endian.little)
      ..setUint16(4, pngs.length, Endian.little);
    var offset = 6 + 16 * pngs.length;
    for (var i = 0; i < pngs.length; i++) {
      final entry = 6 + 16 * i;
      out[entry] = sizes[i] % 256;
      out[entry + 1] = sizes[i] % 256;
      data
        ..setUint16(entry + 4, 1, Endian.little)
        ..setUint16(entry + 6, 32, Endian.little)
        ..setUint32(entry + 8, pngs[i].length, Endian.little)
        ..setUint32(entry + 12, offset, Endian.little);
      out.setRange(offset, offset + pngs[i].length, pngs[i]);
      offset += pngs[i].length;
    }
    return out;
  }

  static const _macSet = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';

  static IconTargetFiles _macos(IconComposer composer) {
    // Apple's grid: an 824 px rounded square centred in 1024 px, transparent
    // around it (macOS does not mask icons itself).
    const content = 824;
    const canvas = 1024;
    final body = _masked(
      composer.draw(content, content),
      IconShape.squircle,
      inset: 0,
      exponent: 5,
    );
    final master = RgbaImage(canvas, canvas, Uint8List(canvas * canvas * 4));
    const margin = (canvas - content) ~/ 2;
    for (var y = 0; y < content; y++) {
      final to = ((margin + y) * canvas + margin) * 4;
      master.rgba.setRange(to, to + content * 4, body.rgba, y * content * 4);
    }
    final images = <Map<String, String>>[];
    for (final (points, scale) in const [
      (16, 1),
      (16, 2),
      (32, 1),
      (32, 2),
      (128, 1),
      (128, 2),
      (256, 1),
      (256, 2),
      (512, 1),
      (512, 2),
    ]) {
      images.add({
        'size': '${points}x$points',
        'idiom': 'mac',
        'filename': 'app_icon_${points * scale}.png',
        'scale': '${scale}x',
      });
    }
    return IconTargetFiles({
      for (final pixels in const [16, 32, 64, 128, 256, 512, 1024])
        '$_macSet/app_icon_$pixels.png': PngEncoder.encode(
          pixels == canvas ? master : master.resized(pixels, pixels),
        ),
      '$_macSet/Contents.json': _utf8(_contents(images)),
    });
  }

  /// Every case size of Xcode's watchOS icon set.
  static const _watchSlots = [
    ('notificationCenter', '24x24', 2, '38mm', 48),
    ('notificationCenter', '27.5x27.5', 2, '42mm', 55),
    ('companionSettings', '29x29', 2, null, 58),
    ('companionSettings', '29x29', 3, null, 87),
    ('notificationCenter', '33x33', 2, '45mm', 66),
    ('appLauncher', '40x40', 2, '38mm', 80),
    ('appLauncher', '44x44', 2, '40mm', 88),
    ('appLauncher', '46x46', 2, '41mm', 92),
    ('appLauncher', '50x50', 2, '44mm', 100),
    ('appLauncher', '51x51', 2, '45mm', 102),
    ('appLauncher', '54x54', 2, '49mm', 108),
    ('quickLook', '86x86', 2, '38mm', 172),
    ('quickLook', '98x98', 2, '42mm', 196),
    ('quickLook', '108x108', 2, '44mm', 216),
    ('quickLook', '117x117', 2, '45mm', 234),
    ('quickLook', '129x129', 2, '49mm', 258),
  ];

  static IconTargetFiles _watchos(IconComposer composer) {
    const folder = 'watchos/AppIcon.appiconset';
    final master = composer.draw(1024, 1024);
    final files = <String, Uint8List>{};
    final images = <Map<String, String>>[];
    for (final (role, size, scale, subtype, pixels) in _watchSlots) {
      final file = 'watch-$pixels.png';
      files.putIfAbsent(
        '$folder/$file',
        () => PngEncoder.encodeOpaque(master.resized(pixels, pixels)),
      );
      images.add({
        'size': size,
        'idiom': 'watch',
        'filename': file,
        'scale': '${scale}x',
        'role': role,
        'subtype': ?subtype,
      });
    }
    files['$folder/watch-1024.png'] = PngEncoder.encodeOpaque(master);
    images.add({
      'size': '1024x1024',
      'idiom': 'watch-marketing',
      'filename': 'watch-1024.png',
      'scale': '1x',
    });
    files['$folder/Contents.json'] = _utf8(_contents(images));
    return IconTargetFiles(files);
  }

  /// Flat images of tvOS's sizes; Xcode layers them in its image stacks.
  static const _tvSlots = [
    ('AppIcon-400x240', 400, 240),
    ('AppIcon-800x480', 800, 480),
    ('AppStore-1280x768', 1280, 768),
    ('TopShelf-1920x720', 1920, 720),
    ('TopShelf-3840x1440', 3840, 1440),
    ('TopShelfWide-2320x720', 2320, 720),
    ('TopShelfWide-4640x1440', 4640, 1440),
  ];

  static IconTargetFiles _tvos(IconComposer composer) => IconTargetFiles({
    for (final (name, width, height) in _tvSlots)
      'tvos/$name.png': PngEncoder.encodeOpaque(composer.draw(width, height)),
  });

  static String _contents(List<Map<String, String>> images) {
    final body = {
      'images': images,
      'info': {'author': 'xcode', 'version': 1},
    };
    return '${const JsonEncoder.withIndent('  ').convert(body)}\n';
  }

  static Uint8List _utf8(String text) => Uint8List.fromList(utf8.encode(text));

  /// [image] cut to [shape], transparent outside, sampled four times per
  /// pixel so its edge is smooth. [inset] is the margin kept around it, a
  /// share of the half side; [exponent] overrides a squircle's curve.
  static RgbaImage _masked(
    RgbaImage image,
    IconShape shape, {
    double inset = 1 / 24,
    double exponent = 4,
  }) {
    final out = Uint8List.fromList(image.rgba);
    final width = image.width;
    final height = image.height;
    const offsets = [0.25, 0.75];
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var hits = 0;
        for (final oy in offsets) {
          for (final ox in offsets) {
            final u = 2 * (x + ox) / width - 1;
            final v = 2 * (y + oy) / height - 1;
            if (_inside(shape, u, v, inset, exponent)) hits++;
          }
        }
        final i = (y * width + x) * 4 + 3;
        out[i] = (out[i] * hits) ~/ 4;
      }
    }
    return RgbaImage(width, height, out);
  }

  static bool _inside(
    IconShape shape,
    double u,
    double v,
    double inset,
    double exponent,
  ) {
    final reach = 1 - inset;
    final x = u.abs() / reach;
    final y = v.abs() / reach;
    if (x > 1 || y > 1) return false;
    switch (shape) {
      case IconShape.circle:
        return x * x + y * y <= 1;
      case IconShape.squircle:
        return math.pow(x, exponent) + math.pow(y, exponent) <= 1;
      case IconShape.square:
        const corner = 0.18;
        final dx = x - (1 - corner);
        final dy = y - (1 - corner);
        if (dx <= 0 || dy <= 0) return true;
        return dx * dx + dy * dy <= corner * corner;
    }
  }
}
