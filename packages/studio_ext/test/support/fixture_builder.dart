// Synthetic, deterministic iOS bundle fixtures for `xcross inspect` tests
// (research R13). Nothing here is an Apple binary: every Mach-O, signature,
// profile and plist is assembled from scratch so the bytes are reviewable and
// identical on every host.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:propertylistserialization/propertylistserialization.dart';

/// Fixed zip entry time so fixture IPAs hash identically everywhere.
final DateTime fixedTime = DateTime.utc(2020);

// ---------------------------------------------------------------------------
// Planted secrets: tests assert none of these ever reach any output.

const plantedUdids = [
  '00008020-001A2B3C4D5E6F70',
  '0123456789abcdef0123456789abcdef01234567',
  '00008110-000A1B2C3D4E5F60',
];
const plantedApiKey = 'AIzaPLANTEDxKEYx00000000000000000000000';
const plantedTeamName = 'Planted Team Name LLC';
const plantedAppIdName = 'Planted AppID Name';
final Uint8List plantedCertificate = Uint8List.fromList(
  utf8.encode('-----PLANTED CERTIFICATE 7f3a9c d41e-----'),
);
final Uint8List plantedCmsPayload = Uint8List.fromList(
  utf8.encode('PLANTED-CMS-SIGNATURE-PAYLOAD-5c2b'),
);

// ---------------------------------------------------------------------------
// Byte helpers.

Uint8List _u32(int value, {Endian endian = Endian.big}) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value, endian);

Uint8List _u64(int value, {Endian endian = Endian.big}) =>
    Uint8List(8)..buffer.asByteData().setUint64(0, value, endian);

int _align(int value, int alignment) =>
    (value + alignment - 1) ~/ alignment * alignment;

Uint8List _concat(Iterable<List<int>> parts) {
  final builder = BytesBuilder(copy: false);
  for (final part in parts) {
    builder.add(part);
  }
  return builder.toBytes();
}

// ---------------------------------------------------------------------------
// Property lists.

Uint8List xmlPlist(Map<String, Object> root) =>
    utf8.encode(PropertyListSerialization.stringWithPropertyList(root));

Uint8List binaryPlist(Map<String, Object> root) =>
    Uint8List.sublistView(PropertyListSerialization.dataWithPropertyList(root));

// ---------------------------------------------------------------------------
// Mach-O.

const _cpu = {
  'arm64': (0x0100000c, 0),
  'arm64e': (0x0100000c, 2),
  'armv7': (12, 9),
  'x86_64': (0x01000007, 3),
};

/// A thin Mach-O executable for [arch] with an optional embedded
/// [signature] (pointed to by `LC_CODE_SIGNATURE`).
Uint8List machO({
  String arch = 'arm64',
  Uint8List? signature,
  int bodySize = 256,
  int seed = 1,
}) {
  final (cpuType, cpuSubtype) = _cpu[arch]!;
  final is64 = arch != 'armv7';
  final headerSize = is64 ? 32 : 28;
  final commandCount = signature == null ? 0 : 1;
  final commandsSize = commandCount * 16;
  final bodyStart = headerSize + commandsSize;
  final signatureOffset = _align(bodyStart + bodySize, 16);
  final total = signature == null
      ? bodyStart + bodySize
      : signatureOffset + signature.length;
  final bytes = Uint8List(total);
  final data = ByteData.sublistView(bytes);
  const le = Endian.little;
  data
    ..setUint32(0, is64 ? 0xfeedfacf : 0xfeedface, le)
    ..setInt32(4, cpuType, le)
    ..setInt32(8, cpuSubtype, le)
    ..setUint32(12, 2, le) // MH_EXECUTE
    ..setUint32(16, commandCount, le)
    ..setUint32(20, commandsSize, le);
  if (signature != null) {
    data
      ..setUint32(headerSize, 0x1d, le)
      ..setUint32(headerSize + 4, 16, le)
      ..setUint32(headerSize + 8, signatureOffset, le)
      ..setUint32(headerSize + 12, signature.length, le);
    bytes.setRange(signatureOffset, total, signature);
  }
  var state = seed & 0x7fffffff;
  for (var i = bodyStart; i < bodyStart + bodySize; i++) {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    bytes[i] = state >> 16 & 0xff;
  }
  return bytes;
}

