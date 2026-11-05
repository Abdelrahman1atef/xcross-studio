// studio: 018 — rules about how the IPA is put together, not about one value in
// it. They need no list of Apple's error codes: each says "this does not hold
// together", the way App Store Connect finds out after an upload (90426 and
// 90429 were both this kind: Swift libraries in one folder and not the other).
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/inspect/inspect_report.dart';
import 'package:studio_ext/src/shared/inspect/inspect_source.dart';
import 'package:studio_ext/src/shared/inspect/plist_reader.dart';
import 'package:studio_ext/src/shared/release/macho_dylibs.dart';
import 'package:studio_ext/src/shared/release/release_checks.dart';

/// Architectures App Store Connect does not take: simulator slices and the
/// 32-bit ones.
const _unsupportedArchitectures = {'x86_64', 'i386', 'armv7', 'armv7s'};

/// The structure findings for [source], given its [report] and the bytes of
/// each binary in [binaries] (by path inside the app).
@internal
List<ReleaseIssue> structureIssues({
  required InspectSource source,
  required InspectReport report,
  required Map<String, Uint8List> binaries,
}) => [
  ..._nestedSignatures(report),
  ..._architectures(report),
  ..._dependencies(source, binaries),
  ..._swiftMirror(source),
  ..._frameworkPlists(source, report),
  ..._looseLibraries(source),
];

/// Apple: iOS apps carry dynamic libraries only inside framework bundles (the
/// Swift runtime is the exception), and no static library at all. A loose
/// `libX.dylib` is what App Store Connect's 90429 is really about, though it
/// names the Swift libraries.
Iterable<ReleaseIssue> _looseLibraries(InspectSource source) sync* {
  for (final file in source.files) {
    if (file.contains('.framework/')) continue;
    final name = file.split('/').last;
    if (name.endsWith('.dylib') && !name.startsWith('libswift')) {
      yield ReleaseIssue(
        'release.loose_dylib',
        ReleaseSeverity.error,
        '$file is a dynamic library outside a framework; iOS allows those '
            'only inside a .framework, and App Store Connect answers 90429 '
            '(often naming the Swift libraries instead).',
        path: file,
        hint:
            'Build again with a current xcross, which wraps the plugin '
            'library in a framework, or ship the library as a framework.',
      );
    } else if (name.endsWith('.a')) {
      yield ReleaseIssue(
        'release.static_library_in_bundle',
        ReleaseSeverity.error,
        '$file is a static library inside the app; its code belongs in a '
            'binary at build time, and App Store Connect refuses it.',
        path: file,
        hint: 'Link it into the app and leave it out of the copy-files steps.',
      );
    }
  }
}

/// Every binary inside the app carries a signature of the app's own team.
Iterable<ReleaseIssue> _nestedSignatures(InspectReport report) sync* {
  final main = report.executables
      .where((e) => e.role == ExecutableRole.main)
      .firstOrNull;
  final team = main?.signature.teamId;
  for (final executable in report.executables) {
    if (executable.role == ExecutableRole.main) continue;
    final signature = executable.signature;
    if (signature.kind == SignatureKind.none) {
      yield ReleaseIssue(
        'release.nested_not_signed',
        ReleaseSeverity.error,
        '${executable.path} is not signed; App Store Connect refuses an app '
            'with unsigned code inside it.',
        path: executable.path,
        hint:
            'Build again with `--export-method app-store`; it signs every '
            'framework and library.',
      );
    } else if (team != null &&
        signature.teamId != null &&
        signature.teamId != team) {
      yield ReleaseIssue(
        'release.nested_team_mismatch',
        ReleaseSeverity.error,
        '${executable.path} is signed by team ${signature.teamId}, the app by '
            '$team; App Store Connect refuses mixed teams.',
        path: executable.path,
        hint:
            'Build again so everything is signed with one distribution '
            'identity.',
      );
    }
  }
}

Iterable<ReleaseIssue> _architectures(InspectReport report) sync* {
  for (final executable in report.executables) {
    final bad = [
      for (final architecture in executable.architectures)
        if (_unsupportedArchitectures.contains(architecture)) architecture,
    ];
    if (bad.isEmpty) continue;
    yield ReleaseIssue(
      'release.unsupported_architecture',
      ReleaseSeverity.error,
      '${executable.path} has ${bad.join(', ')} code; an App Store app is '
          '64-bit ARM only (a simulator or 32-bit slice is refused).',
      path: executable.path,
      hint: 'Use a device build of that framework, or strip the slice.',
    );
  }
}

