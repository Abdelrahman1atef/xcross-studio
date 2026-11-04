// studio: 004 — PNG decoding for the asset catalog compiler (AssetKit uses
// swift-png; this is a small pure-Dart equivalent).
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/assets/asset_byte_writer.dart';

/// An image as straight (non-premultiplied) 8-bit RGBA, row-major.
@internal
final class RgbaImage {
  RgbaImage(this.width, this.height, this.rgba)
    : assert(rgba.length == width * height * 4, 'RGBA size mismatch');

  final int width;
  final int height;
  final Uint8List rgba;

  /// BGRA with premultiplied alpha, CoreUI's `ARGB` pixel format.
  Uint8List toPremultipliedBgra() {
    final out = Uint8List(rgba.length);
    for (var i = 0; i < rgba.length; i += 4) {
      final a = rgba[i + 3];
      out[i] = (rgba[i + 2] * a + 127) ~/ 255;
      out[i + 1] = (rgba[i + 1] * a + 127) ~/ 255;
      out[i + 2] = (rgba[i] * a + 127) ~/ 255;
      out[i + 3] = a;
    }
    return out;
  }

  /// Whether no pixel has any transparency.
  bool get isOpaque {
    for (var i = 3; i < rgba.length; i += 4) {
      if (rgba[i] != 255) return false;
    }
    return true;
  }

  /// This image drawn over the colour [red], [green], [blue] (0…255), leaving
  /// no pixel with any transparency.
  RgbaImage flattenedOver(int red, int green, int blue) {
    final out = Uint8List(rgba.length);
    for (var i = 0; i < rgba.length; i += 4) {
      final a = rgba[i + 3];
      final under = 255 - a;
      out[i] = (rgba[i] * a + red * under + 127) ~/ 255;
      out[i + 1] = (rgba[i + 1] * a + green * under + 127) ~/ 255;
      out[i + 2] = (rgba[i + 2] * a + blue * under + 127) ~/ 255;
      out[i + 3] = 255;
    }
    return RgbaImage(width, height, out);
  }

  /// The single colour of the image, or `null` when pixels differ.
  (int, int, int, int)? get uniformColor {
    if (rgba.isEmpty) return null;
    for (var i = 4; i < rgba.length; i += 4) {
      for (var c = 0; c < 4; c++) {
        if (rgba[i + c] != rgba[c]) return null;
      }
    }
    return (rgba[0], rgba[1], rgba[2], rgba[3]);
  }

  /// Box-filter resize to [newWidth] × [newHeight] (alpha-weighted, so
  /// transparent pixels do not darken edges).
  RgbaImage resized(int newWidth, int newHeight) {
    if (newWidth == width && newHeight == height) return this;
    final out = Uint8List(newWidth * newHeight * 4);
    for (var y = 0; y < newHeight; y++) {
      final y0 = y * height / newHeight;
      final y1 = (y + 1) * height / newHeight;
      for (var x = 0; x < newWidth; x++) {
        final x0 = x * width / newWidth;
        final x1 = (x + 1) * width / newWidth;
        var r = 0.0;
        var g = 0.0;
        var b = 0.0;
        var a = 0.0;
        var area = 0.0;
        for (var sy = y0.floor(); sy < y1.ceil() && sy < height; sy++) {
          final wy = _overlap(sy, y0, y1);
          for (var sx = x0.floor(); sx < x1.ceil() && sx < width; sx++) {
            final weight = wy * _overlap(sx, x0, x1);
            final i = (sy * width + sx) * 4;
            final alpha = rgba[i + 3] * weight;
            r += rgba[i] * alpha;
            g += rgba[i + 1] * alpha;
            b += rgba[i + 2] * alpha;
            a += alpha;
            area += weight;
          }
        }
        final o = (y * newWidth + x) * 4;
        if (a > 0) {
          out[o] = (r / a).round().clamp(0, 255);
          out[o + 1] = (g / a).round().clamp(0, 255);
          out[o + 2] = (b / a).round().clamp(0, 255);
        }
        out[o + 3] = area > 0 ? (a / area).round().clamp(0, 255) : 0;
      }
    }
    return RgbaImage(newWidth, newHeight, out);
  }

  static double _overlap(int pixel, double start, double end) {
    final from = pixel < start ? start : pixel.toDouble();
    final to = pixel + 1 > end ? end : pixel + 1.0;
    return to > from ? to - from : 0;
  }
}