/// A universal (fat) binary holding [slices]; 64-bit fat header when [wide].
Uint8List fatMachO(List<Uint8List> slices, {bool wide = false}) {
  final entrySize = wide ? 32 : 20;
  final header = BytesBuilder()
    ..add(_u32(wide ? 0xcafebabf : 0xcafebabe))
    ..add(_u32(slices.length));
  var offset = _align(8 + slices.length * entrySize, 0x4000);
  final offsets = <int>[];
  for (final slice in slices) {
    final view = ByteData.sublistView(slice);
    final cpuType = view.getInt32(4, Endian.little);
    final cpuSubtype = view.getInt32(8, Endian.little);
    header
      ..add(_u32(cpuType & 0xffffffff))
      ..add(_u32(cpuSubtype & 0xffffffff));
    if (wide) {
      header
        ..add(_u64(offset))
        ..add(_u64(slice.length))
        ..add(_u32(14))
        ..add(_u32(0));
    } else {
      header
        ..add(_u32(offset))
        ..add(_u32(slice.length))
        ..add(_u32(14));
    }
    offsets.add(offset);
    offset = _align(offset + slice.length, 0x4000);
  }
  final bytes = Uint8List(offsets.last + slices.last.length)
    ..setRange(0, header.length, header.toBytes());
  for (var i = 0; i < slices.length; i++) {
    bytes.setRange(offsets[i], offsets[i] + slices[i].length, slices[i]);
  }
  return bytes;
}

// ---------------------------------------------------------------------------
// Code signatures.

/// Which CMS blob-wrapper a signature carries in slot 0x10000.
enum CmsBlob { none, empty, signed }

Uint8List _blob(int magic, List<int> payload) =>
    _concat([_u32(magic), _u32(8 + payload.length), payload]);

/// CodeDirectory version 0x20400 without hash slots.
Uint8List codeDirectory({
  required String identifier,
  String? teamId,
  int flags = 0x2,
}) {
  const headerSize = 88;
  final ident = [...utf8.encode(identifier), 0];
  final team = teamId == null ? <int>[] : [...utf8.encode(teamId), 0];
  const identOffset = headerSize;
  final teamOffset = teamId == null ? 0 : identOffset + ident.length;
  final length = headerSize + ident.length + team.length;
  final bytes = Uint8List(length);
  ByteData.sublistView(bytes)
    ..setUint32(0, 0xfade0c02)
    ..setUint32(4, length)
    ..setUint32(8, 0x20400)
    ..setUint32(12, flags)
    ..setUint32(16, length) // hashOffset: no hashes follow
    ..setUint32(20, identOffset)
    ..setUint8(36, 32) // hashSize
    ..setUint8(37, 2) // SHA-256
    ..setUint8(39, 12) // 4 KiB pages
    ..setUint32(48, teamOffset);
  bytes
    ..setRange(identOffset, identOffset + ident.length, ident)
    ..setRange(teamOffset == 0 ? length : teamOffset, length, team);
  return bytes;
}

