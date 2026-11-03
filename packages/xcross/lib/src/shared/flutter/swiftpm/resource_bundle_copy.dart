// studio: 018 — SwiftPM resource bundles embedded in the app hold files,
// never symbolic links (specs/018-app-store-build).
import 'dart:io';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Copies a SwiftPM resource bundle (`<Package>_<Target>.bundle`) into an app.
///
/// A `.copy` resource that is a symbolic link in its package is copied by
/// SwiftPM as the same link: SDWebImage's
/// `SDWebImage/Resources/PrivacyInfo.xcprivacy` points at
/// `../../WebImage/PrivacyInfo.xcprivacy`, which resolves in the checkout but
/// not in the bundle. The copy writes the file a link points at; a link that
/// does not resolve where SwiftPM left it is looked up in the package sources.
@internal
final class ResourceBundleCopier {
  const ResourceBundleCopier({required this.fileSystem, required this.paths});

  final HostFileSystemInterface fileSystem;
  final p.Context paths;

  /// Links to folders are followed at most this deep, so a link cycle ends.
  static const _maxDepth = 32;

  /// Copies [source] to [destination] with every link replaced by its
  /// target. A link that does not resolve is matched against a link with the
  /// same name and target under [packageRoots] (the package checkouts and the
  /// plugin packages); one that matches nothing is left out and its path,
  /// relative to [source], returned.
  Future<List<String>> copy(
    String source,
    String destination, {
    List<String> packageRoots = const [],
  }) async {
    final skipped = <String>[];
    await _copyTree(
      source,
      destination,
      relative: '',
      packageRoots: packageRoots,
      skipped: skipped,
      depth: 0,
    );
    return skipped;
  }

  Future<void> _copyTree(
    String from,
    String to, {
    required String relative,
    required List<String> packageRoots,
    required List<String> skipped,
    required int depth,
  }) async {
    await fileSystem.directory(to).create(recursive: true);
    final entries = fileSystem.directory(from).listSync(followLinks: false)
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final entity in entries) {
      // Paths are rebuilt from the listed name: a long path may be listed
      // with a `\\?\` prefix the source path does not have.
      final name = paths.basename(entity.path);
      final sourcePath = paths.join(from, name);
      final targetPath = paths.join(to, name);
      final entryRelative = relative.isEmpty ? name : '$relative/$name';
      var path = sourcePath;
      if (entity is Link) {
        final resolved =
            _resolve(sourcePath) ?? _recover(sourcePath, packageRoots);
        if (resolved == null || depth >= _maxDepth) {
          skipped.add(entryRelative);
          continue;
        }
        path = resolved;
      }
      if (fileSystem.directory(path).existsSync()) {
        await _copyTree(
          path,
          targetPath,
          relative: entryRelative,
          packageRoots: packageRoots,
          skipped: skipped,
          depth: entity is Link ? depth + 1 : depth,
        );
      } else if (fileSystem.file(path).existsSync()) {
        await fileSystem.file(path).copy(targetPath);
      }
    }
  }

  /// The file or folder [linkPath] points at, or null when it dangles.
  String? _resolve(String linkPath) {
    try {
      final resolved = fileSystem.link(linkPath).resolveSymbolicLinksSync();
      return fileSystem.file(resolved).existsSync() ||
              fileSystem.directory(resolved).existsSync()
          ? resolved
          : null;
    } on FileSystemException {
      return null;
    }
  }

  /// The target of a link in [packageRoots] with the name and target text of
  /// the dangling [linkPath]: the link SwiftPM copied it from.
  String? _recover(String linkPath, List<String> packageRoots) {
    final String wanted;
    try {
      wanted = _targetText(fileSystem.link(linkPath).targetSync());
    } on FileSystemException {
      return null;
    }
    final name = paths.basename(linkPath);
    for (final root in packageRoots) {
      final directory = fileSystem.directory(root);
      if (!directory.existsSync()) continue;
      final List<FileSystemEntity> entries;
      try {
        entries = directory.listSync(recursive: true, followLinks: false);
      } on FileSystemException {
        continue;
      }
      for (final entity in entries) {
        if (entity is! Link || paths.basename(entity.path) != name) continue;
        try {
          if (_targetText(fileSystem.link(entity.path).targetSync()) !=
              wanted) {
            continue;
          }
        } on FileSystemException {
          continue;
        }
        final resolved = _resolve(entity.path);
        if (resolved != null) return resolved;
      }
    }
    return null;
  }

  static String _targetText(String target) => target.replaceAll(r'\', '/');
}