/// Decodes PNG files: colour types 0, 2, 3, 4 and 6, bit depths 1–16,
/// filters 0–4 and Adam7 interlacing. Throws [FormatException].
@internal
abstract final class PngDecoder {
  static const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  static bool isPng(List<int> bytes) {
    if (bytes.length < 8) return false;
    for (var i = 0; i < 8; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    return true;
  }

  static RgbaImage decode(Uint8List bytes) {
    if (!isPng(bytes)) throw const FormatException('not a PNG file');
    final data = ByteData.sublistView(bytes);
    var offset = 8;
    int? width;
    int? height;
    int? bitDepth;
    int? colorType;
    int? interlace;
    Uint8List? palette;
    Uint8List? transparency;
    final idat = BytesBuilder(copy: false);
    var ended = false;
    while (offset + 8 <= bytes.length && !ended) {
      final length = data.getUint32(offset);
      final type = ascii.decode(
        bytes.sublist(offset + 4, offset + 8),
        allowInvalid: true,
      );
      final start = offset + 8;
      if (start + length + 4 > bytes.length) {
        throw const FormatException('truncated PNG chunk');
      }
      final body = Uint8List.sublistView(bytes, start, start + length);
      switch (type) {
        case 'IHDR':
          if (length < 13) throw const FormatException('short IHDR');
          final header = ByteData.sublistView(body);
          width = header.getUint32(0);
          height = header.getUint32(4);
          bitDepth = body[8];
          colorType = body[9];
          if (body[10] != 0 || body[11] != 0) {
            throw const FormatException('unknown PNG compression or filter');
          }
          interlace = body[12];
        case 'PLTE':
          palette = body;
        case 'tRNS':
          transparency = body;
        case 'IDAT':
          idat.add(body);
        case 'CgBI':
          throw const FormatException(
            'Apple-optimised (CgBI) PNG; use the original image',
          );
        case 'IEND':
          ended = true;
      }
      offset = start + length + 4;
    }
    if (width == null ||
        height == null ||
        bitDepth == null ||
        colorType == null ||
        interlace == null) {
      throw const FormatException('PNG has no IHDR');
    }
    if (width == 0 || height == 0 || width > 16384 || height > 16384) {
      throw FormatException('unsupported PNG size ${width}x$height');
    }
    final channels = switch (colorType) {
      0 => 1,
      2 => 3,
      3 => 1,
      4 => 2,
      6 => 4,
      _ => throw FormatException('unknown PNG colour type $colorType'),
    };
    const validDepths = {
      0: [1, 2, 4, 8, 16],
      2: [8, 16],
      3: [1, 2, 4, 8],
      4: [8, 16],
      6: [8, 16],
    };
    if (!validDepths[colorType]!.contains(bitDepth)) {
      throw FormatException(
        'invalid bit depth $bitDepth for colour type $colorType',
      );
    }
    if (colorType == 3 && palette == null) {
      throw const FormatException('indexed PNG without a palette');
    }
    final Uint8List raw;
    try {
      raw = const ZLibDecoder().decodeBytes(idat.toBytes());
      // The inflater reports corrupt streams with assorted error types.
    } on Object catch (error) {
      throw FormatException('corrupt PNG image data ($error)');
    }
    final decoder = PngPixelUnpacker(
      width: width,
      height: height,
      bitDepth: bitDepth,
      colorType: colorType,
      channels: channels,
      palette: palette,
      transparency: transparency,
    );
    return RgbaImage(
      width,
      height,
      interlace == 1 ? decoder.adam7(raw) : decoder.progressive(raw),
    );
  }
}

/// Unfilters scanlines and expands samples to RGBA8.
@internal
final class PngPixelUnpacker {
  PngPixelUnpacker({
    required this.width,
    required this.height,
    required this.bitDepth,
    required this.colorType,
    required this.channels,
    required this.palette,
    required this.transparency,
  });

  final int width;
  final int height;
  final int bitDepth;
  final int colorType;
  final int channels;
  final Uint8List? palette;
  final Uint8List? transparency;

  int get _bitsPerPixel => bitDepth * channels;
  int get _filterBytes => (_bitsPerPixel + 7) ~/ 8;
  int _rowBytes(int pixels) => (pixels * _bitsPerPixel + 7) ~/ 8;

  Uint8List progressive(Uint8List raw) {
    final out = Uint8List(width * height * 4);
    _pass(raw, 0, width, height, (x, y) => (y * width + x) * 4, out);
    return out;
  }

  Uint8List adam7(Uint8List raw) {
    const passes = [
      (0, 0, 8, 8),
      (4, 0, 8, 8),
      (0, 4, 4, 8),
      (2, 0, 4, 4),
      (0, 2, 2, 4),
      (1, 0, 2, 2),
      (0, 1, 1, 2),
    ];
    final out = Uint8List(width * height * 4);
    var offset = 0;
    for (final (x0, y0, dx, dy) in passes) {
      final passWidth = (width - x0 + dx - 1) ~/ dx;
      final passHeight = (height - y0 + dy - 1) ~/ dy;
      if (passWidth <= 0 || passHeight <= 0) continue;
      offset = _pass(
        raw,
        offset,
        passWidth,
        passHeight,
        (x, y) => ((y0 + y * dy) * width + x0 + x * dx) * 4,
        out,
      );
    }
    return out;
  }

