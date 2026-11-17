import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Normalizes and handles C99 identifier rules and header directory layout (§7.1, §8.5).
@internal
final class PodSourceLayout {
  const PodSourceLayout({
    required this.directoryFactory,
    required this.fileFactory,
    required this.linkFactory,
    void Function(File source, File destination)? hardLinker,
  }) : _customHardLinker = hardLinker;

  final Directory Function(String) directoryFactory;
  final File Function(String) fileFactory;
  final Link Function(String) linkFactory;
  final void Function(File source, File destination)? _customHardLinker;

  void _hardLink(File source, File destination) {
    final custom = _customHardLinker;
    if (custom != null) {
      custom(source, destination);
      return;
    }
    destination.parent.createSync(recursive: true);
    if (destination.existsSync()) destination.deleteSync();
    try {
      linkFactory(destination.path).createSync(source.path);
    } on Object {
      // If symlink/hardlink is not supported, fall back to copy
      source.copySync(destination.path);
    }
  }

  /// Converts a pod name to a valid C99 identifier (as CocoaPods c99ext_identifier).
  static String c99Identifier(String name) {
    var result = name.replaceAll(RegExp('[^a-zA-Z0-9_]'), '_');
    result = result.replaceAll(RegExp('_+'), '_');
    if (result.isNotEmpty && RegExp('^[0-9]').hasMatch(result)) {
      result = '_$result';
    }
    return result;
  }

