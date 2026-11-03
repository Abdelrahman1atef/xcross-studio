// studio: 016 — clang module maps of the plugin build's C-family targets, for
// the project runner (specs/016-push-firebase-maps, AC-016-10).
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:xcross/src/shared/flutter/swiftpm/artifact_filesystem.dart';

/// One `<products>/<Target>.build/module.modulemap` SwiftPM generated, and
/// the folder its umbrella header or umbrella directory lives in.
@internal
@immutable
final class SwiftPmModuleMap {
  const SwiftPmModuleMap({required this.path, this.includeDirectory});

  /// Process path of the module map.
  final String path;

  /// Process path of the public headers folder, when the map names one.
  final String? includeDirectory;

  /// `swiftc` arguments.
  List<String> get swiftArguments => [
    '-Xcc',
    '-fmodule-map-file=$path',
    if (includeDirectory case final include?) ...['-Xcc', '-I$include'],
  ];

  /// `clang` arguments.
  List<String> get clangArguments => [
    '-fmodule-map-file=$path',
    if (includeDirectory case final include?) '-I$include',
  ];

  static final _umbrellaHeader = RegExp(
    r'''module\s+([A-Za-z0-9_]+)[^{]*\{[^}]*?umbrella\s+header\s+"([^"]+)"''',
  );
  static final _umbrellaDirectory = RegExp(r'''umbrella\s+"([^"]+)"''');

  /// Every generated module map directly below [productsDirectory] (the
  /// folder holding the plugins library), sorted.
  static List<SwiftPmModuleMap> discover(
    SwiftPmArtifactFileSystem fileSystem,
    String productsDirectory,
  ) {
    final directory = fileSystem.directory(productsDirectory);
    if (!directory.existsSync()) return const [];
    final List<FileSystemEntity> children;
    try {
      children = directory.listSync(followLinks: false);
    } on FileSystemException {
      return const [];
    }
    final maps = <SwiftPmModuleMap>[];
    for (final child in children) {
      if (!child.path.endsWith('.build')) continue;
      final file = fileSystem.file(p.join(child.path, 'module.modulemap'));
      if (!file.existsSync()) continue;
      final include = includeDirectoryOf(file.readAsStringSync());
      maps.add(
        SwiftPmModuleMap(
          path: fileSystem.processPath(file.path),
          includeDirectory: include,
        ),
      );
    }
    return maps..sort((a, b) => a.path.compareTo(b.path));
  }

  /// The headers folder a module map's umbrella points into: the umbrella
  /// directory itself, or the umbrella header's folder (its parent when that
  /// folder is named after the module, as in `Public/FirebaseCore/`, so
  /// `<FirebaseCore/FIRApp.h>` resolves).
  @visibleForTesting
  static String? includeDirectoryOf(String moduleMap) {
    final header = _umbrellaHeader.firstMatch(moduleMap);
    if (header != null) {
      final module = header.group(1)!;
      final path = header.group(2)!.replaceAll(r'\\', r'\');
      final context = path.contains(r'\') ? p.windows : p.posix;
      final folder = context.dirname(path);
      return context.basename(folder) == module
          ? context.dirname(folder)
          : folder;
    }
    final umbrella = _umbrellaDirectory.firstMatch(moduleMap);
    return umbrella?.group(1)!.replaceAll(r'\\', r'\');
  }
}
