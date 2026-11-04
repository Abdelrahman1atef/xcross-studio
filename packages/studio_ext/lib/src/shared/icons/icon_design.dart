// studio: 024 — what an icon looks like, independent of where it is written
// (specs/024-icon-splash-studio).
import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/assets/png_codec.dart';
import 'package:studio_ext/src/shared/icons/icon_analysis.dart';

/// `--effect`.
@internal
enum IconEffect {
  none('none'),
  dropShadow('drop-shadow'),
  castShadow('cast-shadow'),
  score('score');

  const IconEffect(this.option);
  final String option;

  static IconEffect? parse(String text) {
    for (final value in values) {
      if (value.option == text) return value;
    }
    return null;
  }
}

/// `--background-type`.
@internal
enum IconBackgroundType {
  color,
  gradient,
  mesh,
  image;

  static IconBackgroundType? parse(String text) {
    for (final value in values) {
      if (value.name == text) return value;
    }
    return null;
  }
}

/// `--texture`.
@internal
enum IconTexture {
  none,
  argyle,
  concentric,
  contour,
  coral,
  fabric,
  halftone,
  maze,
  mosaic,
  polka,
  stipple,
  waves;

  static IconTexture? parse(String text) {
    for (final value in values) {
      if (value.name == text) return value;
    }
    return null;
  }
}

/// `--shape`: the Android launcher icon's outline.
@internal
enum IconShape {
  square,
  squircle,
  circle;

  static IconShape? parse(String text) {
    for (final value in values) {
      if (value.name == text) return value;
    }
    return null;
  }
}

/// Margins around the logo, in percent of the logo box's side.
@internal
@immutable
final class IconPadding {
  const IconPadding(this.top, this.right, this.bottom, this.left);

  const IconPadding.all(double value) : this(value, value, value, value);

  static const none = IconPadding.all(0);
  static const maximum = 45.0;

  final double top;
  final double right;
  final double bottom;
  final double left;

  bool get isUniform => top == right && right == bottom && bottom == left;

  /// `n` or `top,right,bottom,left`; null when malformed, out of range, or
  /// leaving no room for the logo.
  static IconPadding? parse(String text) {
    final parts = text.split(',').map((part) => double.tryParse(part.trim()));
    final values = parts.toList();
    if (values.any((value) => value == null)) return null;
    if (values.length != 1 && values.length != 4) return null;
    final numbers = values.cast<double>();
    if (numbers.any((value) => value < 0 || value > maximum)) return null;
    final padding = numbers.length == 1
        ? IconPadding.all(numbers.single)
        : IconPadding(numbers[0], numbers[1], numbers[2], numbers[3]);
    if (padding.left + padding.right >= 100 ||
        padding.top + padding.bottom >= 100) {
      return null;
    }
    return padding;
  }

  /// `12` or `10,14,18,14`.
  String get text {
    String number(double value) => value == value.roundToDouble()
        ? '${value.round()}'
        : value.toStringAsFixed(1);
    return isUniform
        ? number(top)
        : [top, right, bottom, left].map(number).join(',');
  }
}

/// An icon's look. [colors] is empty for `--background auto`.
@internal
@immutable
final class IconDesign {
  const IconDesign({
    this.trim = false,
    this.padding = IconPadding.none,
    this.foreground,
    this.effect = IconEffect.none,
    this.backgroundType = IconBackgroundType.color,
    this.colors = const [],
    this.gradientAngle = 135,
    this.backgroundImage,
    this.texture = IconTexture.none,
    this.badge,
  });

  final bool trim;
  final IconPadding padding;
  final IconColor? foreground;
  final IconEffect effect;
  final IconBackgroundType backgroundType;
  final List<IconColor> colors;

  /// Degrees: 0 goes up, 90 right, 135 towards the lower right.
  final double gradientAngle;
  final RgbaImage? backgroundImage;
  final IconTexture texture;

  /// Drawn across the bottom, its width the logo box's.
  final RgbaImage? badge;
}