/// Every library a binary loads from inside the app is in the app. The OS
/// ones (`/usr/lib`, `/System`) and the Swift runtime (its own rule) are not
/// looked for.
Iterable<ReleaseIssue> _dependencies(
  InspectSource source,
  Map<String, Uint8List> binaries,
) sync* {
  final reported = <String>{};
  for (final MapEntry(key: path, value: bytes) in binaries.entries) {
    final folder = path.contains('/')
        ? path.substring(0, path.lastIndexOf('/'))
        : '';
    String near(String relative) =>
        folder.isEmpty ? relative : '$folder/$relative';
    for (final library in MachODylib.read(bytes)) {
      if (library.weak || library.isSwiftRuntime) continue;
      final String relative;
      if (library.path.startsWith('@rpath/')) {
        relative = library.path.substring('@rpath/'.length);
      } else if (library.path.startsWith('@executable_path/')) {
        relative = library.path.substring('@executable_path/'.length);
      } else if (library.path.startsWith('@loader_path/')) {
        relative = library.path.substring('@loader_path/'.length);
      } else {
        continue;
      }
      final found = {
        'Frameworks/$relative',
        relative,
        near(relative),
        near('Frameworks/$relative'),
      }.any(source.hasFile);
      if (found || !reported.add('$path>${library.path}')) continue;
      yield ReleaseIssue(
        'release.dependency_missing',
        ReleaseSeverity.error,
        '$path loads ${library.path}, which is not in the app; it ends at '
            'launch.',
        path: path,
        hint: 'Embed the framework or library, or link it statically.',
      );
    }
  }
}

/// The Swift runtime libraries embedded in `Frameworks` are the ones in
/// `SwiftSupport/iphoneos`, and the other way round is its own rule: Xcode
/// writes the same set to both.
Iterable<ReleaseIssue> _swiftMirror(InspectSource source) sync* {
  if (source.kind != InputKind.ipa) return;
  const folder = 'SwiftSupport/iphoneos/';
  final packed = {
    for (final file in source.outsideFiles)
      if (file.startsWith(folder)) file.substring(folder.length),
  };
  final embedded = [
    for (final file in source.files)
      if (file.startsWith('Frameworks/libswift') &&
          file.endsWith('.dylib') &&
          !file.substring('Frameworks/'.length).contains('/'))
        file.substring('Frameworks/'.length),
  ];
  final unmatched = [
    for (final name in embedded)
      if (!packed.contains(name)) name,
  ]..sort();
  if (unmatched.isEmpty) return;
  yield ReleaseIssue(
    'release.swift_support_incomplete',
    ReleaseSeverity.error,
    'The app embeds ${unmatched.take(3).join(', ')}'
        '${unmatched.length > 3 ? ', …' : ''} but SwiftSupport/iphoneos does '
        'not hold it; App Store Connect compares the two folders.',
    path: 'SwiftSupport/iphoneos',
    hint: 'Build again with `--export-method app-store`.',
  );
}

/// A framework's own Info.plist names what it is: App Store Connect reads its
/// version keys.
Iterable<ReleaseIssue> _frameworkPlists(
  InspectSource source,
  InspectReport report,
) sync* {
  for (final framework in report.frameworks) {
    if (framework.kind != FrameworkKind.framework) continue;
    final bytes = source.read('${framework.path}/Info.plist');
    final plist = bytes == null ? null : readPlist(bytes)?.dictionary;
    final missing = [
      for (final key in const [
        'CFBundleExecutable',
        'CFBundleIdentifier',
        'CFBundleVersion',
        'CFBundleShortVersionString',
      ])
        if (plist == null || plist[key] is! String || plist[key] == '') key,
    ];
    if (missing.isEmpty) continue;
    yield ReleaseIssue(
      'release.framework_plist_incomplete',
      ReleaseSeverity.warning,
      '${framework.name} has no ${missing.join(', ')} in its Info.plist; App '
          'Store Connect reads these for every framework.',
      path: '${framework.path}/Info.plist',
      hint: 'Add them to the framework, or update the plugin that ships it.',
    );
  }
}