/// An embedded signature SuperBlob (0xfade0cc0).
Uint8List codeSignature({
  String identifier = 'com.example.fixture',
  String? teamId,
  int flags = 0x2,
  Map<String, Object>? entitlements,
  bool derEntitlements = false,
  CmsBlob cms = CmsBlob.none,
  bool corruptEntitlements = false,
}) {
  final slots = <(int, Uint8List)>[
    (0, codeDirectory(identifier: identifier, teamId: teamId, flags: flags)),
    if (entitlements != null)
      (5, _blob(0xfade7171, xmlPlist(entitlements)))
    else if (corruptEntitlements)
      (5, _blob(0xfade7171, utf8.encode('<?xml version="1.0"?><plist>'))),
    if (derEntitlements) (7, _blob(0xfade7172, [0x70, 0x00])),
    if (cms == CmsBlob.empty) (0x10000, _blob(0xfade0b01, const [])),
    if (cms == CmsBlob.signed) (0x10000, _blob(0xfade0b01, plantedCmsPayload)),
  ];
  final indexEnd = 12 + slots.length * 8;
  var offset = indexEnd;
  final index = BytesBuilder();
  for (final (slot, blob) in slots) {
    index
      ..add(_u32(slot))
      ..add(_u32(offset));
    offset += blob.length;
  }
  return _concat([
    _u32(0xfade0cc0),
    _u32(offset),
    _u32(slots.length),
    index.toBytes(),
    for (final (_, blob) in slots) blob,
  ]);
}

// ---------------------------------------------------------------------------
// Provisioning profiles (CMS SignedData wrapping an XML plist).

const _oidSignedData = [
  0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02, //
];
const _oidData = [
  0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x01, //
];

List<int> _tlv(int tag, List<int> content) {
  final length = content.length;
  final List<int> encodedLength;
  if (length < 0x80) {
    encodedLength = [length];
  } else {
    final bytes = <int>[];
    for (var v = length; v > 0; v >>= 8) {
      bytes.insert(0, v & 0xff);
    }
    encodedLength = [0x80 | bytes.length, ...bytes];
  }
  return [tag, ...encodedLength, ...content];
}

List<int> _indefinite(int tag, List<List<int>> children) => [
  tag,
  0x80,
  for (final child in children) ...child,
  0,
  0,
];

/// `embedded.mobileprovision` bytes for [plist]. With [indefinite] the
/// structure uses BER indefinite lengths and a chunked OCTET STRING, as
/// Apple-signed profiles may.
Uint8List mobileProvision(
  Map<String, Object> plist, {
  bool indefinite = false,
}) {
  final content = xmlPlist(plist);
  const version = [0x02, 0x01, 0x01];
  final digestAlgorithms = _tlv(0x31, const []);
  final certificates = _tlv(0xa0, _tlv(0x30, _tlv(0x04, plantedCertificate)));
  final signerInfos = _tlv(0x31, const []);
  if (!indefinite) {
    final encapsulated = _tlv(0x30, [
      ..._oidData,
      ..._tlv(0xa0, _tlv(0x04, content)),
    ]);
    final signedData = _tlv(0x30, [
      ...version,
      ...digestAlgorithms,
      ...encapsulated,
      ...certificates,
      ...signerInfos,
    ]);
    return Uint8List.fromList(
      _tlv(0x30, [..._oidSignedData, ..._tlv(0xa0, signedData)]),
    );
  }
  const chunkSize = 100;
  final chunks = [
    for (var i = 0; i < content.length; i += chunkSize)
      _tlv(
        0x04,
        content.sublist(
          i,
          i + chunkSize > content.length ? content.length : i + chunkSize,
        ),
      ),
  ];
  final encapsulated = _indefinite(0x30, [
    _oidData,
    _indefinite(0xa0, [_indefinite(0x24, chunks)]),
  ]);
  final signedData = _indefinite(0x30, [
    version,
    digestAlgorithms,
    encapsulated,
    certificates,
    signerInfos,
  ]);
  return Uint8List.fromList(
    _indefinite(0x30, [
      _oidSignedData,
      _indefinite(0xa0, [signedData]),
    ]),
  );
}