  /// Normalizes `header_dir` attribute. Returns null if '.' or './' or empty.
  static String? normalizeHeaderDir(String? headerDir) {
    if (headerDir == null) return null;
    final trimmed = headerDir.trim();
    if (trimmed.isEmpty ||
        trimmed == '.' ||
        trimmed == './' ||
        trimmed == r'.\') {
      return null;
    }
    final normalized = p.posix.normalize(trimmed.replaceAll(r'\', '/'));
    if (normalized == '.' || normalized.isEmpty) return null;
    return normalized;
  }

  /// Generates the directory structure, header trees, umbrella header, and vers.c for a pod.
  void layOutPod({
    required Directory packageDir,
    required String podName,
    required String version,
    required String moduleName,
    required Map<String, File> sourceFiles,
    required Map<String, File> publicHeaders,
    required Map<String, File> privateHeaders,
    String? headerDir,
    String? headerMappingsDir,
    String? customModuleMap,
    bool moduleMapDisabled = false,
  }) {
    final sourcesDir = directoryFactory(
      p.join(packageDir.path, 'Sources', moduleName),
    );
    sourcesDir.createSync(recursive: true);

    // 1. Copy sources and all headers into Sources/<Module>/ keeping relative paths
    final stagedSources = <String, File>{};
    for (final entry in sourceFiles.entries) {
      final destFile = fileFactory(p.join(sourcesDir.path, entry.key));
      destFile.parent.createSync(recursive: true);
      entry.value.copySync(destFile.path);
      stagedSources[entry.key] = destFile;
    }

    final allHeaders = <String, File>{...privateHeaders, ...publicHeaders};
    final stagedHeaders = <String, File>{};
    for (final entry in allHeaders.entries) {
      final destFile = fileFactory(p.join(sourcesDir.path, entry.key));
      destFile.parent.createSync(recursive: true);
      if (!destFile.existsSync()) {
        entry.value.copySync(destFile.path);
      }
      stagedHeaders[entry.key] = destFile;
    }

    // 2. Generate Sources/<Module>/xcross/vers.c
    _generateVersC(
      sourcesDir: sourcesDir,
      podName: podName,
      version: version,
      moduleName: moduleName,
    );

    // 3. Lay out Public Headers: Headers/Public/<Module>/...
    final publicBase = directoryFactory(
      p.join(packageDir.path, 'Headers', 'Public'),
    );
    final modulePublicDir = directoryFactory(
      p.join(publicBase.path, moduleName),
    );
    modulePublicDir.createSync(recursive: true);

    final normalizedHDir = normalizeHeaderDir(headerDir);
    final linkAliases = <Directory>[];

    // Alias: <PodName>/ when it differs from <Module>, case included:
    // `<Protobuf/...>` must resolve to module `protobuf` on case-sensitive
    // hosts (Linux). On case-insensitive hosts the alias is the same
    // directory and re-linking it is harmless.
    if (podName != moduleName) {
      linkAliases.add(directoryFactory(p.join(publicBase.path, podName)));
    }
    // Alias: <header_dir>/ when set
    if (normalizedHDir != null &&
        normalizedHDir != moduleName &&
        normalizedHDir != podName) {
      linkAliases.add(
        directoryFactory(p.join(publicBase.path, normalizedHDir)),
      );
    }

    final publicHeaderNames = <String>[];
    for (final entry in publicHeaders.entries) {
      final stagedFile = stagedHeaders[entry.key] ?? stagedSources[entry.key]!;
      final relHeaderPath = _headerRelativePath(entry.key, headerMappingsDir);
      final destHeader = fileFactory(
        p.join(modulePublicDir.path, relHeaderPath),
      );
      _hardLink(stagedFile, destHeader);
      publicHeaderNames.add(relHeaderPath);

      for (final aliasDir in linkAliases) {
        final aliasHeader = fileFactory(p.join(aliasDir.path, relHeaderPath));
        _hardLink(stagedFile, aliasHeader);
      }
    }

    // 4. Lay out Private Headers: Headers/Private/<Module>/...
    final privateBase = directoryFactory(
      p.join(packageDir.path, 'Headers', 'Private', moduleName),
    );
    privateBase.createSync(recursive: true);
    for (final entry in allHeaders.entries) {
      final stagedFile = stagedHeaders[entry.key] ?? stagedSources[entry.key]!;
      final relHeaderPath = _headerRelativePath(entry.key, headerMappingsDir);
      final destHeader = fileFactory(p.join(privateBase.path, relHeaderPath));
      _hardLink(stagedFile, destHeader);
    }

    // 5. Generate or copy umbrella header and module.modulemap in Headers/Public/
    if (!moduleMapDisabled) {
      if (customModuleMap != null && customModuleMap.isNotEmpty) {
        final destMap = fileFactory(
          p.join(publicBase.path, 'module.modulemap'),
        );
        destMap.parent.createSync(recursive: true);
        destMap.writeAsStringSync(customModuleMap);
      } else {
        _generateUmbrellaAndModuleMap(
          publicBaseDir: publicBase,
          moduleName: moduleName,
          publicHeaders: publicHeaderNames,
        );
      }
    }
  }

  static String _headerRelativePath(String originalPath, String? mappingsDir) {
    final normalized = originalPath.replaceAll(r'\', '/');
    if (mappingsDir != null && mappingsDir.isNotEmpty) {
      final normMapping = mappingsDir
          .replaceAll(r'\', '/')
          .replaceAll(RegExp(r'^/+|/+$'), '');
      if (normalized.startsWith('$normMapping/')) {
        return normalized.substring(normMapping.length + 1);
      }
    }
    // Flattened by default
    return p.basename(normalized);
  }

  void _generateVersC({
    required Directory sourcesDir,
    required String podName,
    required String version,
    required String moduleName,
  }) {
    final xcrossDir = directoryFactory(p.join(sourcesDir.path, 'xcross'));
    xcrossDir.createSync(recursive: true);
    final versFile = fileFactory(p.join(xcrossDir.path, 'vers.c'));

    // Extract double version number (e.g. 1.2.3 -> 1.2)
    final versionMatch = RegExp(r'^(\d+(?:\.\d+)?)').firstMatch(version);
    final versionDouble = versionMatch != null ? versionMatch.group(1)! : '1.0';

    final content =
        '''
#ifdef __cplusplus
extern "C" {
#endif
const double ${moduleName}VersionNumber __attribute__((used)) = (double)$versionDouble;
const unsigned char ${moduleName}VersionString[] __attribute__((used)) = "@(#)PROGRAM:$moduleName  PROJECT:$podName-$version\\n";
#ifdef __cplusplus
}
#endif
''';
    versFile.writeAsStringSync(content);
  }

  void _generateUmbrellaAndModuleMap({
    required Directory publicBaseDir,
    required String moduleName,
    required List<String> publicHeaders,
  }) {
    // 1. Umbrella header: Headers/Public/<Module>/<Module>-umbrella.h
    final umbrellaFile = fileFactory(
      p.join(publicBaseDir.path, moduleName, '$moduleName-umbrella.h'),
    );
    umbrellaFile.parent.createSync(recursive: true);

    final buffer = StringBuffer();
    buffer.writeln('#ifdef __OBJC__');
    buffer.writeln('#import <Foundation/Foundation.h>');
    buffer.writeln('#if __has_include(<UIKit/UIKit.h>)');
    buffer.writeln('#import <UIKit/UIKit.h>');
    buffer.writeln('#endif');
    buffer.writeln('#endif');
    buffer.writeln();

    final sortedHeaders = publicHeaders.toSet().toList()..sort();
    for (final header in sortedHeaders) {
      buffer.writeln('#import "$header"');
    }
    buffer.writeln();
    buffer.writeln('FOUNDATION_EXPORT double ${moduleName}VersionNumber;');
    buffer.writeln(
      'FOUNDATION_EXPORT const unsigned char ${moduleName}VersionString[];',
    );

    umbrellaFile.writeAsStringSync(buffer.toString());

    // 2. module.modulemap: Headers/Public/module.modulemap
    final moduleMapFile = fileFactory(
      p.join(publicBaseDir.path, 'module.modulemap'),
    );
    final mapContent =
        '''
framework module $moduleName {
  umbrella header "$moduleName/$moduleName-umbrella.h"
  export *
  module * { export * }
}
''';
    moduleMapFile.writeAsStringSync(mapContent);
  }
}
