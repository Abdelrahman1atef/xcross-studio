// studio: 024 — background textures, drawn by code so nothing is bundled
// (specs/024-icon-splash-studio, AC-024-3, FR-005).
import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/icons/icon_design.dart';

/// How much of [IconTexture] covers a point: 0 to 1, for coordinates where the
/// canvas's short side is 1. Pure functions of the coordinates, so a texture
/// looks the same at every size and on every run.
@internal
abstract final class IconTextures {
  static double coverage(IconTexture texture, double u, double v) =>
      switch (texture) {
        IconTexture.none => 0,
        IconTexture.argyle => _argyle(u, v),
        IconTexture.concentric => _concentric(u, v),
        IconTexture.contour => _contour(u, v),
        IconTexture.coral => _coral(u, v),
        IconTexture.fabric => _fabric(u, v),
        IconTexture.halftone => _halftone(u, v),
        IconTexture.maze => _maze(u, v),
        IconTexture.mosaic => _mosaic(u, v),
        IconTexture.polka => _polka(u, v),
        IconTexture.stipple => _stipple(u, v),
        IconTexture.waves => _waves(u, v),
      };

  /// 1 inside [edge], fading out over [soft].
  static double _inside(double value, double edge, double soft) {
    final t = (edge - value) / soft + 0.5;
    return t < 0
        ? 0
        : t > 1
        ? 1
        : t;
  }

  /// A repeatable pseudo-random number in 0..1 for a grid cell.
  static double _hash(int x, int y) {
    var h = (x * 374761393 + y * 668265263) & 0xFFFFFFFF;
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF;
    return ((h ^ (h >> 16)) & 0xFFFFFF) / 0xFFFFFF;
  }

  static double _fract(double value) => value - value.floorToDouble();

  static double _argyle(double u, double v) {
    const scale = 5.0;
    final a = (u + v) * scale;
    final b = (u - v) * scale;
    final even = (a.floor() + b.floor()).isEven;
    final line = math.min(
      (_fract(a * 2) - 0.5).abs(),
      (_fract(b * 2) - 0.5).abs(),
    );
    return math.max(even ? 0.55 : 0.0, _inside(line, 0.05, 0.03) * 0.8);
  }

  static double _concentric(double u, double v) {
    final distance = math.sqrt((u - 0.5) * (u - 0.5) + (v - 0.5) * (v - 0.5));
    return _inside((_fract(distance * 11) - 0.5).abs(), 0.25, 0.04);
  }

  static double _contour(double u, double v) {
    final height =
        math.sin(u * 7.1 + math.sin(v * 5.3) * 1.3) +
        math.sin(v * 8.7 + math.sin(u * 3.9) * 1.7) * 0.8 +
        math.sin((u + v) * 4.3) * 0.5;
    return _inside((_fract(height * 2.4) - 0.5).abs(), 0.07, 0.04);
  }

  static double _coral(double u, double v) {
    final x = u * 18;
    final y = v * 18;
    final field =
        math.sin(x + math.sin(y * 0.7) * 2.1) *
        math.sin(y + math.sin(x * 0.6) * 2.3);
    return _inside(field.abs(), 0.2, 0.07);
  }

  static double _fabric(double u, double v) {
    const threads = 26.0;
    final x = u * threads;
    final y = v * threads;
    final overHorizontal = (x.floor() + y.floor()).isEven;
    final across = overHorizontal ? _fract(y) : _fract(x);
    return _inside((across - 0.5).abs(), 0.36, 0.1) *
        (overHorizontal ? 0.9 : 0.45);
  }

  static double _halftone(double u, double v) {
    const cells = 16.0;
    final a = (u + v) * cells * 0.7071;
    final b = (u - v) * cells * 0.7071;
    final distance = math.sqrt(
      math.pow(_fract(a) - 0.5, 2) + math.pow(_fract(b) - 0.5, 2),
    );
    final radius = 0.08 + 0.42 * ((u + v) / 2).clamp(0.0, 1.0);
    return _inside(distance, radius, 0.06);
  }

  static double _maze(double u, double v) {
    const cells = 12.0;
    final x = u * cells;
    final y = v * cells;
    final fx = _fract(x);
    final fy = _fract(y);
    final flip = _hash(x.floor(), y.floor()) > 0.5;
    final across = flip ? (fx - fy).abs() : (fx + fy - 1).abs();
    return _inside(across / math.sqrt2, 0.07, 0.04);
  }

  static double _mosaic(double u, double v) {
    const cells = 9.0;
    final x = u * cells;
    final y = v * cells;
    final grout = math.min(
      math.min(_fract(x), 1 - _fract(x)),
      math.min(_fract(y), 1 - _fract(y)),
    );
    return _hash(x.floor() + 7, y.floor() + 11) *
        (1 - _inside(grout, 0.04, 0.03));
  }

  static double _polka(double u, double v) {
    const cells = 9.0;
    final y = v * cells;
    final row = y.floor();
    final x = u * cells + (row.isEven ? 0 : 0.5);
    final distance = math.sqrt(
      math.pow(_fract(x) - 0.5, 2) + math.pow(_fract(y) - 0.5, 2),
    );
    return _inside(distance, 0.24, 0.05);
  }

  static double _stipple(double u, double v) {
    const cells = 42.0;
    final x = u * cells;
    final y = v * cells;
    final cellX = x.floor();
    final cellY = y.floor();
    if (_hash(cellX, cellY) < 0.45) return 0;
    final cx = 0.3 + 0.4 * _hash(cellX + 31, cellY);
    final cy = 0.3 + 0.4 * _hash(cellX, cellY + 17);
    final distance = math.sqrt(
      math.pow(_fract(x) - cx, 2) + math.pow(_fract(y) - cy, 2),
    );
    return _inside(distance, 0.18, 0.1);
  }

  static double _waves(double u, double v) {
    final y = v * 10 + math.sin(u * 9) * 0.55;
    return _inside((_fract(y) - 0.5).abs(), 0.2, 0.06);
  }
}