/// A profile plist with the given kind-driving fields and planted secrets.
Map<String, Object> profilePlist({
  required String bundleId,
  String teamId = 'TEAMID1234',
  bool getTaskAllow = true,
  bool devices = true,
  bool allDevices = false,
  String uuid = '11111111-2222-3333-4444-555555555555',
  DateTime? created,
  DateTime? expires,
  Map<String, Object> extraEntitlements = const {},
}) => {
  'AppIDName': plantedAppIdName,
  'CreationDate': created ?? DateTime.utc(2026),
  'DeveloperCertificates': [ByteData.sublistView(plantedCertificate)],
  'Entitlements': <String, Object>{
    'application-identifier': '$teamId.$bundleId',
    'com.apple.developer.team-identifier': teamId,
    'get-task-allow': getTaskAllow,
    ...extraEntitlements,
  },
  'ExpirationDate': expires ?? DateTime.utc(2027),
  'Name': 'Fixture Profile $bundleId',
  'Platform': ['iOS'],
  if (devices) 'ProvisionedDevices': plantedUdids,
  if (allDevices) 'ProvisionsAllDevices': true,
  'TeamIdentifier': [teamId],
  'TeamName': plantedTeamName,
  'UUID': uuid,
  'Version': 1,
};

// ---------------------------------------------------------------------------
// Bundles.

/// Tiny stand-in PNG (signature only); inspect never decodes images.
final Uint8List fakePng = Uint8List.fromList([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
]);

Map<String, Object> baseInfoPlist({
  required String bundleId,
  String executable = 'Runner',
}) => {
  'CFBundleDisplayName': 'Fixture App',
  'CFBundleExecutable': executable,
  'CFBundleIdentifier': bundleId,
  'CFBundleInfoDictionaryVersion': '6.0',
  'CFBundleName': 'Fixture',
  'CFBundlePackageType': 'APPL',
  'CFBundleShortVersionString': '1.0.0',
  'CFBundleVersion': '1',
  'LSRequiresIPhoneOS': true,
  'MinimumOSVersion': '13.0',
  'UIDeviceFamily': [1],
  'UIRequiredDeviceCapabilities': ['arm64'],
};

Map<String, Uint8List> _flutterFrameworks({
  required Uint8List? appSignature,
  required Uint8List? flutterSignature,
}) => {
  'Frameworks/App.framework/App': machO(signature: appSignature, seed: 2),
  'Frameworks/App.framework/Info.plist': xmlPlist({
    'CFBundleExecutable': 'App',
    'CFBundleIdentifier': 'io.flutter.flutter.app',
  }),
  'Frameworks/Flutter.framework/Flutter': machO(
    signature: flutterSignature,
    seed: 3,
  ),
  'Frameworks/Flutter.framework/Info.plist': xmlPlist({
    'CFBundleExecutable': 'Flutter',
    'CFBundleIdentifier': 'io.flutter.flutter',
  }),
};

/// One app bundle: its directory name and files relative to the bundle root.
final class FixtureBundle {
  FixtureBundle(this.appName, this.files);

  /// Bundle directory name, e.g. `Runner.app`.
  final String appName;
  final Map<String, Uint8List> files;

  /// Writes the bundle as `<parent>/<directoryName ?? appName>` and returns
  /// its path.
  String writeApp(Directory parent, {String? directoryName}) {
    final root = Directory(
      '${parent.path}${Platform.pathSeparator}${directoryName ?? appName}',
    )..createSync(recursive: true);
    for (final MapEntry(:key, :value) in files.entries) {
      File('${root.path}/$key')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(value);
    }
    return root.path;
  }

  /// Zip entries `Payload/<appName>/<file>`.
  Map<String, Uint8List> get ipaEntries => {
    for (final MapEntry(:key, :value) in files.entries)
      'Payload/$appName/$key': value,
  };

  /// Writes `<parent>/<fileName>` as an IPA and returns its path.
  String writeIpa(
    Directory parent,
    String fileName, {
    DateTime? modified,
    bool compress = false,
    Map<String, Uint8List> outside = const {}, // studio: 018 — SwiftSupport
  }) {
    final file = File('${parent.path}${Platform.pathSeparator}$fileName')
      ..writeAsBytesSync(
        encodeZip(
          {...ipaEntries, ...outside},
          modified: modified,
          compress: compress,
        ),
      );
    return file.path;
  }
}

