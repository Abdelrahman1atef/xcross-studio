// studio: 024 — draws an icon design at any size
// (specs/024-icon-splash-studio, User Story 1).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/assets/png_codec.dart';
import 'package:studio_ext/src/shared/icons/icon_analysis.dart';
import 'package:studio_ext/src/shared/icons/icon_design.dart';
import 'package:studio_ext/src/shared/icons/icon_textures.dart';

/// Draws [design] with one source image. The order is background, texture,
/// shadow, logo, badge.
///
/// A canvas has a logo box: a centred square of its short side, or of a
/// share of it ([viewport], for adaptive and maskable icons whose edges are
/// cut). Padding is measured inside that box.
@internal
final class IconComposer {
  IconComposer(RgbaImage source, this.design)
    : _border = borderColorOf(source),
      logo = design.trim ? trimmed(source) : source;

  final IconDesign design;

  /// The source after trim.
  final RgbaImage logo;

  final IconColor? _border;

  /// The colours behind the logo: the design's, or for `auto` the source's
  /// border colour when it is one opaque colour, else white.
  List<IconColor> get colors =>
      design.colors.isNotEmpty ? design.colors : [_border ?? (255, 255, 255)];

  /// The logo has to be enlarged to fill its place in a [side] px canvas.
  bool upscaledAt(int side) => _logoScale(side, side, 1) > 1;

  /// Every layer, opaque unless [design] has an image with holes.
  RgbaImage draw(int width, int height, {double viewport = 1}) {
    final out = _background(width, height);
    _overlay(out, foreground(width, height, viewport: viewport));
    return out;
  }

  /// The background and texture alone, for an adaptive icon's back layer.
  RgbaImage backgroundLayer(int width, int height) =>
      _background(width, height);

  /// The logo, its effect and the badge on transparent, for an adaptive
  /// icon's front layer.
  RgbaImage foreground(int width, int height, {double viewport = 1}) {
    final logoLayer = _logoLayer(width, height, viewport);
    final shade = switch (design.effect) {
      IconEffect.dropShadow => _dropShadow(logoLayer),
      IconEffect.castShadow => _castShadow(logoLayer),
      IconEffect.none || IconEffect.score => null,
    };
    if (design.effect == IconEffect.score) _score(logoLayer);
    final out = shade ?? _transparent(width, height);
    _overlay(out, logoLayer);
    final badge = design.badge;
    if (badge != null) _drawBadge(out, badge, viewport);
    return out;
  }

  /// White on transparent, in the logo's shape, for notification and themed
  /// icons; null when the logo has no shape to take: no transparency and no
  /// one-colour border.
  RgbaImage? silhouette(int width, int height, {double viewport = 1}) {
    final shape = _shapeAlpha(logo);
    if (shape == null) return null;
    final placed = _place(shape, width, height, viewport);
    final out = _transparent(width, height);
    for (var i = 0; i < out.rgba.length; i += 4) {
      out.rgba[i] = 255;
      out.rgba[i + 1] = 255;
      out.rgba[i + 2] = 255;
      out.rgba[i + 3] = placed.rgba[i + 3];
    }
    return out;
  }

  /// [image]'s border colour when it is one opaque colour.
  static IconColor? borderColorOf(RgbaImage image) {
    final short = math.min(image.width, image.height);
    final depth = math.max(1, short ~/ 64);
    var r = 0;
    var g = 0;
    var b = 0;
    var count = 0;
    final pixels = <int>[];
    for (var y = 0; y < image.height; y++) {
      final edgeRow = y < depth || y >= image.height - depth;
      for (var x = 0; x < image.width; x++) {
        if (!edgeRow && x >= depth && x < image.width - depth) continue;
        final i = (y * image.width + x) * 4;
        if (image.rgba[i + 3] < 250) return null;
        r += image.rgba[i];
        g += image.rgba[i + 1];
        b += image.rgba[i + 2];
        count++;
        pixels.add(i);
      }
    }
    if (count == 0) return null;
    final mean = (r ~/ count, g ~/ count, b ~/ count);
    var near = 0;
    for (final i in pixels) {
      final dr = image.rgba[i] - mean.$1;
      final dg = image.rgba[i + 1] - mean.$2;
      final db = image.rgba[i + 2] - mean.$3;
      if (dr * dr + dg * dg + db * db <= 24 * 24) near++;
    }
    return near >= count * 0.9 ? mean : null;
  }

