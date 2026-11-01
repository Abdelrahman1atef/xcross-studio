// studio: 005 — the user's own developer disk image for iOS < 17 launch.
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// A developer disk image and its signature.
@internal
typedef DeveloperDiskImagePaths = ({String image, String signature});

/// Finds a user-supplied developer disk image for an iOS version. Never
/// downloads anything (constitution Principle II).
///
/// Search order: [explicitDir] (`--ddi`), `XCROSS_DDI_DIR`, then
/// `~/.xcross/DeviceSupport`. Each root may hold the image directly or in a
/// version folder named like Xcode's `DeviceSupport` (`16.4`, `16`,
/// `16.4 (20E247)`); the closest version folder wins.
@internal
final class DdiLocator {
  DdiLocator({
    required this.fileSystem,
    required this.paths,
    required this.environment,
  });

  final HostFileSystemInterface fileSystem;
  final p.Context paths;
  final Map<String, String> environment;

  static const imageName = 'DeveloperDiskImage.dmg';

  DeveloperDiskImagePaths? find(String osVersion, {String? explicitDir}) {
    final parts = osVersion.split('.');
    final major = parts.first;
    final minor = parts.length > 1 ? '$major.${parts[1]}' : major;
    final home = environment['HOME'] ?? environment['USERPROFILE'];
    final roots = [
      ?explicitDir,
      if (environment['XCROSS_DDI_DIR'] case final dir? when dir.isNotEmpty)
        dir,
      if (home != null && home.isNotEmpty)
        paths.join(home, '.xcross', 'DeviceSupport'),
    ];
    for (final root in roots) {
      for (final directory in [root, ..._versionFolders(root, major, minor)]) {
        final image = paths.join(directory, imageName);
        final signature = '$image.signature';
        if (fileSystem.file(image).existsSync() &&
            fileSystem.file(signature).existsSync()) {
          return (image: image, signature: signature);
        }
      }
    }
    return null;
  }

  /// Version folders under [root], best match first: exact `major.minor`,
  /// then `major.minor (build)`, then other `major.*`, then `major`.
  List<String> _versionFolders(String root, String major, String minor) {
    final directory = fileSystem.directory(root);
    if (!directory.existsSync()) return const [];
    final names = [
      for (final entity in directory.listSync(followLinks: false))
        // Separator-agnostic: listings can come back in host-native form.
        entity.path.split(RegExp(r'[\\/]')).lastWhere((s) => s.isNotEmpty),
    ];
    int rank(String name) {
      if (name == minor) return 0;
      if (name.startsWith('$minor ')) return 1;
      if (name.startsWith('$major.')) return 2;
      if (name == major) return 3;
      return 99;
    }

    final matches = names.where((n) => rank(n) < 99).toList()
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : b.compareTo(a);
      });
    return [for (final name in matches) paths.join(root, name)];
  }
}
