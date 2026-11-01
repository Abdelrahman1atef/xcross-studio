import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:path/path.dart' as p;

/// Writes an `.app` bundle as an installable `.ipa` (feature 011).
///
/// - Entries are `Payload/<App>.app/…`, directories included, sorted by
///   path, with one fixed timestamp, so the same bundle gives the same zip.
/// - Unix modes are recorded and the archive is marked as made on Unix:
///   Mach-O files (and directories) get 0755, everything else 0644. Without
///   the Unix marker, extractors ignore the modes and the app's executable
///   can end up without its execute bit.
/// - Symlinks are followed (iOS bundles are flat; codesign rejects interior
///   links).
final class IpaWriter {
  const IpaWriter({required this.fileSystem, required this.paths});

  final HostFileSystemInterface fileSystem;
  final p.Context paths;

  /// Every entry's modification time.
  static final DateTime entryTime = DateTime.utc(2001);

  static const _directoryMode = 0x41ED; // S_IFDIR | 0755
  static const _executableMode = 0x81ED; // S_IFREG | 0755
  static const _fileMode = 0x81A4; // S_IFREG | 0644

  /// Zips the `.app` at [appPath] into [ipaPath] (written to a `.part` file
  /// first, then renamed). Returns [ipaPath].
  String write(String appPath, String ipaPath) {
    final root = appPath.replaceAll(RegExp(r'[\\/]+$'), '');
    final appName = paths.basename(root);
    final time = entryTime.millisecondsSinceEpoch ~/ 1000;
    final entries = <String, Object>{};
    for (final entity in fileSystem.directory(root).listSync(recursive: true)) {
      final relative = paths.relative(entity.path, from: root);
      final name = p.posix.joinAll([
        'Payload',
        appName,
        ...paths.split(relative),
      ]);
      if (entity is Directory) {
        entries['$name/'] = _directoryMode;
      } else if (entity is File) {
        entries[name] = entity.path;
      }
    }
    final archive = Archive()
      ..add(
        ArchiveFile.directory('Payload/')
          ..mode = _directoryMode
          ..lastModTime = time,
      )
      ..add(
        ArchiveFile.directory('Payload/$appName/')
          ..mode = _directoryMode
          ..lastModTime = time,
      );
    for (final name in entries.keys.toList()..sort()) {
      final value = entries[name]!;
      if (value is int) {
        archive.add(
          ArchiveFile.directory(name)
            ..mode = value
            ..lastModTime = time,
        );
        continue;
      }
      final bytes = fileSystem.file(value as String).readAsBytesSync();
      archive.add(
        ArchiveFile.bytes(name, bytes)
          ..mode = isMachO(bytes) ? _executableMode : _fileMode
          ..lastModTime = time,
      );
    }
    final zip = markMadeOnUnix(
      Uint8List.fromList(ZipEncoder().encodeBytes(archive)),
    );
    final part = fileSystem.file('$ipaPath.part');
    part.parent.createSync(recursive: true);
    part.writeAsBytesSync(zip, flush: true);
    final target = fileSystem.file(ipaPath);
    if (target.existsSync()) target.deleteSync();
    part.renameSync(ipaPath);
    return ipaPath;
  }

  /// Thin or fat Mach-O magic, either byte order.
  static bool isMachO(List<int> bytes) {
    if (bytes.length < 4) return false;
    final magic = bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3];
    return const {
      0xFEEDFACE,
      0xFEEDFACF,
      0xCEFAEDFE,
      0xCFFAEDFE,
      0xCAFEBABE,
      0xCAFEBABF,
      0xBEBAFECA,
      0xBFBAFECA,
    }.contains(magic);
  }

  /// Sets "version made by" of every central-directory entry to Unix 2.0
  /// (`0x0314`), so the recorded modes are honoured. `package:archive`
  /// always writes MS-DOS here.
  static Uint8List markMadeOnUnix(Uint8List zip) {
    final data = ByteData.sublistView(zip);
    var end = -1;
    for (var i = zip.length - 22; i >= 0 && i >= zip.length - 65557; i--) {
      if (data.getUint32(i, Endian.little) == 0x06054B50) {
        end = i;
        break;
      }
    }
    if (end < 0) return zip;
    final count = data.getUint16(end + 10, Endian.little);
    var offset = data.getUint32(end + 16, Endian.little);
    if (offset == 0xFFFFFFFF) return zip; // zip64: left as written
    for (var i = 0; i < count; i++) {
      if (offset + 46 > zip.length ||
          data.getUint32(offset, Endian.little) != 0x02014B50) {
        break;
      }
      zip[offset + 4] = 20;
      zip[offset + 5] = 3;
      offset +=
          46 +
          data.getUint16(offset + 28, Endian.little) +
          data.getUint16(offset + 30, Endian.little) +
          data.getUint16(offset + 32, Endian.little);
    }
    return zip;
  }
}
