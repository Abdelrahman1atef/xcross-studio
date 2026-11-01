import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'package:studio_ext/src/shared/inspect/bundle_resources.dart';
import 'package:studio_ext/src/shared/inspect/code_signature_reader.dart';
import 'package:studio_ext/src/shared/inspect/inspect_codes.dart';
import 'package:studio_ext/src/shared/inspect/inspect_report.dart';
import 'package:studio_ext/src/shared/inspect/inspect_source.dart';
import 'package:studio_ext/src/shared/inspect/macho_reader.dart';
import 'package:studio_ext/src/shared/inspect/plist_reader.dart';
import 'package:studio_ext/src/shared/inspect/profile_reader.dart';

/// Info.plist keys whose values are reported (research R8). Every other key
/// is reported by name only.
@internal
const inspectPlistAllowList = [
  'CFBundleIconFile',
  'CFBundleIconName',
  'CFBundleIcons',
  'CFBundleIcons~ipad',
  'UIBackgroundModes',
  'UILaunchScreen',
  'UILaunchStoryboardName',
];

/// Private build-time keys written by xcross (presence only).
@internal
const xcrossPrivateKeyNames = [
  'XCrossEntitlements',
  'XCrossCapabilities',
  'XCrossAppGroups',
];

/// Builds the full report for the bundle in [source]. Per-file problems are
/// collected as issues; this never throws for damaged bundle contents.
@internal
InspectReport inspectBundle(InspectSource source) =>
    BundleInspector(source).inspect();

/// One inspection run over a single bundle.
@internal
final class BundleInspector {
  BundleInspector(this.source);

  final InspectSource source;
  final List<Issue> _issues = [];
  final List<ExecutableInfo> _executables = [];

  InspectReport inspect() {
    final document = _plist(
      'Info.plist',
      InspectCodes.infoPlistUnreadable,
      required: true,
    );
    final info = document?.dictionary;
    final bundle = _bundleInfo(document, info);

    final bundleDirectory = basenameOf(
      source.bundlePath == '.' ? source.name : source.bundlePath,
    );
    final main = _executable(
      bundle.executable ?? _withoutSuffix(bundleDirectory, '.app'),
      ExecutableRole.main,
    );
    final frameworks = _frameworks();
    final extensions = _extensions();

    final signed = source.hasFile('_CodeSignature/CodeResources');
    if (signed &&
        (bundle.xcrossPrivateKeys['XCrossEntitlements']! ||
            bundle.xcrossPrivateKeys['XCrossCapabilities']!)) {
      _issues.add(
        Issue.of(
          InspectCodes.xcrossPrivateKeysInSignedBundle,
          severity: IssueSeverity.warning,
          path: 'Info.plist',
          message:
              'The signed bundle still contains XCrossEntitlements or '
              'XCrossCapabilities.',
        ),
      );
    }
    for (final link in source.skippedSymlinks) {
      _issues.add(
        Issue.of(
          InspectCodes.symlinkSkipped,
          severity: IssueSeverity.warning,
          path: link,
          message: 'Symbolic link was not followed.',
        ),
      );
    }

    return InspectReport(
      input: InputInfo(
        kind: source.kind,
        name: source.name,
        sizeBytes: source.sizeBytes,
        sha256: source.sha256Hex,
      ),
      bundle: bundle,
      signature: BundleSignature(
        present: signed,
        kind: main?.signature.kind ?? SignatureKind.none,
        teamId: main?.signature.teamId,
      ),
      executables: _executables,
      profile: _profile('embedded.mobileprovision'),
      resources: readResources(source, info, _issues),
      frameworks: frameworks,
      extensions: extensions,
      issues: _issues,
    );
  }

  BundleInfo _bundleInfo(PlistDocument? document, Map<String, Object?>? info) {
    final family = info?['UIDeviceFamily'];
    return BundleInfo(
      path: source.bundlePath,
      bundleId: _string(info?['CFBundleIdentifier']),
      name: _string(info?['CFBundleName']),
      displayName: _string(info?['CFBundleDisplayName']),
      shortVersion: _string(info?['CFBundleShortVersionString']),
      buildNumber: _string(info?['CFBundleVersion']),
      executable: _string(info?['CFBundleExecutable']),
      minimumOSVersion: _string(info?['MinimumOSVersion']),
      deviceFamily: family is List
          ? ([
              for (final value in family)
                if (value is int)
                  value
                else if (value is String && int.tryParse(value) != null)
                  int.parse(value),
            ]..sort())
          : const [],
      infoPlistFormat: info == null ? null : document!.format.wire,
      infoPlistKeys: info == null ? const [] : (info.keys.toList()..sort()),
      plist: {
        if (info != null)
          for (final key in inspectPlistAllowList)
            if (info.containsKey(key)) key: plistToJson(info[key]),
      },
      xcrossPrivateKeys: {
        for (final key in xcrossPrivateKeyNames)
          key: info?.containsKey(key) ?? false,
      },
    );
  }

  List<FrameworkInfo> _frameworks() {
    final result = <FrameworkInfo>[];
    final bundles = <String>{};
    for (final file in source.files) {
      final segments = file.split('/');
      if (segments.length < 2 || segments[0] != 'Frameworks') continue;
      if (segments.length >= 3 && segments[1].endsWith('.framework')) {
        bundles.add(segments[1]);
      } else if (segments.length == 2 && segments[1].endsWith('.dylib')) {
        _executable(file, ExecutableRole.dylib);
        result.add(
          FrameworkInfo(
            name: segments[1],
            path: file,
            kind: FrameworkKind.dylib,
            bundleId: null,
          ),
        );
      }
    }
    for (final name in bundles) {
      final directory = 'Frameworks/$name';
      final info = _plist(
        '$directory/Info.plist',
        InspectCodes.plistUnreadable,
      )?.dictionary;
      final executable =
          _string(info?['CFBundleExecutable']) ??
          _withoutSuffix(name, '.framework');
      _executable('$directory/$executable', ExecutableRole.framework);
      result.add(
        FrameworkInfo(
          name: name,
          path: directory,
          kind: FrameworkKind.framework,
          bundleId: _string(info?['CFBundleIdentifier']),
        ),
      );
    }
    return result;
  }

