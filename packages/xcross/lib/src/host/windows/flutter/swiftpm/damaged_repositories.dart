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
  /// SwiftPM says "no versions of 'x'" either first ("because no versions
  /// of") or at the end of a chain ("… depends on 'x' 4.0.0..<6.0.0 and no
  /// versions of 'x' match", seen 2026-11-12 with gtm-session-fetcher).
  /// Missing git objects read as "not a tree object" or "bad object" (seen
  /// 2026-11-12 with app-check: "the package at '\' cannot be accessed
  /// (Couldn't read '11.3.2': fatal: not a tree object)").
  static bool explains(Object error) {
    final text = '$error';
    return (text.contains('Dependencies could not be resolved') &&
            text.contains('no versions of')) ||
        text.contains('not a tree object') ||
        text.contains('fatal: bad object');
  }

  /// The folders SwiftPM may keep its shared repository cache in: the old
  /// `<home>/.swiftpm/cache/repositories`, and the caches folder Swift 6 uses
  /// on Windows, `%TEMP%\org.swift.swiftpm\repositories` — which Windows
  /// cleanup empties file by file, leaving the damaged shapes above.
  static List<String> sharedCaches({
    String? home,
    String? temp,
    String? localAppData,
  }) {
    final out = <String>[];
    void add(String path) {
      final key = p.normalize(path).toLowerCase();
      if (out.every((o) => p.normalize(o).toLowerCase() != key)) out.add(path);
    }

    if (home != null) add(p.join(home, '.swiftpm', 'cache', 'repositories'));
    if (temp != null) add(p.join(temp, 'org.swift.swiftpm', 'repositories'));
    if (localAppData != null) {
      add(p.join(localAppData, 'Temp', 'org.swift.swiftpm', 'repositories'));
    }
    return out;
  }

  /// Whether [path] has what git needs to list versions: `config`, `HEAD`,
  /// `objects` and `refs`, with refs that are packed or tags that are not.
  /// Every clone SwiftPM makes has a `config`; one without it had lost files
  /// to Windows cleanup, and SwiftPM calls it "not valid git repository" yet
  /// copies it again from the shared cache (app-check, 2026-11-12).
  bool isUsable(String path) {
    if (!fileSystem.file(p.join(path, 'config')).existsSync() ||
        !fileSystem.file(p.join(path, 'HEAD')).existsSync() ||
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
