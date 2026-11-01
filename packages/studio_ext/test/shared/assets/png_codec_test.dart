// studio: 004 — PNG decoding for asset catalog images.
import 'dart:typed_data';

import 'package:studio_ext/src/shared/assets/png_codec.dart';
import 'package:test/test.dart';

import '../../support/png_builder.dart';

List<int> _pixel(RgbaImage image, int x, int y) {
  final i = (y * image.width + x) * 4;
  return image.rgba.sublist(i, i + 4);
}

void main() {
  test('AC-004-1 RGBA8 with every filter type', () {
    for (var filter = 0; filter <= 4; filter++) {
      final image = PngDecoder.decode(
        buildPng(
          width: 7,
          height: 5,
          colorType: 6,
          bitDepth: 8,
          filter: filter,
          sample: (x, y, c) => (x * 31 + y * 17 + c * 53) & 0xff,
        ),
      );
      expect(image.width, 7, reason: 'filter $filter');
      for (var y = 0; y < 5; y++) {
        for (var x = 0; x < 7; x++) {
          expect(_pixel(image, x, y), [
            for (var c = 0; c < 4; c++) (x * 31 + y * 17 + c * 53) & 0xff,
          ], reason: 'filter $filter at $x,$y');
        }
      }
    }
  });

  test('RGB8 and RGB16 are opaque; 16-bit keeps the high byte', () {
    final rgb = PngDecoder.decode(
      buildPng(
        width: 3,
        height: 2,
        colorType: 2,
        bitDepth: 8,
        filter: 1,
        sample: (x, y, c) => [10, 20, 30][c] + x,
      ),
    );
    expect(_pixel(rgb, 2, 1), [12, 22, 32, 255]);
    final deep = PngDecoder.decode(
      buildPng(
        width: 2,
        height: 2,
        colorType: 6,
        bitDepth: 16,
        filter: 3,
        sample: (x, y, c) => 0x1234 * (c + 1),
      ),
    );
    expect(_pixel(deep, 1, 1), [0x12, 0x24, 0x36, 0x48]);
  });

  test('palette with tRNS, and sub-byte palette indexes', () {
    final image = PngDecoder.decode(
      buildPng(
        width: 5,
        height: 1,
        colorType: 3,
        bitDepth: 2,
        palette: [255, 0, 0, 0, 255, 0, 0, 0, 255, 9, 9, 9],
        transparency: [255, 128],
        sample: (x, y, c) => x % 4,
      ),
    );
    expect(_pixel(image, 0, 0), [255, 0, 0, 255]);
    expect(_pixel(image, 1, 0), [0, 255, 0, 128]);
    expect(_pixel(image, 2, 0), [0, 0, 255, 255]);
    expect(_pixel(image, 3, 0), [9, 9, 9, 255]);
    expect(_pixel(image, 4, 0), [255, 0, 0, 255]);
  });

  test('greyscale 1-bit, 8-bit with a tRNS key, and grey + alpha', () {
    final bits = PngDecoder.decode(
      buildPng(
        width: 9,
        height: 1,
        colorType: 0,
        bitDepth: 1,
        sample: (x, y, c) => x.isEven ? 1 : 0,
      ),
    );
    expect(_pixel(bits, 0, 0), [255, 255, 255, 255]);
    expect(_pixel(bits, 1, 0), [0, 0, 0, 255]);
    expect(_pixel(bits, 8, 0), [255, 255, 255, 255]);

    final keyed = PngDecoder.decode(
      buildPng(
        width: 2,
        height: 1,
        colorType: 0,
        bitDepth: 8,
        transparency: [0, 7],
        sample: (x, y, c) => x == 0 ? 7 : 8,
      ),
    );
    expect(_pixel(keyed, 0, 0), [7, 7, 7, 0]);
    expect(_pixel(keyed, 1, 0), [8, 8, 8, 255]);

    final greyAlpha = PngDecoder.decode(
      buildPng(
        width: 1,
        height: 1,
        colorType: 4,
        bitDepth: 8,
        sample: (x, y, c) => c == 0 ? 100 : 50,
      ),
    );
    expect(_pixel(greyAlpha, 0, 0), [100, 100, 100, 50]);
  });

  test('Adam7 interlacing (odd sizes, all passes)', () {
    int value(int x, int y, int c) => (x * 13 + y * 7 + c * 29) & 0xff;
    final image = PngDecoder.decode(
      buildPng(
        width: 11,
        height: 9,
        colorType: 6,
        bitDepth: 8,
        filter: 4,
        interlace: true,
        sample: value,
      ),
    );
    for (var y = 0; y < 9; y++) {
      for (var x = 0; x < 11; x++) {
        expect(_pixel(image, x, y), [
          for (var c = 0; c < 4; c++) value(x, y, c),
        ]);
      }
    }
  });

  test('premultiplied BGRA, uniform colour, resize and the encoder', () {
    final image = PngDecoder.decode(solidPng(4, 4, (200, 100, 50, 128)));
    expect(image.toPremultipliedBgra().sublist(0, 4), [25, 50, 100, 128]);
    expect(image.uniformColor, (200, 100, 50, 128));
    expect(PngDecoder.decode(gradientPng(4, 4)).uniformColor, isNull);

    final small = image.resized(2, 2);
    expect(small.uniformColor, (200, 100, 50, 128));
    final gradient = PngDecoder.decode(gradientPng(64, 64)).resized(16, 16);
    expect(gradient.width, 16);
    final roundTrip = PngDecoder.decode(PngEncoder.encode(gradient));
    expect(roundTrip.rgba, gradient.rgba);
  });

  test('AC-004-3 broken input is a FormatException', () {
    expect(
      () => PngDecoder.decode(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    expect(
      () => PngDecoder.decode(
        buildPng(
          width: 1,
          height: 1,
          colorType: 6,
          bitDepth: 8,
          sample: (x, y, c) => 0,
          extraChunks: ['CgBI'],
        ),
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('CgBI'),
        ),
      ),
    );
    final truncated = solidPng(8, 8, (1, 2, 3, 4));
    expect(
      () => PngDecoder.decode(Uint8List.sublistView(truncated, 0, 40)),
      throwsFormatException,
    );
  });

  test('JPEG dimensions come from the SOF marker', () {
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8, // SOI
      0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00, // APP0, 2-byte payload
      0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x5A, 0x00, 0x78, 0x03, 0, 0, 0,
    ]);
    expect(JpegDimensions.read(jpeg), (120, 90));
    expect(
      () => JpegDimensions.read(Uint8List.fromList([0, 1, 2, 3])),
      throwsFormatException,
    );
  });
}
