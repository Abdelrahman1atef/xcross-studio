import 'dart:typed_data';

import 'package:meta/meta.dart';

/// ASN.1 tag classes.
@internal
abstract final class BerClass {
  static const universal = 0;
  static const application = 1;
  static const contextSpecific = 2;
  static const private = 3;
}

/// Universal tag numbers used by the profile reader.
@internal
abstract final class BerTag {
  static const integer = 2;
  static const octetString = 4;
  static const objectIdentifier = 6;
  static const sequence = 16;
  static const set = 17;
}

/// One decoded BER/DER element (research R7).
///
/// Supports definite and indefinite lengths, low and high tag numbers, and
/// constructed encodings. Children of constructed elements are parsed
/// eagerly, which is fine for provisioning profiles (a few KiB).
@internal
final class BerElement {
  const BerElement({
    required this.tagClass,
    required this.tagNumber,
    required this.constructed,
    required this.contentStart,
    required this.contentEnd,
    required this.elementEnd,
    required this.children,
  });

  final int tagClass;
  final int tagNumber;
  final bool constructed;

  /// First content byte.
  final int contentStart;

  /// One past the last content byte (before the end-of-contents octets of an
  /// indefinite-length element).
  final int contentEnd;

  /// One past the whole element, including end-of-contents octets.
  final int elementEnd;

  /// Child elements when [constructed]; empty otherwise.
  final List<BerElement> children;

  bool isUniversal(int number) =>
      tagClass == BerClass.universal && tagNumber == number;

  bool isContext(int number) =>
      tagClass == BerClass.contextSpecific && tagNumber == number;
}

const _maxDepth = 64;

/// Reads the element starting at [offset] in [bytes].
///
/// Throws [FormatException] when the encoding runs past the input or is
/// otherwise invalid.
@internal
BerElement readBer(Uint8List bytes, [int offset = 0]) =>
    _read(bytes, offset, bytes.length, 0);

/// The value of an OCTET STRING element, concatenating the chunks of a
/// constructed (BER) encoding.
@internal
Uint8List octetStringValue(Uint8List bytes, BerElement element) {
  if (!element.constructed) {
    return Uint8List.sublistView(
      bytes,
      element.contentStart,
      element.contentEnd,
    );
  }
  final builder = BytesBuilder(copy: false);
  for (final child in element.children) {
    builder.add(octetStringValue(bytes, child));
  }
  return builder.toBytes();
}

/// Dotted decimal form of an OBJECT IDENTIFIER element.
@internal
String objectIdentifierValue(Uint8List bytes, BerElement element) {
  if (element.constructed || element.contentEnd <= element.contentStart) {
    throw const FormatException('invalid OBJECT IDENTIFIER');
  }
  final parts = <int>[];
  var value = 0;
  for (var i = element.contentStart; i < element.contentEnd; i++) {
    final byte = bytes[i];
    value = (value << 7) | (byte & 0x7f);
    if (byte & 0x80 == 0) {
      if (parts.isEmpty) {
        final first = value < 80 ? value ~/ 40 : 2;
        parts
          ..add(first)
          ..add(value - first * 40);
      } else {
        parts.add(value);
      }
      value = 0;
    }
  }
  return parts.join('.');
}

BerElement _read(Uint8List bytes, int offset, int limit, int depth) {
  if (depth > _maxDepth) throw const FormatException('BER nesting too deep');
  var position = offset;
  int next() {
    if (position >= limit) throw const FormatException('truncated BER');
    return bytes[position++];
  }

  final first = next();
  final tagClass = first >> 6;
  final constructed = first & 0x20 != 0;
  var tagNumber = first & 0x1f;
  if (tagNumber == 0x1f) {
    tagNumber = 0;
    int byte;
    var count = 0;
    do {
      byte = next();
      tagNumber = (tagNumber << 7) | (byte & 0x7f);
      if (++count > 4) throw const FormatException('BER tag too long');
    } while (byte & 0x80 != 0);
  }

  final lengthByte = next();
  if (lengthByte == 0x80) {
    if (!constructed) {
      throw const FormatException('indefinite length on primitive');
    }
    final contentStart = position;
    final children = <BerElement>[];
    while (true) {
      if (position + 2 > limit) {
        throw const FormatException('missing end-of-contents');
      }
      if (bytes[position] == 0 && bytes[position + 1] == 0) {
        return BerElement(
          tagClass: tagClass,
          tagNumber: tagNumber,
          constructed: true,
          contentStart: contentStart,
          contentEnd: position,
          elementEnd: position + 2,
          children: List.unmodifiable(children),
        );
      }
      final child = _read(bytes, position, limit, depth + 1);
      children.add(child);
      position = child.elementEnd;
    }
  }

  var length = lengthByte;
  if (lengthByte & 0x80 != 0) {
    final count = lengthByte & 0x7f;
    if (count > 4) throw const FormatException('BER length too long');
    length = 0;
    for (var i = 0; i < count; i++) {
      length = (length << 8) | next();
    }
  }
  final contentStart = position;
  final contentEnd = contentStart + length;
  if (contentEnd > limit) throw const FormatException('truncated BER');
  final children = <BerElement>[];
  if (constructed) {
    var child = contentStart;
    while (child < contentEnd) {
      final element = _read(bytes, child, contentEnd, depth + 1);
      children.add(element);
      child = element.elementEnd;
    }
  }
  return BerElement(
    tagClass: tagClass,
    tagNumber: tagNumber,
    constructed: constructed,
    contentStart: contentStart,
    contentEnd: contentEnd,
    elementEnd: contentEnd,
    children: List.unmodifiable(children),
  );
}