  /// [source] without its transparent or one-colour borders. A source that is
  /// all border is returned as it is.
  static RgbaImage trimmed(RgbaImage source) {
    final border = borderColorOf(source);
    final hasTransparency = _hasTransparency(source);
    if (border == null && !hasTransparency) return source;
    bool isContent(int i) {
      if (hasTransparency) return source.rgba[i + 3] > 12;
      final dr = source.rgba[i] - border!.$1;
      final dg = source.rgba[i + 1] - border.$2;
      final db = source.rgba[i + 2] - border.$3;
      return dr * dr + dg * dg + db * db > 24 * 24;
    }

    var left = source.width;
    var right = -1;
    var top = source.height;
    var bottom = -1;
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        if (!isContent((y * source.width + x) * 4)) continue;
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
    if (right < 0) return source;
    final width = right - left + 1;
    final height = bottom - top + 1;
    if (width == source.width && height == source.height) return source;
    final out = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      final from = ((top + y) * source.width + left) * 4;
      out.setRange(y * width * 4, (y + 1) * width * 4, source.rgba, from);
    }
    return RgbaImage(width, height, out);
  }

  /// The source has pixels iOS would show as black.
  static bool hasTransparency(RgbaImage image) => _hasTransparency(image);

  static bool _hasTransparency(RgbaImage image) {
    for (var i = 3; i < image.rgba.length; i += 4) {
      if (image.rgba[i] < 250) return true;
    }
    return false;
  }

  static RgbaImage _transparent(int width, int height) =>
      RgbaImage(width, height, Uint8List(width * height * 4));

  // --- Logo ---------------------------------------------------------------

  double _logoScale(int width, int height, double viewport) {
    final box = math.min(width, height) * viewport;
    final innerWidth =
        box * (1 - design.padding.left / 100 - design.padding.right / 100);
    final innerHeight =
        box * (1 - design.padding.top / 100 - design.padding.bottom / 100);
    return math.min(innerWidth / logo.width, innerHeight / logo.height);
  }

  /// [image], fitted to the padded logo box of a canvas.
  RgbaImage _place(RgbaImage image, int width, int height, double viewport) {
    final box = math.min(width, height) * viewport;
    final padding = design.padding;
    final innerLeft = (width - box) / 2 + box * padding.left / 100;
    final innerTop = (height - box) / 2 + box * padding.top / 100;
    final innerWidth = box * (1 - padding.left / 100 - padding.right / 100);
    final innerHeight = box * (1 - padding.top / 100 - padding.bottom / 100);
    final scale = math.min(
      innerWidth / image.width,
      innerHeight / image.height,
    );
    final drawnWidth = math.max(1, (image.width * scale).round());
    final drawnHeight = math.max(1, (image.height * scale).round());
    final fitted = image.resized(drawnWidth, drawnHeight);
    final left = (innerLeft + (innerWidth - drawnWidth) / 2).round();
    final top = (innerTop + (innerHeight - drawnHeight) / 2).round();
    final out = _transparent(width, height);
    for (var y = 0; y < drawnHeight; y++) {
      final targetY = top + y;
      if (targetY < 0 || targetY >= height) continue;
      for (var x = 0; x < drawnWidth; x++) {
        final targetX = left + x;
        if (targetX < 0 || targetX >= width) continue;
        final from = (y * drawnWidth + x) * 4;
        final to = (targetY * width + targetX) * 4;
        out.rgba[to] = fitted.rgba[from];
        out.rgba[to + 1] = fitted.rgba[from + 1];
        out.rgba[to + 2] = fitted.rgba[from + 2];
        out.rgba[to + 3] = fitted.rgba[from + 3];
      }
    }
    return out;
  }

  RgbaImage _logoLayer(int width, int height, double viewport) {
    final layer = _place(logo, width, height, viewport);
    final tint = design.foreground;
    if (tint != null) {
      for (var i = 0; i < layer.rgba.length; i += 4) {
        layer.rgba[i] = tint.$1;
        layer.rgba[i + 1] = tint.$2;
        layer.rgba[i + 2] = tint.$3;
      }
    }
    return layer;
  }

  /// The source's shape as alpha: its own transparency, or the distance from
  /// its one-colour border.
  RgbaImage? _shapeAlpha(RgbaImage image) {
    if (_hasTransparency(image)) return image;
    final border = _border;
    if (border == null) return null;
    final out = Uint8List(image.rgba.length);
    for (var i = 0; i < out.length; i += 4) {
      final dr = image.rgba[i] - border.$1;
      final dg = image.rgba[i + 1] - border.$2;
      final db = image.rgba[i + 2] - border.$3;
      final distance = math.sqrt(dr * dr + dg * dg + db * db);
      out[i + 3] = (((distance - 12) / 36).clamp(0.0, 1.0) * 255).round();
    }
    return RgbaImage(image.width, image.height, out);
  }

  // --- Effects ------------------------------------------------------------

  RgbaImage _dropShadow(RgbaImage layer) {
    final short = math.min(layer.width, layer.height);
    final radius = math.max(1, (short * 0.014).round());
    final drop = math.max(1, (short * 0.016).round());
    var mask = Float32List(layer.width * layer.height);
    for (var i = 0; i < mask.length; i++) {
      mask[i] = layer.rgba[i * 4 + 3] / 255;
    }
    for (var pass = 0; pass < 3; pass++) {
      mask = _boxBlur(mask, layer.width, layer.height, radius);
    }
    final out = _transparent(layer.width, layer.height);
    for (var y = drop; y < layer.height; y++) {
      for (var x = 0; x < layer.width; x++) {
        final alpha = mask[(y - drop) * layer.width + x] * 0.42;
        out.rgba[(y * layer.width + x) * 4 + 3] = (alpha * 255).round();
      }
    }
    return out;
  }

  static Float32List _boxBlur(
    Float32List source,
    int width,
    int height,
    int radius,
  ) {
    final span = radius * 2 + 1;
    final across = Float32List(source.length);
    for (var y = 0; y < height; y++) {
      final row = y * width;
      var sum = 0.0;
      for (var x = -radius; x <= radius; x++) {
        sum += source[row + x.clamp(0, width - 1)];
      }
      for (var x = 0; x < width; x++) {
        across[row + x] = sum / span;
        sum +=
            source[row + (x + radius + 1).clamp(0, width - 1)] -
            source[row + (x - radius).clamp(0, width - 1)];
      }
    }
    final down = Float32List(source.length);
    for (var x = 0; x < width; x++) {
      var sum = 0.0;
      for (var y = -radius; y <= radius; y++) {
        sum += across[y.clamp(0, height - 1) * width + x];
      }
      for (var y = 0; y < height; y++) {
        down[y * width + x] = sum / span;
        sum +=
            across[(y + radius + 1).clamp(0, height - 1) * width + x] -
            across[(y - radius).clamp(0, height - 1) * width + x];
      }
    }
    return down;
  }

  /// A long shadow towards the lower right, fading with distance.
  RgbaImage _castShadow(RgbaImage layer) {
    final width = layer.width;
    final height = layer.height;
    final length = math.min(width, height) * 0.9;
    final decay = math.pow(0.02, 1 / length).toDouble();
    final shade = Float32List(width * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final here = layer.rgba[(y * width + x) * 4 + 3] / 255;
        final carried = x > 0 && y > 0
            ? shade[(y - 1) * width + x - 1] * decay
            : 0.0;
        shade[y * width + x] = math.max(here, carried);
      }
    }
    final out = _transparent(width, height);
    for (var i = 0; i < shade.length; i++) {
      out.rgba[i * 4 + 3] = (shade[i] * 0.3 * 255).round();
    }
    return out;
  }

  /// A fold: the logo's lower half slightly darker, its upper half lighter.
  void _score(RgbaImage layer) {
    var top = layer.height;
    var bottom = -1;
    for (var y = 0; y < layer.height; y++) {
      for (var x = 0; x < layer.width; x++) {
        if (layer.rgba[(y * layer.width + x) * 4 + 3] > 12) {
          if (y < top) top = y;
          if (y > bottom) bottom = y;
          break;
        }
      }
    }
    if (bottom < 0) return;
    final middle = (top + bottom) / 2;
    for (var y = 0; y < layer.height; y++) {
      final lower = y >= middle;
      for (var x = 0; x < layer.width; x++) {
        final i = (y * layer.width + x) * 4;
        for (var c = 0; c < 3; c++) {
          final value = layer.rgba[i + c];
          layer.rgba[i + c] = lower
              ? (value * 0.8).round()
              : (value + (255 - value) * 0.08).round();
        }
      }
    }
  }

  void _drawBadge(RgbaImage out, RgbaImage badge, double viewport) {
    final box = math.min(out.width, out.height) * viewport;
    final badgeWidth = math.max(1, box.round());
    final badgeHeight = math.max(1, (badge.height * box / badge.width).round());
    final fitted = badge.resized(badgeWidth, badgeHeight);
    final left = ((out.width - badgeWidth) / 2).round();
    final top = ((out.height + box) / 2 - badgeHeight).round();
    final layer = _transparent(out.width, out.height);
    for (var y = 0; y < badgeHeight; y++) {
      final targetY = top + y;
      if (targetY < 0 || targetY >= out.height) continue;
      for (var x = 0; x < badgeWidth; x++) {
        final targetX = left + x;
        if (targetX < 0 || targetX >= out.width) continue;
        final from = (y * badgeWidth + x) * 4;
        final to = (targetY * out.width + targetX) * 4;
        layer.rgba.setRange(to, to + 4, fitted.rgba, from);
      }
    }
    _overlay(out, layer);
  }

  // --- Background ---------------------------------------------------------

  RgbaImage _background(int width, int height) {
    final out = switch (design.backgroundType) {
      IconBackgroundType.color => _solid(width, height),
      IconBackgroundType.gradient => _gradient(width, height),
      IconBackgroundType.mesh => _mesh(width, height),
      IconBackgroundType.image => _imageBackground(width, height),
    };
    if (design.texture != IconTexture.none) _texture(out);
    return out;
  }

  RgbaImage _solid(int width, int height) {
    final color = colors.first;
    final out = Uint8List(width * height * 4);
    for (var i = 0; i < out.length; i += 4) {
      out[i] = color.$1;
      out[i + 1] = color.$2;
      out[i + 2] = color.$3;
      out[i + 3] = 255;
    }
    return RgbaImage(width, height, out);
  }

  /// The second colour of a gradient given one: a darker first colour.
  IconColor _colorAt(int index) {
    final all = colors;
    if (index < all.length) return all[index];
    final base = all.first;
    final darkened = (
      (base.$1 * 0.6).round(),
      (base.$2 * 0.6).round(),
      (base.$3 * 0.6).round(),
    );
    return index.isOdd ? darkened : base;
  }

  RgbaImage _gradient(int width, int height) {
    final from = _colorAt(0);
    final to = _colorAt(1);
    final radians = design.gradientAngle * math.pi / 180;
    final dx = math.sin(radians);
    final dy = -math.cos(radians);
    final reach = (width * dx).abs() + (height * dy).abs();
    final out = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final t =
            (((x + 0.5 - width / 2) * dx + (y + 0.5 - height / 2) * dy) /
                reach) +
            0.5;
        _put(out, (y * width + x) * 4, _mix(from, to, t));
      }
    }
    return RgbaImage(width, height, out);
  }

  /// Four corner colours (top left, top right, bottom left, bottom right).
  RgbaImage _mesh(int width, int height) {
    final topLeft = _colorAt(0);
    final topRight = _colorAt(1);
    final bottomLeft = _colorAt(2);
    final bottomRight = _colorAt(3);
    double smooth(double t) => t * t * (3 - 2 * t);
    final out = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      final v = smooth((y + 0.5) / height);
      for (var x = 0; x < width; x++) {
        final u = smooth((x + 0.5) / width);
        final top = _mix(topLeft, topRight, u);
        final bottom = _mix(bottomLeft, bottomRight, u);
        _put(out, (y * width + x) * 4, _mix(top, bottom, v));
      }
    }
    return RgbaImage(width, height, out);
  }

  /// The image filling the canvas, cropped rather than stretched.
  RgbaImage _imageBackground(int width, int height) {
    final image = design.backgroundImage;
    if (image == null) return _solid(width, height);
    final scale = math.max(width / image.width, height / image.height);
    final cropWidth = math.min(image.width, (width / scale).round());
    final cropHeight = math.min(image.height, (height / scale).round());
    final left = (image.width - cropWidth) ~/ 2;
    final top = (image.height - cropHeight) ~/ 2;
    final crop = Uint8List(cropWidth * cropHeight * 4);
    for (var y = 0; y < cropHeight; y++) {
      final from = ((top + y) * image.width + left) * 4;
      crop.setRange(
        y * cropWidth * 4,
        (y + 1) * cropWidth * 4,
        image.rgba,
        from,
      );
    }
    final resized = RgbaImage(
      cropWidth,
      cropHeight,
      crop,
    ).resized(width, height);
    // Holes in the image show the first colour, so the result stays opaque.
    final out = _solid(width, height);
    _overlay(out, resized);
    return out;
  }

  /// A subtle pattern: white on dark backgrounds, black on light ones.
  void _texture(RgbaImage image) {
    final short = math.min(image.width, image.height);
    for (var y = 0; y < image.height; y++) {
      final v = (y + 0.5) / short;
      for (var x = 0; x < image.width; x++) {
        final u = (x + 0.5) / short;
        final coverage = IconTextures.coverage(design.texture, u, v);
        if (coverage <= 0) continue;
        final i = (y * image.width + x) * 4;
        final luma =
            image.rgba[i] * 0.299 +
            image.rgba[i + 1] * 0.587 +
            image.rgba[i + 2] * 0.114;
        final ink = luma < 140 ? 255 : 0;
        final alpha = coverage * (luma < 140 ? 0.14 : 0.1);
        for (var c = 0; c < 3; c++) {
          image.rgba[i + c] = (image.rgba[i + c] * (1 - alpha) + ink * alpha)
              .round();
        }
      }
    }
  }

  static IconColor _mix(IconColor from, IconColor to, double t) {
    final amount = t.clamp(0.0, 1.0);
    int channel(int a, int b) => (a + (b - a) * amount).round();
    return (
      channel(from.$1, to.$1),
      channel(from.$2, to.$2),
      channel(from.$3, to.$3),
    );
  }

  static void _put(Uint8List out, int i, IconColor color) {
    out[i] = color.$1;
    out[i + 1] = color.$2;
    out[i + 2] = color.$3;
    out[i + 3] = 255;
  }

  /// [top] over [bottom], in place, both straight alpha.
  static void _overlay(RgbaImage bottom, RgbaImage top) {
    final under = bottom.rgba;
    final over = top.rgba;
    for (var i = 0; i < over.length; i += 4) {
      final alpha = over[i + 3];
      if (alpha == 0) continue;
      if (alpha == 255) {
        under.setRange(i, i + 4, over, i);
        continue;
      }
      final a = alpha / 255;
      final b = under[i + 3] / 255;
      final result = a + b * (1 - a);
      for (var c = 0; c < 3; c++) {
        under[i + c] = ((over[i + c] * a + under[i + c] * b * (1 - a)) / result)
            .round();
      }
      under[i + 3] = (result * 255).round();
    }
  }
}
