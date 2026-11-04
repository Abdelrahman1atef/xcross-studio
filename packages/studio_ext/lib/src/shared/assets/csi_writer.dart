// studio: 004 — ported from xtool-org/AssetKit (MIT, see
// packages/studio_ext/THIRD_PARTY_NOTICES.md): CAR/CSIHeader.swift,
// CAR/CSIWriter.swift, CAR/TVLEntry.swift, CAR/MLECBody.swift,
// CAR/DWAREnvelope.swift.
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/assets/asset_byte_writer.dart';
import 'package:studio_ext/src/shared/assets/rendition.dart';

/// Builds the per-rendition CSI ("CTSI") record: a 184-byte header, the TVL
/// metadata block and the body.
@internal
abstract final class CsiWriter {
  static const headerLength = 184;

  /// `'CTSI'` as a little-endian multi-char constant (bytes `I,S,T,C`).
  static const tag = 0x43545349;

  /// `'ARGB'` LE (bytes `B,G,R,A`): BGRA pixels in memory order.
  static const pixelFormatArgb = 0x41524742;

  /// `'JPEG'` LE (bytes `G,E,P,J`).
  static const pixelFormatJpeg = 0x4A504547;

  static const layoutBitmap = 12;
  static const layoutNamedColor = 1009;

  /// Bit 4: generic-image category (`.imageset`); cleared for app icons.
  static const flagImage = 0x10;

  /// Bit 3: every pixel is opaque.
  static const flagOpaque = 0x08;

  static Uint8List bitmap(BitmapBody body, {required int scaleFactor}) {
    final tvl = AssetByteWriter();
    TvlEntries.bitmapDescriptor(tvl, body.width, body.height);
    TvlEntries.destinationRect(tvl, body.width, body.height);
    TvlEntries.sliceScale(tvl);
    TvlEntries.bitmapFlag(tvl);
    TvlEntries.bytesPerRow(tvl, body.width);
    final tvlBytes = tvl.toBytes();
    final payload = MlecBody.encode(
      width: body.width,
      height: body.height,
      pixelsBgra: body.pixelsBgra,
    );
    return (AssetByteWriter()
          ..bytes(
            header(
              renditionFlags:
                  (body.kind == BitmapKind.image ? flagImage : 0) |
                  (body.opaque ? flagOpaque : 0),
              width: body.width,
              height: body.height,
              scaleFactor: scaleFactor,
              pixelFormat: pixelFormatArgb,
              colorSpace: body.colorSpaceId,
              layout: layoutBitmap,
              name: body.renditionName,
              tvlLength: tvlBytes.length,
              bitmapCount: 1,
              renditionLength: payload.length,
            ),
          )
          ..bytes(tvlBytes)
          ..bytes(payload))
        .toBytes();
  }

  /// A JPEG passed through in a DWAR envelope (flags 0). The CSI header
  /// carries zero dimensions; the decoded size lives in TVL 1001 and 1003,
  /// and there is no bytes-per-row entry.
  static Uint8List jpeg(JpegBody body, {required int scaleFactor}) {
    final tvl = AssetByteWriter();
    TvlEntries.bitmapDescriptor(tvl, body.width, body.height);
    TvlEntries.destinationRect(tvl, body.width, body.height);
    TvlEntries.sliceScale(tvl);
    TvlEntries.bitmapFlag(tvl);
    final tvlBytes = tvl.toBytes();
    final envelope = DwarEnvelope.encode(flags: 0, payload: body.source);
    return (AssetByteWriter()
          ..bytes(
            header(
              renditionFlags: flagImage,
              width: 0,
              height: 0,
              scaleFactor: scaleFactor,
              pixelFormat: pixelFormatJpeg,
              colorSpace: 0,
              layout: layoutBitmap,
              name: body.renditionName,
              tvlLength: tvlBytes.length,
              bitmapCount: 1,
              renditionLength: envelope.length,
            ),
          )
          ..bytes(tvlBytes)
          ..bytes(envelope))
        .toBytes();
  }

  /// A named colour: header plus a `COLR` body with four IEEE-754 doubles.
  static Uint8List color(String name, ColorBody body) {
    final payload = AssetByteWriter()
      ..fourCC('COLR')
      ..u32le(0)
      ..u32le(body.colorSpaceId)
      ..u32le(4);
    for (final component in [body.red, body.green, body.blue, body.alpha]) {
      payload.f64le(component);
    }
    final payloadBytes = payload.toBytes();
    return (AssetByteWriter()
          ..bytes(
            header(
              renditionFlags: 0,
              width: 0,
              height: 0,
              scaleFactor: 100,
              pixelFormat: 0,
              colorSpace: body.colorSpaceId,
              layout: layoutNamedColor,
              name: name,
              tvlLength: 0,
              bitmapCount: 0,
              renditionLength: payloadBytes.length,
            ),
          )
          ..bytes(payloadBytes))
        .toBytes();
  }

