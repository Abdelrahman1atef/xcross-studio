// studio: 024 — the icon design options (specs/024-icon-splash-studio).
import 'dart:typed_data';

import 'package:studio_ext/src/shared/assets/png_codec.dart';
import 'package:studio_ext/src/shared/icons/icon_composer.dart';
import 'package:studio_ext/src/shared/icons/icon_design.dart';
import 'package:test/test.dart';

/// A red [logo]-px square centred in a transparent [side]-px image.
RgbaImage _logo({int side = 64, int logo = 32}) {
  final out = Uint8List(side * side * 4);
  final start = (side - logo) ~/ 2;
  for (var y = start; y < start + logo; y++) {
    for (var x = start; x < start + logo; x++) {
      final i = (y * side + x) * 4;
      out[i] = 200;
      out[i + 3] = 255;
    }
  }
  return RgbaImage(side, side, out);
}

(int, int, int, int) _pixel(RgbaImage image, int x, int y) {
  final i = (y * image.width + x) * 4;
  return (
    image.rgba[i],
    image.rgba[i + 1],
    image.rgba[i + 2],
    image.rgba[i + 3],
  );
}

/// Left, top, right, bottom of the pixels [test] accepts.
(int, int, int, int) _box(
  RgbaImage image,
  bool Function(int, int, int, int) test,
) {
  var left = image.width;
  var top = image.height;
  var right = -1;
  var bottom = -1;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final (r, g, b, a) = _pixel(image, x, y);
      if (!test(r, g, b, a)) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  return (left, top, right, bottom);
}

bool _isLogo(int r, int g, int b, int a) =>
    r > 150 && g < 80 && b < 80 && a > 200;