/// A deterministic zip: entries sorted by name, fixed timestamp, stored
/// (uncompressed) unless [compress].
Uint8List encodeZip(
  Map<String, Uint8List> entries, {
  DateTime? modified,
  bool compress = false,
}) {
  final archive = Archive();
  for (final name in entries.keys.toList()..sort()) {
    final data = entries[name]!;
    archive.add(
      compress
          ? ArchiveFile.bytes(name, data)
          : ArchiveFile.noCompress(name, data.length, data),
    );
  }
  return ZipEncoder().encodeBytes(archive, modified: modified ?? fixedTime);
}

// ---------------------------------------------------------------------------
// The three golden fixtures (research R13).

/// xcross v2.0.9-style unsigned build: XML Info.plist with an empty
/// `UILaunchScreen`, no icons, no Assets.car, unsigned Runner, linker-signed
/// App.framework, certificate-signed Flutter.framework, one plugin dylib.
FixtureBundle unsignedV209({Uint8List? runner}) => FixtureBundle('Runner.app', {
  'Info.plist': xmlPlist({
    ...baseInfoPlist(bundleId: 'com.example.fixture'),
    'UILaunchScreen': <String, Object>{},
  }),
  'Runner': runner ?? machO(),
  ..._flutterFrameworks(
    appSignature: codeSignature(
      identifier: 'io.flutter.flutter.app',
      flags: 0x20002,
    ),
    flutterSignature: codeSignature(
      identifier: 'io.flutter.flutter',
      teamId: 'FLTTEAM001',
      flags: 0,
      cms: CmsBlob.signed,
    ),
  ),
  'Frameworks/libpath_provider_foundation.dylib': machO(seed: 4),
  'flutter_assets/AssetManifest.bin': Uint8List.fromList([0, 1, 2, 3]),
});

/// Ad-hoc signed `.app` with push and associated-domains entitlements, a
/// binary Info.plist, loose icons and a loose launch image.
FixtureBundle adhocPush() => FixtureBundle('Runner.app', {
  'Info.plist': binaryPlist({
    ...baseInfoPlist(bundleId: 'com.example.push'),
    'CFBundleIcons': <String, Object>{
      'CFBundlePrimaryIcon': <String, Object>{
        'CFBundleIconFiles': ['AppIcon60x60'],
        'CFBundleIconName': 'AppIcon',
      },
    },
    'UIBackgroundModes': ['remote-notification'],
    'UILaunchScreen': <String, Object>{
      'UIColorName': 'LaunchBackground',
      'UIImageName': 'LaunchImage',
    },
  }),
  'Runner': machO(
    signature: codeSignature(
      identifier: 'com.example.push',
      entitlements: {
        'application-identifier': 'TEAMID1234.com.example.push',
        'aps-environment': 'development',
        'com.apple.developer.associated-domains': [
          'applinks:example.com',
          'webcredentials:example.com',
        ],
        'get-task-allow': true,
      },
      derEntitlements: true,
    ),
  ),
  '_CodeSignature/CodeResources': xmlPlist({'files': <String, Object>{}}),
  'AppIcon60x60@2x.png': fakePng,
  'AppIcon60x60@3x.png': fakePng,
  'LaunchImage.png': fakePng,
  ..._flutterFrameworks(
    appSignature: codeSignature(identifier: 'io.flutter.flutter.app'),
    flutterSignature: codeSignature(identifier: 'io.flutter.flutter'),
  ),
});