  /// Decodes one (sub)image starting at [offset]; returns the end offset.
  int _pass(
    Uint8List raw,
    int offset,
    int passWidth,
    int passHeight,
    int Function(int x, int y) target,
    Uint8List out,
  ) {
    final rowBytes = _rowBytes(passWidth);
    var previous = Uint8List(rowBytes);
    var cursor = offset;
    for (var y = 0; y < passHeight; y++) {
      if (cursor + 1 + rowBytes > raw.length) {
        throw const FormatException('PNG image data too short');
      }
      final filter = raw[cursor];
      final row = Uint8List.fromList(
        Uint8List.sublistView(raw, cursor + 1, cursor + 1 + rowBytes),
      );
      _unfilter(filter, row, previous);
      for (var x = 0; x < passWidth; x++) {
        _writePixel(row, x, out, target(x, y));
      }
      previous = row;
      cursor += 1 + rowBytes;
    }
    return cursor;
  }

  void _unfilter(int filter, Uint8List row, Uint8List previous) {
    final bpp = _filterBytes;
    switch (filter) {
      case 0:
        return;
      case 1:
        for (var i = bpp; i < row.length; i++) {
          row[i] = (row[i] + row[i - bpp]) & 0xff;
        }
      case 2:
        for (var i = 0; i < row.length; i++) {
          row[i] = (row[i] + previous[i]) & 0xff;
        }
      case 3:
        for (var i = 0; i < row.length; i++) {
          final left = i >= bpp ? row[i - bpp] : 0;
          row[i] = (row[i] + ((left + previous[i]) >> 1)) & 0xff;
        }
      case 4:
        for (var i = 0; i < row.length; i++) {
          final a = i >= bpp ? row[i - bpp] : 0;
          final b = previous[i];
          final c = i >= bpp ? previous[i - bpp] : 0;
          final p = a + b - c;
          final pa = (p - a).abs();
          final pb = (p - b).abs();
          final pc = (p - c).abs();
          final predictor = pa <= pb && pa <= pc
              ? a
              : pb <= pc
              ? b
              : c;
          row[i] = (row[i] + predictor) & 0xff;
        }
      default:
        throw FormatException('unknown PNG filter type $filter');
    }
  }

  /// Sample [channel] of pixel [x], scaled to 0–255; with [raw16] the full
  /// 16-bit value (used for tRNS comparisons).
  int _sample(Uint8List row, int x, int channel, {bool raw16 = false}) {
    if (bitDepth == 16) {
      final i = (x * channels + channel) * 2;
      final value = row[i] << 8 | row[i + 1];
      return raw16 ? value : value >> 8;
    }
    if (bitDepth == 8) return row[x * channels + channel];
    final bitIndex = (x * channels + channel) * bitDepth;
    final byte = row[bitIndex >> 3];
    final shift = 8 - bitDepth - (bitIndex & 7);
    final value = (byte >> shift) & ((1 << bitDepth) - 1);
    if (raw16 || colorType == 3) return value;
    return value * 255 ~/ ((1 << bitDepth) - 1);
  }

  bool _transparentKey(Uint8List row, int x) {
    final key = transparency;
    if (key == null) return false;
    final keyData = ByteData.sublistView(key);
    int keyAt(int index) => keyData.getUint16(index * 2);
    if (colorType == 0 && key.length >= 2) {
      return _sample(row, x, 0, raw16: true) == keyAt(0);
    }
    if (colorType == 2 && key.length >= 6) {
      return _sample(row, x, 0, raw16: true) == keyAt(0) &&
          _sample(row, x, 1, raw16: true) == keyAt(1) &&
          _sample(row, x, 2, raw16: true) == keyAt(2);
    }
    return false;
  }

