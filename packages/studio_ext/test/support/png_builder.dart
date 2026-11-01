// studio: 004 — builds PNG files of every colour type, depth, filter and
// interlace mode for the decoder tests.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Raw sample value of [channel] at ([x], [y]), `0 … 2^bitDepth - 1`.
typedef PngSample = int Function(int x, int y, int channel);

/// A PNG of [width] × [height] with the given IHDR fields. Every scanline
/// uses [filter] (0–4); [interlace] writes Adam7 passes.
Uint8List buildPng({
  required int width,
  required int height,
  required int colorType,
  required int bitDepth,
  required PngSample sample,
  List<int>? palette,
  List<int>? transparency,
  int filter = 0,
  bool interlace = false,
  List<String> extraChunks = const [],
}) {
  final channels = switch (colorType) {
    0 || 3 => 1,
    2 => 3,
    4 => 2,
    _ => 4,
  };
  final bitsPerPixel = channels * bitDepth;
  final filterBytes = (bitsPerPixel + 7) ~/ 8;

  List<int> scanlines(List<(int, int)> Function(int row) rowPixels, int rows) {
    final out = <int>[];
    List<int>? previous;
    for (var r = 0; r < rows; r++) {
      final pixels = rowPixels(r);
      final row = Uint8List((pixels.length * bitsPerPixel + 7) ~/ 8);
      var bit = 0;
      for (final (x, y) in pixels) {
        for (var c = 0; c < channels; c++) {
          final value = sample(x, y, c);
          if (bitDepth == 16) {
            row[bit >> 3] = value >> 8;
            row[(bit >> 3) + 1] = value & 0xff;
          } else if (bitDepth == 8) {
            row[bit >> 3] = value;
          } else {
            row[bit >> 3] |= value << (8 - bitDepth - (bit & 7));
          }
          bit += bitDepth;
        }
      }
      final prior = previous ?? Uint8List(row.length);
      out.add(filter);
      for (var i = 0; i < row.length; i++) {
        final a = i >= filterBytes ? row[i - filterBytes] : 0;
        final b = prior[i];
        final c = i >= filterBytes ? prior[i - filterBytes] : 0;
        final predictor = switch (filter) {
          0 => 0,
          1 => a,
          2 => b,
          3 => (a + b) >> 1,
          _ => _paeth(a, b, c),
        };
        out.add((row[i] - predictor) & 0xff);
      }
      previous = row;
    }
    return out;
  }

  final raw = <int>[];
  if (!interlace) {
    raw.addAll(
      scanlines((y) => [for (var x = 0; x < width; x++) (x, y)], height),
    );
  } else {
    const passes = [
      (0, 0, 8, 8),
      (4, 0, 8, 8),
      (0, 4, 4, 8),
      (2, 0, 4, 4),
      (0, 2, 2, 4),
      (1, 0, 2, 2),
      (0, 1, 1, 2),
    ];
    for (final (x0, y0, dx, dy) in passes) {
      final passWidth = (width - x0 + dx - 1) ~/ dx;
      final passHeight = (height - y0 + dy - 1) ~/ dy;
      if (passWidth <= 0 || passHeight <= 0) continue;
      raw.addAll(
        scanlines(
          (r) => [
            for (var i = 0; i < passWidth; i++) (x0 + i * dx, y0 + r * dy),
          ],
          passHeight,
        ),
      );
    }
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, bitDepth)
    ..setUint8(9, colorType)
    ..setUint8(12, interlace ? 1 : 0);
  final out = BytesBuilder()
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> body) {
    final typeBytes = ascii.encode(type);
    out
      ..add((ByteData(4)..setUint32(0, body.length)).buffer.asUint8List())
      ..add(typeBytes)
      ..add(body)
      ..add(
        (ByteData(4)..setUint32(0, getCrc32([...typeBytes, ...body]))).buffer
            .asUint8List(),
      );
  }

  chunk('IHDR', header.buffer.asUint8List());
  for (final extra in extraChunks) {
    chunk(extra, const []);
  }
  if (palette != null) chunk('PLTE', palette);
  if (transparency != null) chunk('tRNS', transparency);
  final compressed = const ZLibEncoder().encodeBytes(raw);
  // Split IDAT in two to exercise multi-chunk image data.
  final half = compressed.length ~/ 2;
  chunk('IDAT', compressed.sublist(0, half));
  chunk('IDAT', compressed.sublist(half));
  chunk('IEND', const []);
  return out.toBytes();
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

/// A solid RGBA8 PNG.
Uint8List solidPng(int width, int height, (int, int, int, int) rgba) =>
    buildPng(
      width: width,
      height: height,
      colorType: 6,
      bitDepth: 8,
      sample: (x, y, c) => switch (c) {
        0 => rgba.$1,
        1 => rgba.$2,
        2 => rgba.$3,
        _ => rgba.$4,
      },
    );

/// An RGBA8 gradient PNG (every pixel differs).
Uint8List gradientPng(int width, int height) => buildPng(
  width: width,
  height: height,
  colorType: 6,
  bitDepth: 8,
  filter: 4,
  sample: (x, y, c) => switch (c) {
    0 => x * 255 ~/ (width > 1 ? width - 1 : 1),
    1 => y * 255 ~/ (height > 1 ? height - 1 : 1),
    2 => (x + y) & 0xff,
    _ => 255,
  },
);
