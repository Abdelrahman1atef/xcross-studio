import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

import 'package:studio_ext/src/shared/inspect/inspect_codes.dart';
import 'package:studio_ext/src/shared/inspect/inspect_failure.dart';
import 'package:studio_ext/src/shared/inspect/inspect_report.dart';

/// Read-only view of one app bundle inside an `.ipa` or a `.app` directory
/// (research R11).
///
/// Paths are POSIX and relative to the bundle root, e.g.
/// `Frameworks/Flutter.framework/Info.plist`.
@internal
abstract class InspectSource {
  /// Opens [path], which must be an `.ipa` file or a `.app` directory.
  ///
  /// Throws [InspectFailure] for a missing or unsupported input and for
  /// unreadable archives.
  static InspectSource open(HostFileSystemInterface fileSystem, String path) {
    final name = basenameOf(path);
    final lower = name.toLowerCase();
    if (fileSystem.directory(path).existsSync()) {
      if (lower.endsWith('.app')) {
        return AppDirectorySource.open(fileSystem, path, name);
      }
      throw InspectFailure(
        InspectCodes.unsupportedInput,
        '$name is a directory but not a .app bundle.',
      );
    }
    if (fileSystem.file(path).existsSync()) {
      if (lower.endsWith('.ipa')) {
        return IpaSource.open(fileSystem, path, name);
      }
      throw InspectFailure(
        InspectCodes.unsupportedInput,
        '$name is not an .ipa file or a .app directory.',
      );
    }
    throw InspectFailure(InspectCodes.inputNotFound, '$name does not exist.');
  }

  InputKind get kind;

  /// Basename of the input, e.g. `Runner.ipa`.
  String get name;

  /// Input file size for `.ipa` input; null for `.app` input.
  int? get sizeBytes;

  /// Lowercase hex SHA-256 of the `.ipa` file; null for `.app` input.
  String? get sha256Hex;

  /// `Payload/<Name>.app` for `.ipa` input, `.` for `.app` input.
  String get bundlePath;

  /// Regular files, sorted.
  List<String> get files;

  /// Symbolic links that were not followed, sorted.
  List<String> get skippedSymlinks;

  bool hasFile(String path);

  bool hasDirectory(String path);

  /// Uncompressed size of the file at [path], or null if it does not exist.
  int? sizeOf(String path);

  /// Contents of the file at [path], or null if it does not exist.
  ///
  /// Throws [FormatException] when the file exists but cannot be read.
  Uint8List? read(String path);

  void close();
}