  List<ExtensionInfo> _extensions() {
    final names = <String>{};
    for (final file in source.files) {
      final segments = file.split('/');
      if (segments.length >= 3 &&
          segments[0] == 'PlugIns' &&
          segments[1].endsWith('.appex')) {
        names.add(segments[1]);
      }
    }
    return [for (final name in names) _extension('PlugIns/$name', name)];
  }

  ExtensionInfo _extension(String directory, String name) {
    final info = _plist(
      '$directory/Info.plist',
      InspectCodes.plistUnreadable,
      required: true,
    )?.dictionary;
    final executableName =
        _string(info?['CFBundleExecutable']) ?? _withoutSuffix(name, '.appex');
    final executable = _executable(
      '$directory/$executableName',
      ExecutableRole.extension,
    );
    final extension = info?['NSExtension'];
    return ExtensionInfo(
      path: directory,
      bundleId: _string(info?['CFBundleIdentifier']),
      extensionPoint: extension is Map
          ? _string(extension['NSExtensionPointIdentifier'])
          : null,
      executable: executable?.path,
      profile: _profile('$directory/embedded.mobileprovision'),
    );
  }

  /// Reads one executable; records an [ExecutableInfo] when the file exists.
  ExecutableInfo? _executable(String path, ExecutableRole role) {
    final Uint8List? bytes;
    try {
      bytes = source.read(path);
    } on FormatException catch (error) {
      return _unreadable(path, role, error.message);
    }
    if (bytes == null) {
      _issues.add(
        Issue.of(
          InspectCodes.executableMissing,
          severity: IssueSeverity.error,
          path: path,
          message: 'The ${role.wire} executable does not exist.',
        ),
      );
      return null;
    }
    if (!hasMachOMagic(bytes)) {
      return _unreadable(path, role, 'not a Mach-O file');
    }
    final MachOInfo macho;
    try {
      macho = readMachO(bytes);
    } on FormatException catch (error) {
      return _unreadable(path, role, error.message);
    }
    final signature = readCodeSignature(bytes, macho.preferredSlice);
    if (signature.malformed) {
      _issues.add(
        Issue.of(
          InspectCodes.signatureInvalid,
          severity: IssueSeverity.error,
          path: path,
          message: 'The embedded code signature is malformed.',
        ),
      );
    }
    if (signature.entitlementsUnreadable) {
      _issues.add(
        Issue.of(
          InspectCodes.entitlementsUnreadable,
          severity: IssueSeverity.error,
          path: path,
          message: 'The embedded entitlements are not a valid plist.',
        ),
      );
    } else if (signature.entitlements == null &&
        signature.derEntitlementsPresent) {
      _issues.add(
        Issue.of(
          InspectCodes.entitlementsDerOnly,
          severity: IssueSeverity.warning,
          path: path,
          message: 'Only DER entitlements are embedded; values not decoded.',
        ),
      );
    }
    final info = ExecutableInfo(
      path: path,
      role: role,
      architectures: macho.architectures,
      signature: signature.executableSignature,
      entitlements: signature.entitlements,
      derEntitlementsPresent: signature.derEntitlementsPresent,
    );
    _executables.add(info);
    return info;
  }

  ExecutableInfo _unreadable(String path, ExecutableRole role, String why) {
    _issues.add(
      Issue.of(
        InspectCodes.machoInvalid,
        severity: IssueSeverity.error,
        path: path,
        message: 'The ${role.wire} executable cannot be read: $why.',
      ),
    );
    final info = ExecutableInfo(
      path: path,
      role: role,
      architectures: const [],
      signature: ExecutableSignature.unsigned,
      entitlements: null,
      derEntitlementsPresent: false,
    );
    _executables.add(info);
    return info;
  }

  ProfileSummary? _profile(String path) {
    final Uint8List? bytes;
    try {
      bytes = source.read(path);
    } on FormatException {
      return _unreadableProfile(path);
    }
    if (bytes == null) return null;
    return readProfile(bytes) ?? _unreadableProfile(path);
  }

  ProfileSummary? _unreadableProfile(String path) {
    _issues.add(
      Issue.of(
        InspectCodes.profileUnreadable,
        severity: IssueSeverity.error,
        path: path,
        message: 'The provisioning profile is not a readable CMS profile.',
      ),
    );
    return null;
  }

  /// Reads a dictionary plist; a missing file is an issue only if
  /// [required].
  PlistDocument? _plist(
    String path,
    InspectCode code, {
    bool required = false,
  }) {
    Uint8List? bytes;
    try {
      bytes = source.read(path);
    } on FormatException {
      bytes = null;
    }
    if (bytes == null) {
      if (required) {
        _issues.add(
          Issue.of(
            code,
            severity: IssueSeverity.error,
            path: path,
            message: '$path is missing or cannot be read.',
          ),
        );
      }
      return null;
    }
    final document = readPlist(bytes);
    if (document?.dictionary == null) {
      _issues.add(
        Issue.of(
          code,
          severity: IssueSeverity.error,
          path: path,
          message: '$path is not a valid property list dictionary.',
        ),
      );
      return null;
    }
    return document;
  }
}

String? _string(Object? value) => value is String ? value : null;

String _withoutSuffix(String value, String suffix) => value.endsWith(suffix)
    ? value.substring(0, value.length - suffix.length)
    : value;
