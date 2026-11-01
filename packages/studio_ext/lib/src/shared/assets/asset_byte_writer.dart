// studio: 004 — ported from xtool-org/AssetKit (MIT, see
// packages/studio_ext/THIRD_PARTY_NOTICES.md): BOM/ByteWriter.swift.
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Append-only byte writer with explicit endianness, used for every block
/// of an `Assets.car`.
@internal
final class AssetByteWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  int get length => _builder.length;

  /// Appends [value] as is. The list must not be modified afterwards.
  void bytes(List<int> value) => _builder.add(value);

  void byte(int value) => _builder.addByte(value & 0xff);

  void zeros(int count) {
    if (count > 0) _builder.add(Uint8List(count));
  }

  void u16le(int value) {
    byte(value);
    byte(value >> 8);
  }

  void u32le(int value) {
    byte(value);
    byte(value >> 8);
    byte(value >> 16);
    byte(value >> 24);
  }

  void u16be(int value) {
    byte(value >> 8);
    byte(value);
  }

  void u32be(int value) {
    byte(value >> 24);
    byte(value >> 16);
    byte(value >> 8);
    byte(value);
  }

  void f32le(double value) {
    final data = ByteData(4)..setFloat32(0, value, Endian.little);
    bytes(data.buffer.asUint8List());
  }

  void f64le(double value) {
    final data = ByteData(8)..setFloat64(0, value, Endian.little);
    bytes(data.buffer.asUint8List());
  }

  /// Four ASCII characters in character order (`MLEC`, `KCBC`, `META`, …).
  void fourCC(String value) {
    final encoded = ascii.encode(value);
    if (encoded.length != 4) {
      throw ArgumentError.value(value, 'value', 'must be 4 ASCII characters');
    }
    bytes(encoded);
  }

  /// [value] as UTF-8, truncated or zero-padded to exactly [length] bytes.
  void padded(String value, int length) {
    final encoded = utf8.encode(value);
    final kept = encoded.length > length ? encoded.sublist(0, length) : encoded;
    bytes(kept);
    zeros(length - kept.length);
  }

  Uint8List toBytes() => _builder.toBytes();
}
