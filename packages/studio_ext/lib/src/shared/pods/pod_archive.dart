import 'dart:io';

import 'package:archive/archive.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

@internal
final class UnsafePodArchive implements Exception {
  const UnsafePodArchive(this.entry);
  final String entry;
  @override
  String toString() => 'Unsafe pod archive entry: $entry';
}

@internal
final class PodLfsPointer implements Exception {
  const PodLfsPointer(this.entry);
  final String entry;
  @override
  String toString() => 'Git LFS object required: $entry';
}

/// Extracts a pod source archive into a staging folder before publishing it.
@internal
final class PodArchive {
  const PodArchive({required this.directoryFactory, required this.fileFactory});

  final Directory Function(String) directoryFactory;
  final File Function(String) fileFactory;

  Future<void> extract(
    List<int> bytes,
    String type,
    Directory destination, {
    bool flatten = false,
  }) async {
    final archive = switch (type) {
      'zip' => ZipDecoder().decodeBytes(bytes),
      'tar' => TarDecoder().decodeBytes(bytes),
      'tgz' || 'tar.gz' => TarDecoder().decodeBytes(
        const GZipDecoder().decodeBytes(bytes),
      ),
      'tbz' ||
      'tar.bz2' => TarDecoder().decodeBytes(BZip2Decoder().decodeBytes(bytes)),
      'txz' ||
      'tar.xz' => TarDecoder().decodeBytes(XZDecoder().decodeBytes(bytes)),
      _ => throw ArgumentError.value(type, 'type', 'Unsupported pod archive'),
    };
    final entries = archive.files
        .where((entry) => !_otherPlatform(entry.name))
        .toList();
    final prefix = flatten
        ? _singleRoot(entries.map((entry) => entry.name))
        : null;
    final staging = directoryFactory(
      '${destination.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    await staging.create(recursive: true);
    try {
      final links = <(String, String)>[];
      for (final entry in entries) {
        final name = prefix == null
            ? entry.name
            : entry.name == prefix.substring(0, prefix.length - 1)
            ? ''
            : entry.name.substring(prefix.length);
        if (name.isEmpty) continue;
        final relative = validateName(name);
        final target = path.join(staging.path, relative);
        if (entry.isSymbolicLink) {
          links.add((relative, entry.symbolicLink!));
          continue;
        }
        if (!entry.isFile) {
          await directoryFactory(target).create(recursive: true);
          continue;
        }
        await directoryFactory(path.dirname(target)).create(recursive: true);
        final content = entry.content as List<int>;
        if (_lfsPointer(content)) {
          throw PodLfsPointer(name);
        }
        await fileFactory(target).writeAsBytes(content);
      }
      for (final (name, link) in links) {
        final target = path.normalize(path.join(path.dirname(name), link));
        final safeTarget = validateName(target);
        final source = fileFactory(path.join(staging.path, safeTarget));
        if (!source.existsSync()) throw UnsafePodArchive(name);
        final copy = fileFactory(path.join(staging.path, name));
        await copy.parent.create(recursive: true);
        await source.copy(copy.path);
      }
      if (destination.existsSync()) {
        await staging.delete(recursive: true);
      } else {
        await staging.rename(destination.path);
      }
    } on Object {
      if (staging.existsSync()) await staging.delete(recursive: true);
      rethrow;
    }
  }

  String validateName(String name) {
    final normalized = name.replaceAll(String.fromCharCode(92), '/');
    if (normalized.startsWith('/') ||
        RegExp('^[a-zA-Z]:').hasMatch(normalized)) {
      throw UnsafePodArchive(name);
    }
    final segments = normalized
        .split('/')
        .where((segment) => segment.isNotEmpty && segment != '.')
        .toList();
    if (segments.isEmpty ||
        segments.any((segment) {
          final trimmed = segment.replaceAll(RegExp(r'[. ]+$'), '');
          return trimmed.isEmpty || segment.contains(':');
        })) {
      throw UnsafePodArchive(name);
    }
    return path.joinAll(segments);
  }

  String? _singleRoot(Iterable<String> names) {
    final roots = names
        .map(
          (name) =>
              name.replaceAll(String.fromCharCode(92), '/').split('/').first,
        )
        .toSet();
    return roots.length == 1 ? '${roots.single}/' : null;
  }

  bool _otherPlatform(String name) =>
      name.toLowerCase().contains('.xcframework/macos-') ||
      name.toLowerCase().contains('.xcframework/tvos-') ||
      name.toLowerCase().contains('.xcframework/watchos-') ||
      name.toLowerCase().contains('.xcframework/xros-');

  bool _lfsPointer(List<int> content) {
    const marker = 'version https://git-lfs.github.com/spec/v1';
    if (content.length < marker.length || content.length > 1024) return false;
    for (var i = 0; i < marker.length; i++) {
      if (content[i] != marker.codeUnitAt(i)) return false;
    }
    return true;
  }
}
