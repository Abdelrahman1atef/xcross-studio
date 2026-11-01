import 'package:meta/meta.dart';

import 'package:studio_ext/src/shared/inspect/inspect_codes.dart';

// Report model for `xcross inspect` (schemaVersion 1).
//
// Field order in every `toJson` is the order of the tables in
// `specs/001-inspect/data-model.md`, and every field is always emitted.

/// `"ipa"` or `"app"`.
@internal
enum InputKind {
  ipa,
  app;

  String get wire => name;
}

/// Code-signature kind of one executable.
@internal
enum SignatureKind {
  none,
  adhoc,
  certificate;

  String get wire => name;
}

/// Structural role of an executable inside the bundle.
@internal
enum ExecutableRole {
  main,
  framework,
  dylib,
  extension;

  String get wire => name;
}

/// Provisioning profile kind.
@internal
enum ProfileKind {
  development('development'),
  adHoc('ad-hoc'),
  appStore('app-store'),
  enterprise('enterprise');

  const ProfileKind(this.wire);

  final String wire;
}

/// How the bundle declares its launch screen.
@internal
enum LaunchScreenKind {
  uiLaunchScreen('UILaunchScreen'),
  storyboard('storyboard'),
  none('none');

  const LaunchScreenKind(this.wire);

  final String wire;
}

/// Where a `UILaunchScreen.UIImageName` resolves.
@internal
enum LaunchImageSource {
  looseFile('loose-file'),
  assetCatalog('asset-catalog'),
  missing('missing');

  const LaunchImageSource(this.wire);

  final String wire;
}

/// Framework bundle or loose dylib.
@internal
enum FrameworkKind {
  framework,
  dylib;

  String get wire => name;
}

/// Issue severity: `error` means a report section is incomplete.
@internal
enum IssueSeverity {
  warning,
  error;

  String get wire => name;
}

@internal
final class InputInfo {
  const InputInfo({
    required this.kind,
    required this.name,
    required this.sizeBytes,
    required this.sha256,
  });

  final InputKind kind;
  final String name;
  final int? sizeBytes;
  final String? sha256;

  Map<String, Object?> toJson() => {
    'kind': kind.wire,
    'name': name,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
  };
}

@internal
final class BundleInfo {
  const BundleInfo({
    required this.path,
    required this.bundleId,
    required this.name,
    required this.displayName,
    required this.shortVersion,
    required this.buildNumber,
    required this.executable,
    required this.minimumOSVersion,
    required this.deviceFamily,
    required this.infoPlistFormat,
    required this.infoPlistKeys,
    required this.plist,
    required this.xcrossPrivateKeys,
  });

  final String path;
  final String? bundleId;
  final String? name;
  final String? displayName;
  final String? shortVersion;
  final String? buildNumber;
  final String? executable;
  final String? minimumOSVersion;
  final List<int> deviceFamily;

  /// `"xml"`, `"binary"` or null when Info.plist is missing or unreadable.
  final String? infoPlistFormat;
  final List<String> infoPlistKeys;

  /// Allow-listed Info.plist values only, already mapped to JSON values.
  final Map<String, Object?> plist;

  /// Presence of `XCrossEntitlements`, `XCrossCapabilities`,
  /// `XCrossAppGroups`, in that order.
  final Map<String, bool> xcrossPrivateKeys;

  Map<String, Object?> toJson() => {
    'path': path,
    'bundleId': bundleId,
    'name': name,
    'displayName': displayName,
    'shortVersion': shortVersion,
    'buildNumber': buildNumber,
    'executable': executable,
    'minimumOSVersion': minimumOSVersion,
    'deviceFamily': deviceFamily,
    'infoPlistFormat': infoPlistFormat,
    'infoPlistKeys': infoPlistKeys,
    'plist': plist,
    'xcrossPrivateKeys': xcrossPrivateKeys,
  };
}

@internal
final class BundleSignature {
  const BundleSignature({
    required this.present,
    required this.kind,
    required this.teamId,
  });

  /// True exactly when `_CodeSignature/CodeResources` exists at the root.
  final bool present;
  final SignatureKind kind;
  final String? teamId;

  Map<String, Object?> toJson() => {
    'present': present,
    'kind': kind.wire,
    'teamId': teamId,
  };
}

@internal
final class ExecutableSignature {
  const ExecutableSignature({
    required this.kind,
    required this.linkerSigned,
    required this.identifier,
    required this.teamId,
  });

