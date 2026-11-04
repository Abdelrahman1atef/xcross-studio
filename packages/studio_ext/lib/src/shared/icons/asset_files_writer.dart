// studio: 024 — writes generated icons and splash files into a project (after
// a backup), a folder or an archive (specs/024-icon-splash-studio, AC-024-15,
// AC-024-16).
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Files are keyed by project-relative path, with `/` separators.
@internal
final class AssetFilesWriter {
  const AssetFilesWriter(this.fileSystem);

  final HostFileSystemInterface fileSystem;

  /// `yyyyMMdd-HHmmss`, the backup folder's name.
  static String stamp(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  void writeFiles(String base, Map<String, Uint8List> files) {
    for (final MapEntry(:key, :value) in files.entries) {
      final file = fileSystem.file(p.joinAll([base, ...key.split('/')]));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(value);
    }
  }

  /// One archive; a fixed time on its entries, so the same files give the
  /// same bytes.
  void writeZip(String path, Map<String, Uint8List> files) {
    final archive = Archive();
    for (final name in files.keys.toList()..sort()) {
      archive.add(ArchiveFile.bytes(name, files[name]!)..lastModTime = 0);
    }
    final file = fileSystem.file(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(ZipEncoder().encodeBytes(archive));
  }

  /// Copies those of [paths] that exist under
  /// `.xcross/icon-backups/<stamp>/`, keeping their paths; null when none do.
  String? backUp(String root, Iterable<String> paths, DateTime now) {
    final existing = [
      for (final path in paths)
        if (fileSystem.file(p.joinAll([root, ...path.split('/')])).existsSync())
          path,
    ];
    if (existing.isEmpty) return null;
    final backup = p.join(root, '.xcross', 'icon-backups', stamp(now));
    for (final path in existing) {
      final target = fileSystem.file(p.joinAll([backup, ...path.split('/')]));
      target.parent.createSync(recursive: true);
      fileSystem
          .file(p.joinAll([root, ...path.split('/')]))
          .copySync(target.path);
    }
    return backup;
  }
}
