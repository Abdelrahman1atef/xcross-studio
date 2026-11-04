// Feature 024: what the studio's controls hold, turned into `xcross` options.
// The drawing is the CLI's; these only name the choices.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'clipart_set.dart';

enum IconSourceType { image, text, clipart }

/// A colour written as `#RRGGBB`.
bool isHexColor(String text) =>
    RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(text.trim());

/// Padding or margin on four sides, with one value while [split] is off.
class FourSides {
  FourSides(double value) : values = [value, value, value, value];

  /// Top, right, bottom, left.
  final List<double> values;
  bool split = false;

  /// `12` or `10,14,18,14`.
  String get text {
    String number(double value) => value == value.roundToDouble()
        ? '${value.round()}'
        : value.toStringAsFixed(1);
    final uniform = values.every((value) => value == values.first);
    return uniform ? number(values.first) : values.map(number).join(',');
  }

  void set(int side, double value) {
    if (split) {
      values[side] = value;
    } else {
      values.fillRange(0, 4, value);
    }
  }

  /// Reads `text`; anything else leaves the values as they are.
  void parse(String? text) {
    if (text == null) return;
    final parts = text
        .split(',')
        .map((t) => double.tryParse(t.trim()))
        .toList();
    if (parts.any((value) => value == null)) return;
    if (parts.length == 1) {
      values.fillRange(0, 4, parts.single!);
    } else if (parts.length == 4) {
      for (var i = 0; i < 4; i++) {
        values[i] = parts[i]!;
      }
      split = !values.every((value) => value == values.first);
    }
  }
}

/// The icon tab's choices.
class IconStudioDesign {
  IconSourceType sourceType = IconSourceType.image;
  String? imagePath;
  String text = 'Aa';
  String? fontFamily;
  bool bold = true;
  bool italic = false;
  Clipart? clipart = clipartSet.firstWhere((item) => item.name == 'bolt');
  ClipartStyle clipartStyle = ClipartStyle.filled;

  bool trim = false;
  final FourSides padding = FourSides(15);
  String? foreground;
  String effect = 'none';

  String backgroundType = 'color';

  /// `auto` or `#RRGGBB`.
  String background = 'auto';
  String background2 = '#5E5CE6';
  String background3 = '#FF9F0A';
  String background4 = '#30D158';
  double gradientAngle = 135;
  String? backgroundImage;
  String texture = 'none';

  String badge = '';
  String badgeColor = '#E5484D';

  /// The badge image a saved design names. Its text is not saved: the CLI only
  /// sees the rendered image.
  String? savedBadge;

  String name = 'ic_launcher';
  String shape = 'squircle';
  bool themed = false;

  /// What "Write to project" writes.
  final Set<String> targets = {'ios'};

  /// What only an export can hold.
  final Set<String> exportTargets = {};

  /// Text and clipart have empty space around the drawn shape, always trimmed.
  bool get effectiveTrim => trim || sourceType != IconSourceType.image;

  /// A problem to show instead of drawing, or null.
  String? get invalid {
    if (foreground != null && !isHexColor(foreground!)) {
      return 'Enter the foreground colour as #RRGGBB.';
    }
    if (background != 'auto' && !isHexColor(background)) {
      return 'Enter the background colour as #RRGGBB.';
    }
    if (backgroundType == 'gradient' || backgroundType == 'mesh') {
      if (!isHexColor(background2)) return 'Enter the colours as #RRGGBB.';
    }
    if (backgroundType == 'mesh' &&
        (!isHexColor(background3) || !isHexColor(background4))) {
      return 'Enter the colours as #RRGGBB.';
    }
    if (backgroundType == 'image' && backgroundImage == null) {
      return 'Pick a background image.';
    }
    final top = padding.values[0];
    final right = padding.values[1];
    final bottom = padding.values[2];
    final left = padding.values[3];
    if (left + right >= 100 || top + bottom >= 100) {
      return 'Those margins leave no room for the logo.';
    }
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
      return 'The file name takes lower case letters, digits and _, starting '
          'with a letter.';
    }
    return null;
  }

  /// The options as `xcross icons generate` takes them; [badgeImage] is the
  /// badge rendered to a file.
  Map<String, String> options({String? badgeImage}) => {
    'padding': padding.text,
    'background': background,
    if (backgroundType != 'color') 'background-type': backgroundType,
    if (backgroundType == 'gradient' || backgroundType == 'mesh')
      'background2': background2,
    if (backgroundType == 'mesh') ...{
      'background3': background3,
      'background4': background4,
    },
    if (backgroundType == 'gradient')
      'gradient-angle': gradientAngle.round().toString(),
    if (backgroundType == 'image') 'background-image': ?backgroundImage,
    if (texture != 'none') 'texture': texture,
    'foreground': ?foreground,
    if (effect != 'none') 'effect': effect,
    'badge-image': ?badgeImage,
    if (name != 'ic_launcher') 'name': name,
    if (shape != 'squircle') 'shape': shape,
  };

  List<String> flags() => [if (effectiveTrim) 'trim', if (themed) 'themed'];

  /// One line for `xcross icons preview --serve`.
  Map<String, Object?> previewRequest(String source, {String? badgeImage}) => {
    'source': source,
    ...options(badgeImage: badgeImage),
    if (effectiveTrim) 'trim': true,
  };

  /// Restores what `--save-config` stored in `xcross_assets.json`, with paths
  /// made absolute against [project].
  void restore(Map<String, Object?> saved, String project) {
    String? path(String key) {
      final value = saved[key];
      if (value is! String) return null;
      return p.isAbsolute(value) ? value : p.join(project, value);
    }

    String? text(String key) =>
        saved[key] is String ? saved[key]! as String : null;
    imagePath = path('source') ?? imagePath;
    trim = saved['trim'] == true;
    themed = saved['themed'] == true;
    padding.parse(text('padding'));
    foreground = text('foreground');
    effect = text('effect') ?? effect;
    backgroundType = text('background-type') ?? backgroundType;
    background = text('background') ?? background;
    background2 = text('background2') ?? background2;
    background3 = text('background3') ?? background3;
    background4 = text('background4') ?? background4;
    gradientAngle =
        double.tryParse(text('gradient-angle') ?? '') ?? gradientAngle;
    backgroundImage = path('background-image');
    savedBadge = path('badge-image');
    texture = text('texture') ?? texture;
    name = text('name') ?? name;
    shape = text('shape') ?? shape;
    final savedTargets = text('targets');
    if (savedTargets != null) {
      targets
        ..clear()
        ..addAll(savedTargets.split(',').map((t) => t.trim()));
      exportTargets.addAll(targets.where(_exportOnly.contains));
      targets.removeWhere(_exportOnly.contains);
    }
  }

  static const _exportOnly = {'watchos', 'tvos', 'android-tv', 'play-banner'};
}