  static const unsigned = ExecutableSignature(
    kind: SignatureKind.none,
    linkerSigned: false,
    identifier: null,
    teamId: null,
  );

  final SignatureKind kind;
  final bool linkerSigned;
  final String? identifier;
  final String? teamId;

  Map<String, Object?> toJson() => {
    'kind': kind.wire,
    'linkerSigned': linkerSigned,
    'identifier': identifier,
    'teamId': teamId,
  };
}

@internal
final class ExecutableInfo {
  const ExecutableInfo({
    required this.path,
    required this.role,
    required this.architectures,
    required this.signature,
    required this.entitlements,
    required this.derEntitlementsPresent,
  });

  final String path;
  final ExecutableRole role;
  final List<String> architectures;
  final ExecutableSignature signature;

  /// Decoded XML entitlements (JSON values, keys sorted) or null.
  final Map<String, Object?>? entitlements;
  final bool derEntitlementsPresent;

  Map<String, Object?> toJson() => {
    'path': path,
    'role': role.wire,
    'architectures': architectures,
    'signature': signature.toJson(),
    'entitlements': entitlements,
    'derEntitlementsPresent': derEntitlementsPresent,
  };
}

@internal
final class ProfileSummary {
  const ProfileSummary({
    required this.kind,
    required this.name,
    required this.teamId,
    required this.uuid,
    required this.creationDate,
    required this.expirationDate,
    required this.platforms,
    required this.entitlements,
    required this.provisionsAllDevices,
    required this.deviceCount,
    required this.certificateCount,
  });

  final ProfileKind kind;
  final String? name;
  final String? teamId;
  final String? uuid;
  final String? creationDate;
  final String? expirationDate;
  final List<String> platforms;
  final Map<String, Object?> entitlements;
  final bool provisionsAllDevices;
  final int? deviceCount;
  final int certificateCount;

  Map<String, Object?> toJson() => {
    'kind': kind.wire,
    'name': name,
    'teamId': teamId,
    'uuid': uuid,
    'creationDate': creationDate,
    'expirationDate': expirationDate,
    'platforms': platforms,
    'entitlements': entitlements,
    'provisionsAllDevices': provisionsAllDevices,
    'deviceCount': deviceCount,
    'certificateCount': certificateCount,
  };
}

@internal
final class DeclaredIcon {
  const DeclaredIcon({
    required this.set,
    required this.name,
    required this.files,
  });

  /// `CFBundleIcons`, `CFBundleIcons~ipad` or `CFBundleIconFile`.
  final String set;
  final String name;
  final List<String> files;

  bool get resolved => files.isNotEmpty;

  Map<String, Object?> toJson() => {
    'set': set,
    'name': name,
    'files': files,
    'resolved': resolved,
  };
}

@internal
final class Icons {
  const Icons({required this.iconName, required this.declared});

  final String? iconName;
  final List<DeclaredIcon> declared;

  Map<String, Object?> toJson() => {
    'iconName': iconName,
    'declared': [for (final icon in declared) icon.toJson()],
  };
}

@internal
final class AssetsCar {
  const AssetsCar({required this.present, required this.sizeBytes});

  final bool present;
  final int? sizeBytes;

  Map<String, Object?> toJson() => {'present': present, 'sizeBytes': sizeBytes};
}

@internal
final class LaunchImage {
  const LaunchImage({required this.name, required this.source});

  final String name;
  final LaunchImageSource source;

  Map<String, Object?> toJson() => {'name': name, 'source': source.wire};
}

@internal
final class LaunchStoryboard {
  const LaunchStoryboard({required this.name, required this.compiledPresent});

  final String name;
  final bool compiledPresent;

  Map<String, Object?> toJson() => {
    'name': name,
    'compiledPresent': compiledPresent,
  };
}

@internal
final class LaunchScreen {
  const LaunchScreen({
    required this.kind,
    required this.keys,
    required this.image,
    required this.storyboard,
  });

  final LaunchScreenKind kind;
  final List<String> keys;
  final LaunchImage? image;
  final LaunchStoryboard? storyboard;

  Map<String, Object?> toJson() => {
    'kind': kind.wire,
    'keys': keys,
    'image': image?.toJson(),
    'storyboard': storyboard?.toJson(),
  };
}

@internal
final class Resources {
  const Resources({
    required this.icons,
    required this.assetsCar,
    required this.launchScreen,
    required this.storyboards,
  });

