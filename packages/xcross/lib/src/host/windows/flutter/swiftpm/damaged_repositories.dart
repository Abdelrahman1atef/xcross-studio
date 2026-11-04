// studio: 025 — SwiftPM's shared repository cache can hold unusable entries on
// Windows: most had lost everything but `objects`, one had no tags. A new
// workspace copies from that cache, finds no versions, and cannot resolve;
// workspaces that already have their own copy never notice.
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Finds and removes bare git repositories SwiftPM cannot read versions from.
@internal
final class SwiftPmDamagedRepositories {
  SwiftPmDamagedRepositories(this.fileSystem, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final HostFileSystemInterface fileSystem;
  final DateTime Function() _clock;

  /// A shared cache entry this new may be another build's clone in progress.
  static const sharedCacheMinimumAge = Duration(minutes: 10);

  /// Whether a failed resolve could be down to a repository without tags.
  static bool explains(Object error) => '$error'.contains(
    'Dependencies could not be resolved because no versions of',
  );

  /// `<home>/.swiftpm/cache/repositories`.
  static String sharedCache(String home) =>
      p.join(home, '.swiftpm', 'cache', 'repositories');

  /// Whether [path] has what git needs to list versions: `HEAD`, `objects` and
  /// `refs`, with refs that are packed or tags that are not.
  bool isUsable(String path) {
    if (!fileSystem.file(p.join(path, 'HEAD')).existsSync() ||
        !fileSystem.directory(p.join(path, 'objects')).existsSync() ||
        !fileSystem.directory(p.join(path, 'refs')).existsSync()) {
      return false;
    }
    if (fileSystem.file(p.join(path, 'packed-refs')).existsSync()) return true;
    final tags = fileSystem.directory(p.join(path, 'refs', 'tags'));
    return tags.existsSync() && tags.listSync().isNotEmpty;
  }

  /// Removes the unusable repositories in [folder]. Returns their names. With
  /// [minimumAge], newer ones stay. One that cannot be removed is skipped.
  Future<List<String>> removeFrom(
    String folder, {
    Duration minimumAge = Duration.zero,
  }) async {
    final directory = fileSystem.directory(folder);
    if (!directory.existsSync()) return const [];
    final removed = <String>[];
    for (final entry in directory.listSync(followLinks: false)) {
      final repository = fileSystem.directory(entry.path);
      if (!repository.existsSync() || isUsable(entry.path)) continue;
      final age = _clock().difference(repository.statSync().modified);
      if (age < minimumAge) continue;
      try {
        await repository.delete(recursive: true);
        removed.add(p.basename(entry.path));
      } on Object {
        continue;
      }
    }
    return removed;
  }
}
