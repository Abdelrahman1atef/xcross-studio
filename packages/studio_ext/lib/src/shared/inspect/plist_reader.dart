import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:propertylistserialization/propertylistserialization.dart';

/// Property-list flavour found on disk.
@internal
enum PlistFormat {
  xml,
  binary;

  String get wire => name;
}

/// A parsed property list and the format it was stored in.
@internal
final class PlistDocument {
  const PlistDocument(this.format, this.root);

  final PlistFormat format;

  /// One of String, int, double, bool, DateTime, ByteData, List, Map.
  final Object root;

  /// [root] as a dictionary, or null when the root is not a dictionary.
  Map<String, Object?>? get dictionary {
    final value = root;
    return value is Map ? value.cast<String, Object?>() : null;
  }
}

const _binaryMagic = 'bplist00';

/// Parses [bytes] as a binary or XML property list (research R3).
///
/// Returns null when the bytes are neither format or fail to parse. The
/// parser library prints a stack trace before rethrowing; that output is
/// swallowed so it can never corrupt `--json` stdout.
@internal
PlistDocument? readPlist(Uint8List bytes) {
  final binary =
      bytes.length >= _binaryMagic.length &&
      _startsWithAscii(bytes, 0, _binaryMagic);
  if (!binary && !_looksLikeXml(bytes)) return null;
  return runZoned(() {
    try {
      final root = binary
          ? PropertyListSerialization.propertyListWithData(
              ByteData.sublistView(bytes),
            )
          : PropertyListSerialization.propertyListWithString(
              _withoutBom(utf8.decode(bytes)),
            );
      return PlistDocument(binary ? PlistFormat.binary : PlistFormat.xml, root);
      // The parser reports malformed input with assorted exceptions and
      // errors (RangeError, StateError, type errors); all mean "unreadable".
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }, zoneSpecification: ZoneSpecification(print: (_, _, _, _) {}));
}

/// Maps a parsed plist value to a deterministic JSON value (research R3).
///
/// Dictionaries get sorted keys, dates become ISO-8601 UTC strings with
/// second precision, data becomes `{"$data": "<base64>"}`, and non-finite
/// doubles become strings.
@internal
Object? plistToJson(Object? value) => switch (value) {
  null => null,
  String() || bool() || int() => value,
  double() => value.isFinite ? value : value.toString(),
  DateTime() => isoUtc(value),
  ByteData() => {r'$data': base64.encode(Uint8List.sublistView(value))},
  Uint8List() => {r'$data': base64.encode(value)},
  Map() => {
    for (final key in (value.keys.map((k) => '$k').toList()..sort()))
      key: plistToJson(value[key]),
  },
  List() => [for (final item in value) plistToJson(item)],
  _ => '$value',
};

/// Formats [time] as `YYYY-MM-DDTHH:MM:SSZ` in UTC.
@internal
String isoUtc(DateTime time) {
  final utc = time.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-'
      '${two(utc.day)}T${two(utc.hour)}:${two(utc.minute)}:'
      '${two(utc.second)}Z';
}

String _withoutBom(String text) =>
    text.startsWith('﻿') ? text.substring(1) : text;

bool _startsWithAscii(Uint8List bytes, int offset, String prefix) {
  if (bytes.length < offset + prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[offset + i] != prefix.codeUnitAt(i)) return false;
  }
  return true;
}

bool _looksLikeXml(Uint8List bytes) {
  var offset = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf) {
    offset = 3;
  }
  while (offset < bytes.length &&
      (bytes[offset] == 0x20 ||
          bytes[offset] == 0x09 ||
          bytes[offset] == 0x0a ||
          bytes[offset] == 0x0d)) {
    offset++;
  }
  return _startsWithAscii(bytes, offset, '<?xml') ||
      _startsWithAscii(bytes, offset, '<!DOCTYPE plist') ||
      _startsWithAscii(bytes, offset, '<plist');
}
