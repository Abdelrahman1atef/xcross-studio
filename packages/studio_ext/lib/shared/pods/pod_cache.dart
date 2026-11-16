import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

final class PodCache {
  const PodCache({
    required this.root,
    required this.fileFactory,
    required this.directoryFactory,
    required this.processAlive,
    required this.processId,
    this.createHardLink,
    this.makeReadOnly,
  });

  final Directory root;
  final File Function(String) fileFactory;
  final Directory Function(String) directoryFactory;
  final bool Function(int) processAlive;
  final int processId;
  final Future<void> Function(String source, String destination)?
  createHardLink;
  final Future<void> Function(String path)? makeReadOnly;

  String key12(String input) =>
      sha256.convert(input.codeUnits).toString().substring(0, 12);

  Directory source(String key) =>
      directoryFactory(path.join(root.path, 'sources', _checkedKey(key)));

  Directory package(String pod, String version, String key) {
    if (!_safeName(pod) || !_safeName(version)) {
      throw ArgumentError('Invalid pod or version');
    }
    return directoryFactory(
      path.join(root.path, 'packages', pod, '$version-${_checkedKey(key)}'),
    );
  }

  File lockFile(String key) =>
      fileFactory(path.join(root.path, 'locks', '${_checkedKey(key)}.lock'));

  Future<void> link(File source, File destination) async {
    final hardLink = createHardLink;
    if (hardLink == null) {
      throw StateError('hard links are unavailable on this host');
    }
    await destination.parent.create(recursive: true);
    try {
      await hardLink(source.path, destination.path);
    } on Object {
      throw StateError(
        'Could not make a hard link for ${path.basename(source.path)}. '
        'Keep the pod cache and project on one volume with hard-link support.',
      );
    }
  }

  Future<void> seal(Directory entry) async {
    final readOnly = makeReadOnly;
    if (readOnly == null) {
      throw StateError('read-only cache entries are unavailable');
    }
    await for (final entity in entry.list(recursive: true)) {
      if (entity is File) await readOnly(entity.path);
    }
  }

  List<String> listEntries() {
    final entries = <String>[];
    for (final group in ['sources', 'packages']) {
      final directory = directoryFactory(path.join(root.path, group));
      if (!directory.existsSync()) continue;
      for (final entry in directory.listSync(recursive: group == 'packages')) {
        if (entry is Directory &&
            (group == 'sources' ||
                path.dirname(path.dirname(entry.path)) == directory.path)) {
          entries.add(path.relative(entry.path, from: root.path));
        }
      }
    }
    return entries..sort();
  }

  Future<void> clear({required bool confirmed}) async {
    if (!confirmed) throw StateError('Confirm clearing the pod cache first');
    final locks = directoryFactory(path.join(root.path, 'locks'));
    if (locks.existsSync() && locks.listSync().isNotEmpty) {
      throw StateError('A pod cache entry is in use');
    }
    for (final group in ['index', 'specs', 'sources', 'packages']) {
      final directory = directoryFactory(path.join(root.path, group));
      if (directory.existsSync()) await directory.delete(recursive: true);
    }
  }

  Future<T> withLock<T>(
    String key,
    Future<T> Function() work, {
    void Function()? onWait,
    Duration waitNotice = const Duration(seconds: 5),
  }) async {
    final lock = lockFile(key);
    await lock.parent.create(recursive: true);
    final marker = '$processId:${DateTime.now().microsecondsSinceEpoch}';
    final start = DateTime.now();
    var reported = false;
    while (true) {
      try {
        await lock.create(exclusive: true);
        await lock.writeAsString(marker);
        break;
      } on FileSystemException {
        if (!lock.existsSync()) rethrow;
        final owner = int.tryParse(lock.readAsStringSync().split(':').first);
        if (owner == null &&
            DateTime.now().difference(lock.lastModifiedSync()) <
                const Duration(seconds: 5)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          continue;
        }
        if (owner == null || !processAlive(owner)) {
          try {
            await lock.delete();
          } on FileSystemException {
            // Another process may have taken over first.
          }
          continue;
        }
        if (!reported && DateTime.now().difference(start) >= waitNotice) {
          onWait?.call();
          reported = true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    try {
      return await work();
    } finally {
      if (lock.existsSync() && lock.readAsStringSync() == marker) {
        await lock.delete();
      }
    }
  }

  String _checkedKey(String key) {
    if (!RegExp(r'^[a-f0-9]{12}$').hasMatch(key)) {
      throw ArgumentError.value(key, 'key', 'Expected 12 hex characters');
    }
    return key;
  }

  bool _safeName(String value) => RegExp(r'^[A-Za-z0-9_.+-]+$').hasMatch(value);
}