  void _writePixel(Uint8List row, int x, Uint8List out, int o) {
    switch (colorType) {
      case 0:
        final v = _sample(row, x, 0);
        out
          ..[o] = v
          ..[o + 1] = v
          ..[o + 2] = v
          ..[o + 3] = _transparentKey(row, x) ? 0 : 255;
      case 2:
        out
          ..[o] = _sample(row, x, 0)
          ..[o + 1] = _sample(row, x, 1)
          ..[o + 2] = _sample(row, x, 2)
          ..[o + 3] = _transparentKey(row, x) ? 0 : 255;
      case 3:
        final index = _sample(row, x, 0);
        final colors = palette!;
        if (index * 3 + 2 >= colors.length) {
          throw const FormatException('palette index out of range');
        }
        final alpha = transparency;
        out
          ..[o] = colors[index * 3]
          ..[o + 1] = colors[index * 3 + 1]
          ..[o + 2] = colors[index * 3 + 2]
          ..[o + 3] = alpha != null && index < alpha.length
              ? alpha[index]
              : 255;
      case 4:
        final v = _sample(row, x, 0);
        out
          ..[o] = v
          ..[o + 1] = v
          ..[o + 2] = v
          ..[o + 3] = _sample(row, x, 1);
      case 6:
        out
          ..[o] = _sample(row, x, 0)
          ..[o + 1] = _sample(row, x, 1)
          ..[o + 2] = _sample(row, x, 2)
          ..[o + 3] = _sample(row, x, 3);
    }
  }
}

/// Writes 8-bit RGBA PNGs (no filtering, zlib-compressed), for app icon
/// sizes generated from a single 1024-pixel source.
@internal
abstract final class PngEncoder {
  static Uint8List encode(RgbaImage image) {
    final rowBytes = image.width * 4;
    final raw = Uint8List(image.height * (rowBytes + 1));
    for (var y = 0; y < image.height; y++) {
      raw.setRange(
        y * (rowBytes + 1) + 1,
        (y + 1) * (rowBytes + 1),
        image.rgba,
        y * rowBytes,
      );
    }
    final header = AssetByteWriter()
      ..u32be(image.width)
      ..u32be(image.height)
      ..byte(8)
      ..byte(6)
      ..byte(0)
      ..byte(0)
      ..byte(0);
    final writer = AssetByteWriter()..bytes(PngDecoder.signature);
    _chunk(writer, 'IHDR', header.toBytes());
    _chunk(writer, 'IDAT', const ZLibEncoder().encodeBytes(raw));
    _chunk(writer, 'IEND', Uint8List(0));
    return writer.toBytes();
  }

  // studio: 023 — app icons for the App Store carry no alpha channel
  // (ITMS-90717); alpha is dropped, so flatten the image first.
  /// Writes [image] as an 8-bit RGB PNG (colour type 2), without alpha.
  static Uint8List encodeOpaque(RgbaImage image) {
    final rowBytes = image.width * 3;
    final raw = Uint8List(image.height * (rowBytes + 1));
    for (var y = 0; y < image.height; y++) {
      var o = y * (rowBytes + 1) + 1;
      var i = y * image.width * 4;
      for (var x = 0; x < image.width; x++, i += 4) {
        raw[o++] = image.rgba[i];
        raw[o++] = image.rgba[i + 1];
        raw[o++] = image.rgba[i + 2];
      }
    }
    final header = AssetByteWriter()
      ..u32be(image.width)
      ..u32be(image.height)
      ..byte(8)
      ..byte(2)
      ..byte(0)
      ..byte(0)
      ..byte(0);
    final writer = AssetByteWriter()..bytes(PngDecoder.signature);
    _chunk(writer, 'IHDR', header.toBytes());
    _chunk(writer, 'IDAT', const ZLibEncoder().encodeBytes(raw));
    _chunk(writer, 'IEND', Uint8List(0));
    return writer.toBytes();
  }

  static void _chunk(AssetByteWriter writer, String type, Uint8List body) {
    final typeBytes = ascii.encode(type);
    writer
      ..u32be(body.length)
      ..bytes(typeBytes)
      ..bytes(body)
      ..u32be(getCrc32([...typeBytes, ...body]));
  }
}

/// Reads a JPEG's pixel size from its SOF0/1/2 marker.
@internal
abstract final class JpegDimensions {
  static (int, int) read(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      throw const FormatException('missing JPEG SOI marker');
    }
    var i = 2;
    while (i < bytes.length) {
      while (i < bytes.length && bytes[i] != 0xFF) {
        i++;
      }
      while (i < bytes.length && bytes[i] == 0xFF) {
        i++;
      }
      if (i >= bytes.length) break;
      final marker = bytes[i++];
      if (marker == 0xD8 ||
          marker == 0xD9 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        continue;
      }
      if (i + 2 > bytes.length) {
        throw const FormatException('truncated JPEG segment');
      }
      final length = bytes[i] << 8 | bytes[i + 1];
      if (length < 2 || i + length > bytes.length) {
        throw const FormatException('JPEG segment overruns the file');
      }
      if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
        if (length < 7) throw const FormatException('short JPEG SOF');
        final height = bytes[i + 3] << 8 | bytes[i + 4];
        final width = bytes[i + 5] << 8 | bytes[i + 6];
        return (width, height);
      }
      i += length;
    }
    throw const FormatException('no JPEG SOF marker');
  }
}