/// The splash tab's choices.
class SplashStudioDesign {
  String? logo;
  String? darkLogo;
  String background = '#FFFFFF';

  /// Null: no dark variant.
  String? darkBackground;
  double logoWidth = 120;
  final FourSides padding = FourSides(0);
  final FourSides margin = FourSides(0);
  String? branding;
  String? darkBranding;
  bool ios = true;
  bool android = true;

  String? get invalid {
    if (!isHexColor(background)) {
      return 'Enter the background colour as #RRGGBB.';
    }
    if (darkBackground != null && !isHexColor(darkBackground!)) {
      return 'Enter the dark background colour as #RRGGBB.';
    }
    if (!ios && !android) return 'Choose iOS, Android or both.';
    return null;
  }

  Map<String, String> options() => {
    'background': background,
    'dark-background': ?darkBackground,
    'dark-logo': ?darkLogo,
    'logo-width': logoWidth.round().toString(),
    'padding': padding.text,
    'margin': margin.text,
    'branding': ?branding,
    'dark-branding': ?darkBranding,
    'platforms': [if (ios) 'ios', if (android) 'android'].join(','),
  };

  Map<String, Object?> previewRequest() => {
    'kind': 'splash',
    'source': logo,
    ...options(),
  };

  void restore(Map<String, Object?> saved, String project) {
    String? path(String key) {
      final value = saved[key];
      if (value is! String) return null;
      return p.isAbsolute(value) ? value : p.join(project, value);
    }

    String? text(String key) =>
        saved[key] is String ? saved[key]! as String : null;
    logo = path('source') ?? logo;
    darkLogo = path('dark-logo');
    background = text('background') ?? background;
    darkBackground = text('dark-background');
    logoWidth = double.tryParse(text('logo-width') ?? '') ?? logoWidth;
    padding.parse(text('padding'));
    margin.parse(text('margin'));
    branding = path('branding');
    darkBranding = path('dark-branding');
    final platforms = text('platforms');
    if (platforms != null) {
      ios = platforms.contains('ios');
      android = platforms.contains('android');
    }
  }
}

/// [path], or a copy of it in [project] when it is outside: the saved design
/// names it, so it has to stay with the project for a team to regenerate.
Future<String> keepInProject(
  String project,
  String path, {
  String? name,
}) async {
  if (p.isWithin(project, path)) return path;
  final kept = File(
    p.join(project, '.xcross', 'assets', name ?? p.basename(path)),
  );
  await kept.parent.create(recursive: true);
  await File(path).copy(kept.path);
  return kept.path;
}

/// A section of `xcross_assets.json` in [project], empty when not saved.
Map<String, Object?> savedAssets(String project, String section) {
  final file = File(p.join(project, 'xcross_assets.json'));
  if (!file.existsSync()) return const {};
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map<String, Object?> &&
        decoded[section] is Map<String, Object?>) {
      return decoded[section]! as Map<String, Object?>;
    }
  } on FormatException {
    // The CLI reports a broken file when it is used.
  } on FileSystemException {
    // Unreadable: start from the defaults.
  }
  return const {};
}
