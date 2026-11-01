import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'package:studio_ext/src/shared/inspect/ber_reader.dart';
import 'package:studio_ext/src/shared/inspect/inspect_report.dart';
import 'package:studio_ext/src/shared/inspect/plist_reader.dart';

const _signedDataOid = '1.2.840.113549.1.7.2';

/// Reads a redacted summary of an `embedded.mobileprovision` (research R7,
/// R8). Returns null when the bytes are not a readable CMS profile.
///
/// Only allow-listed fields are copied: device UDIDs, certificate data, team
/// name and App ID name never leave this function.
@internal
ProfileSummary? readProfile(Uint8List bytes) {
  final Uint8List content;
  try {
    content = cmsContent(bytes);
  } on FormatException {
    return null;
  }
  final plist = readPlist(content)?.dictionary;
  return plist == null ? null : summarizeProfile(plist);
}

/// Extracts the encapsulated content of a CMS SignedData ContentInfo.
///
/// No signature or certificate is verified. Throws [FormatException] when
/// the structure is not ContentInfo → SignedData → encapContentInfo →
/// eContent.
@internal
Uint8List cmsContent(Uint8List bytes) {
  final contentInfo = readBer(bytes);
  _require(
    contentInfo.isUniversal(BerTag.sequence) &&
        contentInfo.children.length >= 2,
    'not a CMS ContentInfo',
  );
  final type = contentInfo.children[0];
  _require(
    type.isUniversal(BerTag.objectIdentifier) &&
        objectIdentifierValue(bytes, type) == _signedDataOid,
    'not CMS SignedData',
  );
  final explicit = contentInfo.children[1];
  _require(
    explicit.isContext(0) && explicit.children.isNotEmpty,
    'missing SignedData',
  );
  final signedData = explicit.children[0];
  _require(
    signedData.isUniversal(BerTag.sequence) && signedData.children.length >= 3,
    'invalid SignedData',
  );
  final encapsulated = signedData.children[2];
  _require(
    encapsulated.isUniversal(BerTag.sequence) &&
        encapsulated.children.length >= 2,
    'missing encapsulated content',
  );
  final eContent = encapsulated.children[1];
  _require(
    eContent.isContext(0) && eContent.children.isNotEmpty,
    'missing eContent',
  );
  final octets = eContent.children[0];
  _require(octets.isUniversal(BerTag.octetString), 'eContent not OCTET STRING');
  return octetStringValue(bytes, octets);
}

/// Builds the redacted [ProfileSummary] from a decoded profile plist.
@internal
ProfileSummary summarizeProfile(Map<String, Object?> plist) {
  final entitlementsValue = plist['Entitlements'];
  final entitlements = entitlementsValue is Map
      ? plistToJson(entitlementsValue)! as Map<String, Object?>
      : <String, Object?>{};
  final allDevices = plist['ProvisionsAllDevices'] == true;
  final devices = plist['ProvisionedDevices'];
  final getTaskAllow =
      entitlementsValue is Map && entitlementsValue['get-task-allow'] == true;
  final kind = allDevices
      ? ProfileKind.enterprise
      : devices is List
      ? (getTaskAllow ? ProfileKind.development : ProfileKind.adHoc)
      : ProfileKind.appStore;
  final teams = plist['TeamIdentifier'];
  final platforms = plist['Platform'];
  final certificates = plist['DeveloperCertificates'];
  return ProfileSummary(
    kind: kind,
    name: _string(plist['Name']),
    teamId: teams is List && teams.isNotEmpty ? _string(teams.first) : null,
    uuid: _string(plist['UUID']),
    creationDate: _date(plist['CreationDate']),
    expirationDate: _date(plist['ExpirationDate']),
    platforms: platforms is List
        ? ([for (final p in platforms) '$p']..sort())
        : const [],
    entitlements: entitlements,
    provisionsAllDevices: allDevices,
    deviceCount: devices is List ? devices.length : null,
    certificateCount: certificates is List ? certificates.length : 0,
  );
}

String? _string(Object? value) => value is String ? value : null;

String? _date(Object? value) => value is DateTime ? isoUtc(value) : null;

void _require(bool condition, String message) {
  if (!condition) throw FormatException(message);
}
