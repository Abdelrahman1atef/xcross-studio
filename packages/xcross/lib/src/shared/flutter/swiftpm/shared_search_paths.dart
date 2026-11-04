// studio: 006 — Xcode's project-wide search paths for prebuilt xcframeworks.
import 'dart:io';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:xcross/src/shared/flutter/swiftpm/artifact_filesystem.dart';
import 'package:xcross/src/target/shared/flutter/flutter_target_build_policy.dart';

/// Search flags that make every resolved xcframework visible to every target,
/// the way Xcode does: it copies the headers of static-library xcframeworks
/// into one shared `include/` folder and frameworks into one products folder.
///
/// Packages rely on it. Google's ios-maps-sdk `GoogleMapsCoreTarget` depends
/// only on `GoogleMapsCore` yet compiles `@import GoogleMaps;`, which a plain
/// `swift build` rejects with "module 'GoogleMaps' not found" (a client app,
/// 2026-11-02).
@internal
final class SwiftPmSharedSearchPaths<T extends PlatformHostInterface> {
  SwiftPmSharedSearchPaths({
    required this.fileSystem,
    required this.targetPolicy,
  });

  final SwiftPmArtifactFileSystem fileSystem;
  final FlutterTargetBuildPolicy<T> targetPolicy;

  /// Folders below [scratchPath] that hold resolved binary targets:
  /// xcross's materialized `checkouts/<package>/.xa/<id>/` and SwiftPM's own
  /// `artifacts/`.
  static const int _maxDepth = 4;

  /// `-Xcc`/`-Xswiftc` header and framework search flags for every
  /// xcframework of the resolved graph under [scratchPath].
  List<String> arguments(String scratchPath) {
    final includes = <String>{};
    final frameworks = <String>{};
    for (final xcframework in xcframeworks(scratchPath)) {
      for (final library in _libraries(xcframework)) {
        final slice = p.join(xcframework, library.identifier);
        final headers = library.headersPath;
        if (headers != null) {
          final dir = p.join(slice, headers);
          if (fileSystem.directory(dir).existsSync()) includes.add(dir);
        }
        if (library.libraryPath.endsWith('.framework')) frameworks.add(slice);
      }
    }
    final sortedIncludes = includes.toList()..sort();
    final sortedFrameworks = frameworks.toList()..sort();
    return [
      for (final dir in sortedIncludes) ...[
        '-Xcc',
        '-I${fileSystem.processPath(dir)}',
        '-Xswiftc',
        '-I',
        '-Xswiftc',
        fileSystem.processPath(dir),
      ],
      for (final dir in sortedFrameworks) ...[
        '-Xcc',
        '-F${fileSystem.processPath(dir)}',
        '-Xswiftc',
        '-F',
        '-Xswiftc',
        fileSystem.processPath(dir),
      ],
    ];
  }

  /// Every `*.xcframework` directory under `checkouts/` and `artifacts/`,
  /// without descending into one.
  @visibleForTesting
  List<String> xcframeworks(String scratchPath) {
    final found = <String>[];
    void walk(Directory directory, int depth) {
      final List<FileSystemEntity> children;
      try {
        children = directory.listSync(followLinks: false);
      } on FileSystemException {
        return;
      }
      for (final child in children) {
        final isDirectory =
            fileSystem.typeSync(child.path) == FileSystemEntityType.directory;
        if (!isDirectory) continue;
        if (child.path.toLowerCase().endsWith('.xcframework')) {
          found.add(child.path);
        } else if (depth < _maxDepth) {
          walk(fileSystem.directory(child.path), depth + 1);
        }
      }
    }

    for (final root in ['checkouts', 'artifacts']) {
      final directory = fileSystem.directory(p.join(scratchPath, root));
      if (directory.existsSync()) walk(directory, 1);
    }
    return found..sort();
  }

  List<XcframeworkLibrary> _libraries(String xcframework) {
    final info = fileSystem.file(p.join(xcframework, 'Info.plist'));
    if (!info.existsSync()) return const [];
    try {
      final plist = PropertyListSerialization.propertyListWithString(
        info.readAsStringSync(),
      );
      final libraries = plist is Map ? plist['AvailableLibraries'] : null;
      if (libraries is! List) return const [];
      return [
        for (final library in libraries)
          if (library is Map &&
              library['SupportedPlatform'] == 'ios' &&
              targetPolicy.matchesLibraryVariant(
                library['SupportedPlatformVariant'] as String?,
              ) &&
              library['SupportedArchitectures'] is List &&
              (library['SupportedArchitectures'] as List).contains('arm64') &&
              library['LibraryIdentifier'] is String &&
              library['LibraryPath'] is String)
            XcframeworkLibrary(
              identifier: library['LibraryIdentifier'] as String,
              libraryPath: library['LibraryPath'] as String,
              headersPath: library['HeadersPath'] as String?,
            ),
      ];
    } on Object {
      return const [];
    }
  }
}

/// One `AvailableLibraries` entry of an xcframework.
@internal
final class XcframeworkLibrary {
  const XcframeworkLibrary({
    required this.identifier,
    required this.libraryPath,
    required this.headersPath,
  });

  final String identifier;
  final String libraryPath;
  final String? headersPath;
}