  /// The fixed 184-byte CSI header.
  static Uint8List header({
    required int renditionFlags,
    required int width,
    required int height,
    required int scaleFactor,
    required int pixelFormat,
    required int colorSpace,
    required int layout,
    required String name,
    required int tvlLength,
    required int bitmapCount,
    required int renditionLength,
  }) {
    final writer = AssetByteWriter()
      ..u32le(tag)
      ..u32le(1) // version
      ..u32le(renditionFlags)
      ..u32le(width)
      ..u32le(height)
      ..u32le(scaleFactor)
      ..u32le(pixelFormat)
      ..u32le(colorSpace)
      ..u32le(0) // modification time (the reference writes 0)
      ..u16le(layout)
      ..u16le(0)
      ..padded(name, 128)
      ..u32le(tvlLength)
      ..u32le(bitmapCount)
      ..u32le(0) // reserved
      ..u32le(renditionLength);
    assert(writer.length == headerLength, 'CSI header is $headerLength bytes');
    return writer.toBytes();
  }
}

/// The TVL (type, length, value) entries between the CSI header and body.
@internal
abstract final class TvlEntries {
  /// 1001: `(1, 0, 0, width, height)`.
  static void bitmapDescriptor(AssetByteWriter w, int width, int height) => w
    ..u32le(1001)
    ..u32le(20)
    ..u32le(1)
    ..u32le(0)
    ..u32le(0)
    ..u32le(width)
    ..u32le(height);

  /// 1003: destination rect `(1, 0, 0, 0, 0, width, height)`.
  static void destinationRect(AssetByteWriter w, int width, int height) => w
    ..u32le(1003)
    ..u32le(28)
    ..u32le(1)
    ..u32le(0)
    ..u32le(0)
    ..u32le(0)
    ..u32le(0)
    ..u32le(width)
    ..u32le(height);

  /// 1004: slice/scale pair `(0, 1.0f)`.
  static void sliceScale(AssetByteWriter w) => w
    ..u32le(1004)
    ..u32le(8)
    ..u32le(0)
    ..f32le(1);

  /// 1006: always 1 in the reference.
  static void bitmapFlag(AssetByteWriter w) => w
    ..u32le(1006)
    ..u32le(4)
    ..u32le(1);

  /// 1007: bytes per row of the stored pixels.
  ///
  /// AssetKit writes `width * 4` rounded up to 16 while storing unpadded
  /// rows; the two only agree when `width % 4 == 0` (the sizes its
  /// reference covers). This port writes the real stride, `width * 4`, so
  /// the value and the data agree for every width (icon sizes such as 29,
  /// 58, 87 or 167 pixels).
  static void bytesPerRow(AssetByteWriter w, int width) => w
    ..u32le(1007)
    ..u32le(4)
    ..u32le(width * 4);
}

/// `MLEC` bitmap payload: compression type, bytes per pixel, chunk count,
/// then `KCBC` chunks (8 reserved bytes, rows, payload size, payload).
///
/// AssetKit compresses each chunk with Apple's LZFSE encoder (type 3).
/// This port keeps type 3 but stores each chunk as an LZFSE *uncompressed
/// block* (`bvx-`), the frame Apple's own encoder falls back to for
/// incompressible input, which every LZFSE decoder reads. The catalog is
/// larger than actool's, never different in pixels.
@internal
abstract final class MlecBody {
  static const compressionLzfse = 3;

  static Uint8List encode({
    required int width,
    required int height,
    required Uint8List pixelsBgra,
  }) {
    final bytesPerRow = width * 4;
    // actool splits into three equal chunks when the height allows.
    final chunkCount = height % 3 == 0 && height > 0 ? 3 : 1;
    final rowsPerChunk = height ~/ chunkCount;
    final writer = AssetByteWriter()
      ..fourCC('MLEC')
      ..u32le(compressionLzfse)
      ..u32le(4)
      ..u32le(chunkCount);
    for (var i = 0; i < chunkCount; i++) {
      final start = i * rowsPerChunk * bytesPerRow;
      final payload = LzfseStoredFrame.encode(
        Uint8List.sublistView(
          pixelsBgra,
          start,
          start + rowsPerChunk * bytesPerRow,
        ),
      );
      writer
        ..fourCC('KCBC')
        ..zeros(8)
        ..u32le(rowsPerChunk)
        ..u32le(payload.length)
        ..bytes(payload);
    }
    return writer.toBytes();
  }
}

/// An LZFSE stream made of one uncompressed block: `bvx-`, the raw length
/// (`u32` LE), the raw bytes, then the `bvx$` end-of-stream marker
/// (`lzfse_encode.c`, `try_uncompressed`).
@internal
abstract final class LzfseStoredFrame {
  static const uncompressedBlockMagic = 0x2d787662; // bvx-
  static const endOfStreamMagic = 0x24787662; // bvx$

  static Uint8List encode(List<int> raw) =>
      (AssetByteWriter()
            ..u32le(uncompressedBlockMagic)
            ..u32le(raw.length)
            ..bytes(raw)
            ..u32le(endOfStreamMagic))
          .toBytes();
}

/// 12-byte `DWAR` envelope (character order on disk), flags, length.
@internal
abstract final class DwarEnvelope {
  static Uint8List encode({required int flags, required List<int> payload}) =>
      (AssetByteWriter()
            ..fourCC('DWAR')
            ..u32le(flags)
            ..u32le(payload.length)
            ..bytes(payload))
          .toBytes();
}