  final Icons icons;
  final AssetsCar assetsCar;
  final LaunchScreen launchScreen;
  final List<String> storyboards;

  Map<String, Object?> toJson() => {
    'icons': icons.toJson(),
    'assetsCar': assetsCar.toJson(),
    'launchScreen': launchScreen.toJson(),
    'storyboards': storyboards,
  };
}

@internal
final class FrameworkInfo {
  const FrameworkInfo({
    required this.name,
    required this.path,
    required this.kind,
    required this.bundleId,
  });

  final String name;
  final String path;
  final FrameworkKind kind;
  final String? bundleId;

  Map<String, Object?> toJson() => {
    'name': name,
    'path': path,
    'kind': kind.wire,
    'bundleId': bundleId,
  };
}

@internal
final class ExtensionInfo {
  const ExtensionInfo({
    required this.path,
    required this.bundleId,
    required this.extensionPoint,
    required this.executable,
    required this.profile,
  });

  final String path;
  final String? bundleId;
  final String? extensionPoint;
  final String? executable;
  final ProfileSummary? profile;

  Map<String, Object?> toJson() => {
    'path': path,
    'bundleId': bundleId,
    'extensionPoint': extensionPoint,
    'executable': executable,
    'profile': profile?.toJson(),
  };
}

@internal
final class Issue {
  const Issue({
    required this.code,
    required this.severity,
    required this.path,
    required this.message,
    required this.hint,
  });

  /// Issue for [code] with its contract hint.
  Issue.of(
    InspectCode code, {
    required this.severity,
    required this.message,
    this.path,
  }) : code = code.code,
       hint = code.hint;

  final String code;
  final IssueSeverity severity;
  final String? path;
  final String message;
  final String? hint;

  Map<String, Object?> toJson() => {
    'code': code,
    'severity': severity.wire,
    'path': path,
    'message': message,
    'hint': hint,
  };
}

/// The whole `xcross inspect` report.
@internal
final class InspectReport {
  InspectReport({
    required this.input,
    required this.bundle,
    required this.signature,
    required List<ExecutableInfo> executables,
    required this.profile,
    required this.resources,
    required List<FrameworkInfo> frameworks,
    required List<ExtensionInfo> extensions,
    required List<Issue> issues,
    this.normalized = false,
  }) : executables = List<ExecutableInfo>.unmodifiable(
         <ExecutableInfo>[...executables]
           ..sort((a, b) => a.path.compareTo(b.path)),
       ),
       frameworks = List<FrameworkInfo>.unmodifiable(
         <FrameworkInfo>[...frameworks]
           ..sort((a, b) => a.path.compareTo(b.path)),
       ),
       extensions = List<ExtensionInfo>.unmodifiable(
         <ExtensionInfo>[...extensions]
           ..sort((a, b) => a.path.compareTo(b.path)),
       ),
       issues = List<Issue>.unmodifiable(
         <Issue>[...issues]..sort(compareIssues),
       );

  static const schemaVersion = 1;

  final bool normalized;
  final InputInfo input;
  final BundleInfo bundle;
  final BundleSignature signature;
  final List<ExecutableInfo> executables;
  final ProfileSummary? profile;
  final Resources resources;
  final List<FrameworkInfo> frameworks;
  final List<ExtensionInfo> extensions;
  final List<Issue> issues;

  /// The main executable, if one was read.
  ExecutableInfo? get mainExecutable {
    for (final executable in executables) {
      if (executable.role == ExecutableRole.main) return executable;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'normalized': normalized,
    'input': input.toJson(),
    'bundle': bundle.toJson(),
    'signature': signature.toJson(),
    'executables': [for (final e in executables) e.toJson()],
    'profile': profile?.toJson(),
    'resources': resources.toJson(),
    'frameworks': [for (final f in frameworks) f.toJson()],
    'extensions': [for (final e in extensions) e.toJson()],
    'issues': [for (final i in issues) i.toJson()],
  };
}

/// Issue order: path (null first), then code, then message.
@internal
int compareIssues(Issue a, Issue b) {
  final pathA = a.path;
  final pathB = b.path;
  if (pathA != pathB) {
    if (pathA == null) return -1;
    if (pathB == null) return 1;
    final byPath = pathA.compareTo(pathB);
    if (byPath != 0) return byPath;
  }
  final byCode = a.code.compareTo(b.code);
  return byCode != 0 ? byCode : a.message.compareTo(b.message);
}