/// Last path segment of [path], accepting `/` and `\` separators and a
/// trailing separator.
@internal
String basenameOf(String path) {
  var end = path.length;
  while (end > 0 && (path[end - 1] == '/' || path[end - 1] == r'\')) {
    end--;
  }
  var start = end;
  while (start > 0 && path[start - 1] != '/' && path[start - 1] != r'\') {
    start--;
  }
  return path.substring(start, end);
}

Set<String> _parentDirectories(Iterable<String> files) {
  final directories = <String>{};
  for (final file in files) {
    var slash = file.lastIndexOf('/');
    while (slash > 0) {
      final directory = file.substring(0, slash);
      if (!directories.add(directory)) break;
      slash = directory.lastIndexOf('/');
    }
  }
  return directories;
}

/// An app bundle inside an `.ipa` zip archive.
@internal
final class IpaSource extends InspectSource {
  IpaSource._({
    required this.name,
    required this.sizeBytes,
    required this.sha256Hex,
    required this.bundlePath,
    required Map<String, ArchiveFile> entries,
    required List<String> skippedSymlinks,
    required InputFileStream input,
  }) : _entries = entries,
       _input = input,
       files = List.unmodifiable(entries.keys.toList()..sort()),
       skippedSymlinks = List.unmodifiable(skippedSymlinks..sort()),
       _directories = _parentDirectories(entries.keys);

  /// Opens the `.ipa` at [path] and locates its single `Payload/*.app`.
  factory IpaSource.open(
    HostFileSystemInterface fileSystem,
    String path,
    String name,
  ) {
    final file = fileSystem.file(path);
    final size = file.lengthSync();
    if (!hasZipSignature(file)) {
      throw InspectFailure(
        InspectCodes.corruptArchive,
        '$name is not a zip archive.',
      );
    }
    final hash = sha256OfFile(file);
    final input = InputFileStream(file.path);
    try {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeStream(input);
        // archive reports damaged zips with assorted exception and error
        // types; every one of them means "not a readable zip".
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        throw InspectFailure(
          InspectCodes.corruptArchive,
          '$name is not a readable zip archive.',
        );
      }
      final apps = <String>{};
      for (final entry in archive.files) {
        final segments = entry.name.replaceAll(r'\', '/').split('/');
        if (segments.length >= 2 &&
            segments[0] == 'Payload' &&
            segments[1].endsWith('.app')) {
          apps.add(segments[1]);
        }
      }
      if (apps.isEmpty) {
        throw InspectFailure(
          InspectCodes.noApp,
          '$name has no Payload/<Name>.app bundle.',
        );
      }
      if (apps.length > 1) {
        throw InspectFailure(
          InspectCodes.multipleApps,
          '$name has ${apps.length} app bundles under Payload/: '
          '${(apps.toList()..sort()).join(', ')}.',
        );
      }
      final app = apps.single;
      final prefix = 'Payload/$app/';
      final entries = <String, ArchiveFile>{};
      final links = <String>[];
      for (final entry in archive.files) {
        final entryName = entry.name.replaceAll(r'\', '/');
        if (!entryName.startsWith(prefix) || !entry.isFile) continue;
        final relative = entryName.substring(prefix.length);
        if (relative.isEmpty) continue;
        if (entry.isSymbolicLink) {
          links.add(relative);
        } else {
          entries[relative] = entry;
        }
      }
      return IpaSource._(
        name: name,
        sizeBytes: size,
        sha256Hex: hash,
        bundlePath: 'Payload/$app',
        entries: entries,
        skippedSymlinks: links,
        input: input,
      );
    } on Object {
      input.closeSync();
      rethrow;
    }
  }

  final Map<String, ArchiveFile> _entries;
  final InputFileStream _input;
  final Set<String> _directories;

  @override
  InputKind get kind => InputKind.ipa;

  @override
  final String name;

  @override
  final int? sizeBytes;

  @override
  final String? sha256Hex;

  @override
  final String bundlePath;

  @override
  final List<String> files;

  @override
  final List<String> skippedSymlinks;

  @override
  bool hasFile(String path) => _entries.containsKey(path);

  @override
  bool hasDirectory(String path) => _directories.contains(path);

  @override
  int? sizeOf(String path) => _entries[path]?.size;

  @override
  Uint8List? read(String path) {
    final entry = _entries[path];
    if (entry == null) return null;
    try {
      // Inflate into a fresh buffer instead of the entry's cache so memory
      // is released as soon as the caller drops the bytes.
      final output = OutputMemoryStream();
      entry.decompress(output);
      return output.getBytes();
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      throw FormatException('cannot inflate $path');
    }
  }

  @override
  void close() => _input.closeSync();
}

/// An app bundle given as a `.app` directory.
@internal
final class AppDirectorySource extends InspectSource {
  AppDirectorySource._({
    required this.name,
    required Map<String, File> entries,
    required Set<String> directories,
    required List<String> skippedSymlinks,
  }) : _entries = entries,
       _directories = directories,
       files = List.unmodifiable(entries.keys.toList()..sort()),
       skippedSymlinks = List.unmodifiable(skippedSymlinks..sort());

  /// Lists the directory at [path] without following symbolic links.
  factory AppDirectorySource.open(
    HostFileSystemInterface fileSystem,
    String path,
    String name,
  ) {
    final directory = fileSystem.directory(path);
    final root = _slashes(directory.path).replaceFirst(RegExp(r'/+$'), '');
    final entries = <String, File>{};
    final directories = <String>{};
    final links = <String>[];
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      final full = _slashes(entity.path);
      if (!full.startsWith('$root/')) continue;
      final relative = full.substring(root.length + 1);
      switch (entity) {
        case Link():
          links.add(relative);
        case File():
          entries[relative] = entity;
        case Directory():
          directories.add(relative);
      }
    }
    return AppDirectorySource._(
      name: name,
      entries: entries,
      directories: directories..addAll(_parentDirectories(entries.keys)),
      skippedSymlinks: links,
    );
  }

  final Map<String, File> _entries;
  final Set<String> _directories;

  @override
  InputKind get kind => InputKind.app;

  @override
  final String name;

  @override
  int? get sizeBytes => null;

  @override
  String? get sha256Hex => null;

  @override
  String get bundlePath => '.';

  @override
  final List<String> files;

  @override
  final List<String> skippedSymlinks;

  @override
  bool hasFile(String path) => _entries.containsKey(path);

  @override
  bool hasDirectory(String path) => _directories.contains(path);

  @override
  int? sizeOf(String path) => _entries[path]?.lengthSync();

  @override
  Uint8List? read(String path) {
    final file = _entries[path];
    if (file == null) return null;
    try {
      return file.readAsBytesSync();
    } on FileSystemException {
      throw FormatException('cannot read $path');
    }
  }

  @override
  void close() {}
}

String _slashes(String path) => path.replaceAll(r'\', '/');

/// Whether [file] starts with a zip local-file or empty-archive signature.
@internal
bool hasZipSignature(File file) {
  final handle = file.openSync();
  try {
    final head = handle.readSync(4);
    return head.length == 4 &&
        head[0] == 0x50 &&
        head[1] == 0x4b &&
        ((head[2] == 3 && head[3] == 4) || (head[2] == 5 && head[3] == 6));
  } finally {
    handle.closeSync();
  }
}

/// Lowercase hex SHA-256 of [file], read in 1 MiB chunks.
@internal
String sha256OfFile(File file) {
  final handle = file.openSync();
  try {
    final capture = DigestCapture();
    final input = sha256.startChunkedConversion(capture);
    while (true) {
      final chunk = handle.readSync(1 << 20);
      if (chunk.isEmpty) break;
      input.add(chunk);
    }
    input.close();
    return capture.value.toString();
  } finally {
    handle.closeSync();
  }
}

/// Receives the single digest of a chunked hash conversion.
@internal
final class DigestCapture implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
