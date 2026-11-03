// studio: 023 — where the logo sits in an app icon, measured against the
// shape iOS cuts the icon to (specs/023-icon-studio).
import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/assets/png_codec.dart';

/// An opaque colour.
@internal
typedef IconColor = (int, int, int);

/// `#RRGGBB` for [color].
@internal
String iconColorHex(IconColor color) {
  String two(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
  return '#${two(color.$1)}${two(color.$2)}${two(color.$3)}';
}

/// What [IconAnalyzer.analyze] measured. Fractions are of the icon's side.
@internal
@immutable
final class IconPlacement {
  const IconPlacement({
    required this.background,
    required this.box,
    required this.offset,
    required this.outsideMask,
    required this.prerounded,
    required this.transparent,
  });

  /// The colour of the border, or null for full-bleed artwork.
  final IconColor? background;

  /// The logo's left, top, width and height; null when the icon is one
  /// colour or full-bleed.
  final (double, double, double, double)? box;

  /// The logo's centre minus the icon's centre (positive: right, down).
  final (double, double) offset;

  /// The share of the logo's pixels iOS's rounded corners cut off.
  final double outsideMask;

  /// The corners already differ from the border: the icon was exported
  /// rounded or with transparent corners.
  final bool prerounded;

  /// Some pixel is not fully opaque.
  final bool transparent;

  bool get fullBleed => background == null;

  Map<String, Object?> toJson() => {
    'background': background == null ? null : iconColorHex(background!),
    'box': box == null ? null : [box!.$1, box!.$2, box!.$3, box!.$4],
    'offset': [offset.$1, offset.$2],
    'outsideMask': outsideMask,
    'prerounded': prerounded,
    'transparent': transparent,
    'fullBleed': fullBleed,
  };
}

/// Measures logo placement on a square icon.
@internal
abstract final class IconAnalyzer {
  /// Analysis grid: 4 px of a 1024 px icon per cell.
  static const _size = 256;

  /// Border ring width in grid cells.
  static const _ring = 3;

  /// Share of the ring one colour must cover to count as the background.
  static const _uniformShare = 0.85;

  /// Colour distance above which a pixel is part of the logo.
  static const _foreground = 48.0;

  /// Colour distance within which pixels count as one colour.
  static const _tolerance = 24.0;

  /// Whether the point ([u], [v]) of the unit square is inside the iOS icon
  /// shape, approximated by the superellipse |x|⁵ + |y|⁵ ≤ 1 (it cuts the
  /// diagonal at 6.5% of the side, as iOS's rounded corners do).
  static bool insideMask(double u, double v) {
    final x = (2 * u - 1).abs();
    final y = (2 * v - 1).abs();
    return math.pow(x, 5) + math.pow(y, 5) <= 1;
  }

  static IconPlacement analyze(RgbaImage image) {
    var transparent = false;
    for (var i = 3; i < image.rgba.length; i += 4) {
      if (image.rgba[i] < 255) {
        transparent = true;
        break;
      }
    }
    final grid = image.resized(_size, _size);
    // Colours as iOS shows them: transparent pixels over black.
    final colors = List<IconColor>.generate(_size * _size, (index) {
      final i = index * 4;
      final a = grid.rgba[i + 3];
      return (
        grid.rgba[i] * a ~/ 255,
        grid.rgba[i + 1] * a ~/ 255,
        grid.rgba[i + 2] * a ~/ 255,
      );
    });
    final outside = List<bool>.generate(
      _size * _size,
      (index) => !insideMask(
        (index % _size + 0.5) / _size,
        (index ~/ _size + 0.5) / _size,
      ),
    );

    final ring = <int>[];
    final corners = <int>[];
    for (var index = 0; index < _size * _size; index++) {
      if (outside[index]) {
        corners.add(index);
        continue;
      }
      final x = index % _size;
      final y = index ~/ _size;
      if (x < _ring || y < _ring || x >= _size - _ring || y >= _size - _ring) {
        ring.add(index);
      }
    }
    final background = _dominant(colors, ring, _uniformShare);

    // Rounded or transparent corners in the file: the corners are one colour
    // that is not the border's, or mostly transparent while the border is
    // opaque.
    double alphaOf(List<int> indexes) => indexes.isEmpty
        ? 255
        : indexes.map((i) => grid.rgba[i * 4 + 3]).reduce((a, b) => a + b) /
              indexes.length;
    final cornerColor = _dominant(colors, corners, 0.8);
    final prerounded =
        (alphaOf(corners) < 128 && alphaOf(ring) > 200) ||
        (background != null &&
            cornerColor != null &&
            _distance(background, cornerColor) > 60);

    if (background == null) {
      return IconPlacement(
        background: null,
        box: null,
        offset: (0, 0),
        outsideMask: 0,
        prerounded: prerounded,
        transparent: transparent,
      );
    }

    var minX = _size;
    var minY = _size;
    var maxX = -1;
    var maxY = -1;
    var logo = 0;
    var cut = 0;
    for (var index = 0; index < _size * _size; index++) {
      // Pre-rounded corners are not logo: iOS cuts them anyway.
      if (prerounded && outside[index]) continue;
      if (_distance(colors[index], background) <= _foreground) continue;
      final x = index % _size;
      final y = index ~/ _size;
      logo++;
      if (outside[index]) cut++;
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
    }
    if (logo == 0) {
      return IconPlacement(
        background: background,
        box: null,
        offset: (0, 0),
        outsideMask: 0,
        prerounded: prerounded,
        transparent: transparent,
      );
    }
    final left = minX / _size;
    final top = minY / _size;
    final width = (maxX + 1 - minX) / _size;
    final height = (maxY + 1 - minY) / _size;
    return IconPlacement(
      background: background,
      box: (left, top, width, height),
      offset: (left + width / 2 - 0.5, top + height / 2 - 0.5),
      outsideMask: cut < 4 ? 0 : cut / logo,
      prerounded: prerounded,
      transparent: transparent,
    );
  }

  /// The average colour of [indexes] near their most common colour (16
  /// levels per channel), when those cover at least [share] of them.
  static IconColor? _dominant(
    List<IconColor> colors,
    List<int> indexes,
    double share,
  ) {
    if (indexes.isEmpty) return null;
    final counts = <int, int>{};
    for (final index in indexes) {
      final key = _bucket(colors[index]);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    IconColor mean(Iterable<int> members) {
      var r = 0;
      var g = 0;
      var b = 0;
      var n = 0;
      for (final index in members) {
        r += colors[index].$1;
        g += colors[index].$2;
        b += colors[index].$3;
        n++;
      }
      return (r ~/ n, g ~/ n, b ~/ n);
    }

    // The bucket's mean, then every colour near it: a colour on a bucket
    // edge (127/128) still counts once.
    final seed = mean(indexes.where((i) => _bucket(colors[i]) == best.key));
    final near = [
      for (final index in indexes)
        if (_distance(colors[index], seed) <= _tolerance) index,
    ];
    if (near.length < indexes.length * share) return null;
    return mean(near);
  }

  static int _bucket(IconColor color) =>
      (color.$1 >> 4) << 8 | (color.$2 >> 4) << 4 | color.$3 >> 4;

  static double _distance(IconColor a, IconColor b) {
    final dr = a.$1 - b.$1;
    final dg = a.$2 - b.$2;
    final db = a.$3 - b.$3;
    return math.sqrt(dr * dr + dg * dg + db * db);
  }
}
