import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'package:studio_ext/src/shared/inspect/inspect_report.dart';
import 'package:studio_ext/src/shared/inspect/macho_reader.dart';
import 'package:studio_ext/src/shared/inspect/plist_reader.dart';

/// Blob magics and slots of an embedded code signature (big-endian).
@internal
abstract final class CodeSignatureMagic {
  static const embeddedSignature = 0xfade0cc0;
  static const codeDirectory = 0xfade0c02;
  static const blobWrapper = 0xfade0b01;
  static const entitlements = 0xfade7171;
  static const derEntitlements = 0xfade7172;

  static const slotCodeDirectory = 0;
  static const slotEntitlements = 5;
  static const slotDerEntitlements = 7;
  static const slotAlternateCodeDirectory = 0x1000;
  static const slotSignature = 0x10000;

  static const flagAdHoc = 0x2;
  static const flagLinkerSigned = 0x20000;
  static const teamIdVersion = 0x20200;
}

/// What one slice's code signature says (research R5, R6).
@internal
final class CodeSignatureInfo {
  const CodeSignatureInfo({
    required this.kind,
    required this.linkerSigned,
    required this.identifier,
    required this.teamId,
    required this.entitlements,
    required this.entitlementsUnreadable,
    required this.derEntitlementsPresent,
    required this.malformed,
  });

  static const unsigned = CodeSignatureInfo(
    kind: SignatureKind.none,
    linkerSigned: false,
    identifier: null,
    teamId: null,
    entitlements: null,
    entitlementsUnreadable: false,
    derEntitlementsPresent: false,
    malformed: false,
  );

  static const malformedSignature = CodeSignatureInfo(
    kind: SignatureKind.adhoc,
    linkerSigned: false,
    identifier: null,
    teamId: null,
    entitlements: null,
    entitlementsUnreadable: false,
    derEntitlementsPresent: false,
    malformed: true,
  );

  final SignatureKind kind;
  final bool linkerSigned;
  final String? identifier;
  final String? teamId;

  /// Decoded XML entitlements as JSON values (keys sorted), or null.
  final Map<String, Object?>? entitlements;

  /// An XML entitlements blob exists but is not a dictionary plist.
  final bool entitlementsUnreadable;
  final bool derEntitlementsPresent;

  /// The SuperBlob or CodeDirectory is malformed.
  final bool malformed;

  ExecutableSignature get executableSignature => ExecutableSignature(
    kind: kind,
    linkerSigned: linkerSigned,
    identifier: identifier,
    teamId: teamId,
  );
}

/// Reads the code signature of [slice] from the whole file [bytes].
@internal
CodeSignatureInfo readCodeSignature(Uint8List bytes, MachOSlice slice) {
  final start = slice.codeSignatureOffset;
  final size = slice.codeSignatureSize;
  if (start == null || size == null) return CodeSignatureInfo.unsigned;
  try {
    return _read(Uint8List.sublistView(bytes, start, start + size));
  } on FormatException {
    return CodeSignatureInfo.malformedSignature;
  }
}

CodeSignatureInfo _read(Uint8List blob) {
  final data = ByteData.sublistView(blob);
  _require(blob.length >= 12, 'truncated SuperBlob');
  _require(
    data.getUint32(0) == CodeSignatureMagic.embeddedSignature,
    'not an embedded signature',
  );
  final length = data.getUint32(4);
  _require(length >= 12 && length <= blob.length, 'invalid SuperBlob length');
  final count = data.getUint32(8);
  _require(12 + count * 8 <= length, 'truncated SuperBlob index');

  final slots = <int, Uint8List>{};
  for (var i = 0; i < count; i++) {
    final type = data.getUint32(12 + i * 8);
    final offset = data.getUint32(16 + i * 8);
    _require(offset + 8 <= length, 'blob offset out of range');
    final blobLength = data.getUint32(offset + 4);
    _require(
      blobLength >= 8 && offset + blobLength <= length,
      'blob length out of range',
    );
    slots[type] = Uint8List.sublistView(blob, offset, offset + blobLength);
  }

  final directory =
      slots[CodeSignatureMagic.slotCodeDirectory] ??
      slots[CodeSignatureMagic.slotAlternateCodeDirectory];
  _require(directory != null, 'no CodeDirectory');
  final cd = ByteData.sublistView(directory!);
  _require(
    directory.length >= 44 &&
        cd.getUint32(0) == CodeSignatureMagic.codeDirectory,
    'invalid CodeDirectory',
  );
  final version = cd.getUint32(8);
  final flags = cd.getUint32(12);
  final identifier = _cString(directory, cd.getUint32(20));
  String? teamId;
  if (version >= CodeSignatureMagic.teamIdVersion && directory.length >= 52) {
    final teamOffset = cd.getUint32(48);
    if (teamOffset != 0) teamId = _cString(directory, teamOffset);
  }

  final cms = slots[CodeSignatureMagic.slotSignature];
  final certificate =
      cms != null &&
      ByteData.sublistView(cms).getUint32(0) ==
          CodeSignatureMagic.blobWrapper &&
      cms.length > 8;

  Map<String, Object?>? entitlements;
  var entitlementsUnreadable = false;
  final xml = slots[CodeSignatureMagic.slotEntitlements];
  if (xml != null &&
      ByteData.sublistView(xml).getUint32(0) ==
          CodeSignatureMagic.entitlements) {
    final dictionary = readPlist(Uint8List.sublistView(xml, 8))?.dictionary;
    if (dictionary == null) {
      entitlementsUnreadable = true;
    } else {
      entitlements = plistToJson(dictionary)! as Map<String, Object?>;
    }
  }
  final der = slots[CodeSignatureMagic.slotDerEntitlements];
  final derPresent =
      der != null &&
      ByteData.sublistView(der).getUint32(0) ==
          CodeSignatureMagic.derEntitlements;

  return CodeSignatureInfo(
    kind: certificate ? SignatureKind.certificate : SignatureKind.adhoc,
    linkerSigned: flags & CodeSignatureMagic.flagLinkerSigned != 0,
    identifier: identifier,
    teamId: teamId,
    entitlements: entitlements,
    entitlementsUnreadable: entitlementsUnreadable,
    derEntitlementsPresent: derPresent,
    malformed: false,
  );
}

String? _cString(Uint8List bytes, int offset) {
  if (offset == 0 || offset >= bytes.length) return null;
  var end = offset;
  while (end < bytes.length && bytes[end] != 0) {
    end++;
  }
  return utf8.decode(
    Uint8List.sublistView(bytes, offset, end),
    allowMalformed: true,
  );
}

void _require(bool condition, String message) {
  if (!condition) throw FormatException(message);
}