void main() {
  const white = (255, 255, 255);

  group('AC-024-1 padding and trim', () {
    test('one value or four; nonsense and no room are refused', () {
      final four = IconPadding.parse('10,14,18,16')!;
      expect((four.top, four.right, four.bottom, four.left), (10, 14, 18, 16));
      expect(IconPadding.parse('12')!.isUniform, isTrue);
      expect(IconPadding.parse('12')!.text, '12');
      expect(four.text, '10,14,18,16');
      for (final bad in ['46', '-1', 'a', '1,2,3', '1,2', '45,45,45,x']) {
        expect(IconPadding.parse(bad), isNull, reason: bad);
      }
    });

    test('each side moves the logo that way', () {
      final logo = _logo(side: 32);
      RgbaImage draw(IconPadding padding) => IconComposer(
        logo,
        IconDesign(padding: padding, colors: const [white]),
      ).draw(200, 200);
      final even = _box(draw(const IconPadding.all(25)), _isLogo);
      expect(even, (50, 50, 149, 149));
      final moved = _box(draw(const IconPadding(40, 25, 10, 25)), _isLogo);
      // Same 100 px height left, placed 30 px lower.
      expect(moved.$2, 80);
      expect(moved.$4, 179);
    });

    test('trim measures padding from the logo, not its empty border', () {
      RgbaImage draw({required bool trim}) => IconComposer(
        _logo(),
        IconDesign(
          trim: trim,
          padding: const IconPadding.all(10),
          colors: const [white],
        ),
      ).draw(100, 100);
      final (l, _, r, _) = _box(draw(trim: false), _isLogo);
      expect(r - l + 1, 40);
      final (tl, _, tr, _) = _box(draw(trim: true), _isLogo);
      expect(tr - tl + 1, 80);
    });

    test('trim also removes a one-colour border', () {
      final source = Uint8List(8 * 8 * 4);
      for (var i = 0; i < source.length; i += 4) {
        source.setRange(i, i + 4, [10, 20, 30, 255]);
      }
      source.setRange((3 * 8 + 3) * 4, (3 * 8 + 3) * 4 + 4, [200, 0, 0, 255]);
      final trimmed = IconComposer.trimmed(RgbaImage(8, 8, source));
      expect((trimmed.width, trimmed.height), (1, 1));
    });

    test('a source that is all border stays as it is', () {
      final empty = RgbaImage(4, 4, Uint8List(4 * 4 * 4));
      expect(IconComposer.trimmed(empty).width, 4);
    });
  });

  group('AC-024-2 foreground and effects', () {
    test('foreground recolours and keeps the shape', () {
      final image = IconComposer(
        _logo(),
        const IconDesign(foreground: (0, 90, 200), colors: [white]),
      ).draw(64, 64);
      expect(_pixel(image, 32, 32), (0, 90, 200, 255));
      expect(_pixel(image, 2, 2), (255, 255, 255, 255));
    });

    RgbaImage withEffect(IconEffect effect) => IconComposer(
      _logo(side: 100, logo: 40),
      IconDesign(effect: effect, colors: const [white]),
    ).draw(200, 200);

    int darkness(RgbaImage image, int x, int y) => 255 - _pixel(image, x, y).$2;

    test('drop shadow darkens below the logo, not above it', () {
      final image = withEffect(IconEffect.dropShadow);
      expect(darkness(image, 100, 142), greaterThan(20));
      expect(darkness(image, 100, 50), 0);
    });

    test('cast shadow runs towards the lower right', () {
      final image = withEffect(IconEffect.castShadow);
      expect(darkness(image, 150, 150), greaterThan(15));
      expect(darkness(image, 50, 50), 0);
      expect(
        darkness(image, 130, 130),
        greaterThan(darkness(image, 175, 175)),
        reason: 'it fades with distance',
      );
    });

    test('score darkens the lower half of the logo only', () {
      final plain = withEffect(IconEffect.none);
      final scored = withEffect(IconEffect.score);
      expect(_pixel(scored, 100, 120).$1, lessThan(_pixel(plain, 100, 120).$1));
      expect(
        _pixel(scored, 100, 80).$1,
        greaterThanOrEqualTo(_pixel(plain, 100, 80).$1),
      );
      expect(_pixel(scored, 20, 20), _pixel(plain, 20, 20));
    });

    test('effects stay inside the canvas and the result stays opaque', () {
      for (final effect in IconEffect.values) {
        final image = withEffect(effect);
        for (var i = 3; i < image.rgba.length; i += 4) {
          expect(image.rgba[i], 255, reason: effect.option);
        }
      }
    });
  });

  group('AC-024-3 background', () {
    final logo = RgbaImage(1, 1, Uint8List(4));

    test('auto takes the border colour, else white', () {
      final opaque = Uint8List(4 * 4 * 4);
      for (var i = 0; i < opaque.length; i += 4) {
        opaque.setRange(i, i + 4, [5, 6, 7, 255]);
      }
      expect(IconComposer(RgbaImage(4, 4, opaque), const IconDesign()).colors, [
        (5, 6, 7),
      ]);
      expect(IconComposer(_logo(), const IconDesign()).colors, [white]);
    });

    test('a gradient runs from the first colour to the second', () {
      final image = IconComposer(
        logo,
        const IconDesign(
          backgroundType: IconBackgroundType.gradient,
          colors: [(0, 0, 0), (200, 200, 200)],
          gradientAngle: 90,
        ),
      ).draw(100, 100);
      expect(_pixel(image, 0, 50).$1, lessThan(6));
      expect(_pixel(image, 99, 50).$1, greaterThan(194));
      expect(_pixel(image, 50, 10).$1, _pixel(image, 50, 90).$1);
    });

    test('a mesh has its four colours in the corners', () {
      final image = IconComposer(
        logo,
        const IconDesign(
          backgroundType: IconBackgroundType.mesh,
          colors: [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0)],
        ),
      ).draw(100, 100);
      expect(_pixel(image, 0, 0).$1, greaterThan(250));
      expect(_pixel(image, 99, 0).$2, greaterThan(250));
      expect(_pixel(image, 0, 99).$3, greaterThan(250));
      expect(_pixel(image, 99, 99).$3, lessThan(5));
    });

    test('an image background is cropped, not stretched', () {
      // Left half black, right half white, twice as wide as tall.
      final rgba = Uint8List(40 * 20 * 4);
      for (var y = 0; y < 20; y++) {
        for (var x = 0; x < 40; x++) {
          final i = (y * 40 + x) * 4;
          final value = x < 20 ? 0 : 255;
          rgba.setRange(i, i + 4, [value, value, value, 255]);
        }
      }
      final image = IconComposer(
        logo,
        IconDesign(
          backgroundType: IconBackgroundType.image,
          backgroundImage: RgbaImage(40, 20, rgba),
          colors: const [white],
        ),
      ).draw(100, 100);
      // The middle 20 × 20 of the source fills it: the split stays central.
      expect(_pixel(image, 20, 50).$1, 0);
      expect(_pixel(image, 80, 50).$1, 255);
    });

    test('every texture marks the background, the same way each time', () {
      for (final texture in IconTexture.values) {
        if (texture == IconTexture.none) continue;
        IconDesign design() =>
            IconDesign(texture: texture, colors: const [(40, 80, 160)]);
        final image = IconComposer(logo, design()).draw(128, 128);
        final again = IconComposer(logo, design()).draw(128, 128);
        expect(image.rgba, again.rgba, reason: texture.name);
        final changed = {
          for (var i = 0; i < image.rgba.length; i += 4) image.rgba[i],
        };
        expect(changed.length, greaterThan(1), reason: texture.name);
        for (var i = 3; i < image.rgba.length; i += 4) {
          expect(image.rgba[i], 255, reason: texture.name);
        }
      }
    });
  });

  group('AC-024-4 badge', () {
    test('drawn across the bottom of the logo box', () {
      final band = Uint8List(10 * 2 * 4);
      for (var i = 0; i < band.length; i += 4) {
        band.setRange(i, i + 4, [0, 200, 0, 255]);
      }
      final image = IconComposer(
        _logo(),
        IconDesign(badge: RgbaImage(10, 2, band), colors: const [white]),
      ).draw(100, 100);
      expect(_pixel(image, 50, 90).$2, 200);
      expect(_pixel(image, 50, 79).$2, 255);
    });
  });

  group('AC-024-5 repeatable', () {
    test('the same design draws the same bytes', () {
      IconComposer composer() => IconComposer(
        _logo(),
        const IconDesign(
          trim: true,
          padding: IconPadding(5, 10, 15, 20),
          effect: IconEffect.dropShadow,
          backgroundType: IconBackgroundType.gradient,
          colors: [(1, 2, 3), (200, 100, 50)],
          texture: IconTexture.polka,
        ),
      );
      expect(composer().draw(128, 128).rgba, composer().draw(128, 128).rgba);
    });
  });

  group('layers', () {
    test('the foreground is transparent around the logo', () {
      final layer = IconComposer(
        _logo(side: 16, logo: 16),
        const IconDesign(colors: [white]),
      ).foreground(100, 100, viewport: 0.5);
      expect(_pixel(layer, 50, 50).$4, 255);
      expect(_pixel(layer, 10, 10).$4, 0);
      expect(_box(layer, _isLogo), (25, 25, 74, 74));
    });

    test('a silhouette is white in the shape of the logo', () {
      final shape = IconComposer(
        _logo(),
        const IconDesign(),
      ).silhouette(64, 64)!;
      expect(_pixel(shape, 32, 32), (255, 255, 255, 255));
      expect(_pixel(shape, 2, 2).$4, 0);
    });

    test('an opaque source uses its one-colour border as transparent', () {
      final rgba = Uint8List(16 * 16 * 4);
      for (var i = 0; i < rgba.length; i += 4) {
        rgba.setRange(i, i + 4, [255, 255, 255, 255]);
      }
      for (var y = 6; y < 10; y++) {
        for (var x = 6; x < 10; x++) {
          rgba.setRange((y * 16 + x) * 4, (y * 16 + x) * 4 + 4, [0, 0, 0, 255]);
        }
      }
      final shape = IconComposer(
        RgbaImage(16, 16, rgba),
        const IconDesign(),
      ).silhouette(16, 16)!;
      expect(_pixel(shape, 8, 8).$4, 255);
      expect(_pixel(shape, 1, 1).$4, 0);
    });

    test('no transparency and no border: no silhouette', () {
      final rgba = Uint8List(16 * 16 * 4);
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          final i = (y * 16 + x) * 4;
          rgba.setRange(i, i + 4, [x * 16, y * 16, (x + y) * 8, 255]);
        }
      }
      expect(
        IconComposer(
          RgbaImage(16, 16, rgba),
          const IconDesign(),
        ).silhouette(16, 16),
        isNull,
      );
    });
  });
}