/// Certificate-signed IPA with a fat Runner, a BER development profile with
/// planted secrets, Assets.car, a missing icon file, an uncompiled launch
/// storyboard, leaked xcross private keys and a share extension with its own
/// ad-hoc profile.
FixtureBundle profileAppex({
  String uuid = '11111111-2222-3333-4444-555555555555',
  DateTime? created,
  DateTime? expires,
}) {
  const bundleId = 'com.example.profile';
  final mainEntitlements = <String, Object>{
    'application-identifier': 'TEAMID1234.$bundleId',
    'aps-environment': 'development',
    'com.apple.developer.associated-domains': ['applinks:example.com'],
    'get-task-allow': true,
  };
  Uint8List signed(String identifier, Map<String, Object> entitlements) =>
      codeSignature(
        identifier: identifier,
        teamId: 'TEAMID1234',
        flags: 0,
        entitlements: entitlements,
        cms: CmsBlob.signed,
      );
  return FixtureBundle('Runner.app', {
    'Info.plist': xmlPlist({
      ...baseInfoPlist(bundleId: bundleId),
      'CFBundleIcons': <String, Object>{
        'CFBundlePrimaryIcon': <String, Object>{
          'CFBundleIconFiles': ['AppIcon60x60', 'AppIconMissing'],
          'CFBundleIconName': 'AppIcon',
        },
      },
      'GMSApiKey': plantedApiKey,
      'UIDeviceFamily': [2, 1],
      'UILaunchScreen': <String, Object>{'UIImageName': 'LaunchLogo'},
      'UILaunchStoryboardName': 'LaunchScreen',
      'XCrossEntitlements': <String, Object>{'aps-environment': 'development'},
    }),
    'Runner': fatMachO([
      machO(signature: signed(bundleId, mainEntitlements), seed: 5),
      machO(
        arch: 'armv7',
        signature: signed(bundleId, mainEntitlements),
        seed: 6,
      ),
    ]),
    '_CodeSignature/CodeResources': xmlPlist({'files': <String, Object>{}}),
    'embedded.mobileprovision': mobileProvision(
      profilePlist(
        bundleId: bundleId,
        uuid: uuid,
        created: created,
        expires: expires,
        extraEntitlements: {'aps-environment': 'development'},
      ),
      indefinite: true,
    ),
    'Assets.car': Uint8List.fromList(List.generate(64, (i) => i)),
    'AppIcon60x60@2x.png': fakePng,
    'AppIcon60x60~ipad.png': fakePng,
    'PlugIns/Share.appex/Info.plist': xmlPlist({
      'CFBundleExecutable': 'Share',
      'CFBundleIdentifier': '$bundleId.Share',
      'NSExtension': <String, Object>{
        'NSExtensionPointIdentifier': 'com.apple.share-services',
      },
    }),
    'PlugIns/Share.appex/Share': machO(
      signature: signed('$bundleId.Share', {
        'com.apple.security.application-groups': ['group.$bundleId'],
      }),
      seed: 7,
    ),
    'PlugIns/Share.appex/embedded.mobileprovision': mobileProvision(
      profilePlist(
        bundleId: '$bundleId.Share',
        getTaskAllow: false,
        uuid: '66666666-7777-8888-9999-000000000000',
        created: created,
        expires: expires,
      ),
    ),
    ..._flutterFrameworks(
      appSignature: signed('io.flutter.flutter.app', const {}),
      flutterSignature: codeSignature(
        identifier: 'io.flutter.flutter',
        teamId: 'FLTTEAM001',
        flags: 0,
        cms: CmsBlob.signed,
      ),
    ),
  });
}

/// The golden fixtures: name → writer returning the input path.
final Map<String, String Function(Directory)> goldenFixtures = {
  'unsigned_v209': (dir) => unsignedV209().writeIpa(dir, 'unsigned_v209.ipa'),
  'adhoc_push': (dir) =>
      adhocPush().writeApp(dir, directoryName: 'adhoc_push.app'),
  'profile_appex': (dir) => profileAppex().writeIpa(dir, 'profile_appex.ipa'),
};
