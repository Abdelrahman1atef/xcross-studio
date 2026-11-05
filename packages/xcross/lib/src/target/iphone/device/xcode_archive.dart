// studio: 018 — `.xcarchive` and dSYMs for an App Store export
// (specs/018-app-store-build, AC-018-1, AC-018-5).
import 'dart:io';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:cli_kit/shared/process/process.dart';
import 'package:meta/meta.dart';
import 'package:propertylistserialization/propertylistserialization.dart';

/// What the archive's `Info.plist` records about the app.
@internal
@immutable
final class ArchivedApp {
  const ArchivedApp({
    required this.bundleId,
    required this.shortVersion,
    required this.buildNumber,
    required this.signingIdentity,
    required this.teamId,
  });

  final String bundleId;
  final String shortVersion;
  final String buildNumber;

  /// The certificate's common name, such as `Apple Distribution: Team (ID)`.
  final String signingIdentity;
  final String teamId;
}

/// Writes `Runner.xcarchive` the way Xcode and `flutter build ipa` lay it out:
/// `Info.plist`, `Products/Applications/<app>.app` and `dSYMs/`.
@internal
final class XcodeArchiveWriter<T extends PlatformHostInterface> {
  XcodeArchiveWriter({required this.runner, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final ProcessRunner<T> runner;
  final DateTime Function() _clock;

  HostFileSystemInterface get _files => runner.host.fileSystem;

  /// Copies the signed [appPath] into a fresh archive at [archivePath] and
  /// returns the binaries no dSYM could be made for (empty when all were).
  Future<List<String>> write({
    required String appPath,
    required String archivePath,
    required ArchivedApp app,
    Map<String, String> swiftSupport = const {}, // studio: 018
  }) async {
    final paths = runner.host.paths.context;
    final archive = _files.directory(archivePath);
    if (archive.existsSync()) await archive.delete(recursive: true);
    final appName = paths.basename(appPath);
    final applications = paths.join(archivePath, 'Products', 'Applications');
    await _copyDirectory(appPath, paths.join(applications, appName));
    final dsyms = paths.join(archivePath, 'dSYMs');
    await _files.directory(dsyms).create(recursive: true);
    // studio: 018 — Xcode keeps the Swift runtime libraries here too.
    for (final MapEntry(key: name, value: source) in swiftSupport.entries) {
      final target = paths.joinAll([archivePath, ...name.split('/')]);
      await _files.directory(paths.dirname(target)).create(recursive: true);
      await _files.file(source).copy(target);
    }

    await _files
        .file(paths.join(archivePath, 'Info.plist'))
        .writeAsString(infoPlist(app, appName: appName, created: _clock()));

    final missing = <String>[];
    final dsymutil = await _dsymutil();
    for (final binary in binariesOf(appPath)) {
      final name = paths.basename(binary);
      final container = paths.basename(paths.dirname(binary));
      final dsymName = container.endsWith('.framework')
          ? '$container.dSYM'
          : '$name.${container.endsWith('.app') ? 'app' : 'dylib'}.dSYM';
      if (dsymutil == null) {
        missing.add(name);
        continue;
      }
      try {
        await runner.runChecked(dsymutil, [
          binary,
          '-o',
          paths.join(dsyms, dsymName),
        ], label: 'dsymutil');
      } on Object {
        missing.add(name);
      }
    }
    return missing;
  }

  /// The main executable, `App.framework/App` and every other framework or
  /// dylib binary under `Frameworks/`.
  @visibleForTesting
  List<String> binariesOf(String appPath) {
    final paths = runner.host.paths.context;
    final result = <String>[];
    final plist = _files.file(paths.join(appPath, 'Info.plist'));
    if (plist.existsSync()) {
      try {
        final executable =
            (PropertyListSerialization.propertyListWithString(
                  plist.readAsStringSync(),
                )
                as Map)['CFBundleExecutable'];
        if (executable is String) {
          final main = paths.join(appPath, executable);
          if (_files.file(main).existsSync()) result.add(main);
        }
      } on Object {
        // A binary plist from another tool: archived without the main dSYM.
      }
    }
    final frameworksPath = paths.join(appPath, 'Frameworks');
    final frameworks = _files.directory(frameworksPath);
    if (frameworks.existsSync()) {
      // Paths are built from [appPath], not the listing, so tools get the
      // plain form (no long-path prefix).
      final names = [
        for (final entity in frameworks.listSync()) paths.basename(entity.path),
      ]..sort();
      for (final name in names) {
        if (name.endsWith('.framework')) {
          final binary = paths.join(
            frameworksPath,
            name,
            paths.basenameWithoutExtension(name),
          );
          if (_files.file(binary).existsSync()) result.add(binary);
        } else if (name.endsWith('.dylib')) {
          result.add(paths.join(frameworksPath, name));
        }
      }
    }
    return result;
  }

  /// The archive `Info.plist`.
  @visibleForTesting
  static String infoPlist(
    ArchivedApp app, {
    required String appName,
    required DateTime created,
  }) => PropertyListSerialization.stringWithPropertyList(<String, Object>{
    'ApplicationProperties': <String, Object>{
      'ApplicationPath': 'Applications/$appName',
      'Architectures': ['arm64'],
      'CFBundleIdentifier': app.bundleId,
      'CFBundleShortVersionString': app.shortVersion,
      'CFBundleVersion': app.buildNumber,
      'SigningIdentity': app.signingIdentity,
      'Team': app.teamId,
    },
    'ArchiveVersion': 2,
    'CreationDate': created.toUtc(),
    'Name': 'Runner',
    'SchemeName': 'Runner',
  });

  Future<String?> _dsymutil() async {
    try {
      return await runner.locateTool('dsymutil');
    } on Object {
      return null;
    }
  }

  Future<void> _copyDirectory(String from, String to) async {
    final paths = runner.host.paths.context;
    await _files.directory(to).create(recursive: true);
    final source = _files.directory(from);
    // Listed paths carry the host's I/O form (a long-path prefix on
    // Windows), so they are made relative to the listed directory itself.
    for (final entity in source.listSync(recursive: true)) {
      final relative = paths.relative(entity.path, from: source.path);
      final target = paths.join(to, relative);
      if (entity is Directory) {
        await _files.directory(target).create(recursive: true);
      } else if (entity is File) {
        await _files.file(target).parent.create(recursive: true);
        await entity.copy(_files.file(target).path);
      }
    }
  }
}
