import 'package:meta/meta.dart';

@internal
final class LockedPod {
  const LockedPod(this.name, this.version, this.dependencies);

  final String name;
  final String version;
  final List<String> dependencies;
}

/// The Podfile.lock fields needed for resolution and stale-lock diagnostics.
@internal
final class PodfileLock {
  PodfileLock.parse(String content)
    : pods = <String, LockedPod>{},
      dependencies = <String>[],
      specRepos = <String, List<String>>{},
      externalSources = <String, Map<String, String>>{},
      checkoutOptions = <String, Map<String, String>>{},
      specChecksums = <String, String>{} {
    String? section;
    String? currentPod;
    String? currentRepo;
    String? currentExternal;
    String? currentCheckout;
    for (final raw in content.split(RegExp(r'\r?\n'))) {
      if (raw.trim().isEmpty) continue;
      final indent = raw.length - raw.trimLeft().length;
      final line = raw.trim();
      if (indent == 0) {
        if (line.endsWith(':') &&
            !line.startsWith('PODFILE CHECKSUM:') &&
            !line.startsWith('COCOAPODS:')) {
          section = line.substring(0, line.length - 1);
        } else {
          final pair = _pair(line);
          if (pair != null) {
            if (pair.$1 == 'PODFILE CHECKSUM') podfileChecksum = pair.$2;
            if (pair.$1 == 'COCOAPODS') cocoapodsVersion = pair.$2;
          }
        }
        continue;
      }
      switch (section) {
        case 'PODS':
          if (indent == 2 && line.startsWith('- ')) {
            final entry = _unquote(
              line.substring(2).replaceFirst(RegExp(r':$'), ''),
            );
            final match = RegExp(r'^(.+?) \(([^)]+)\)$').firstMatch(entry);
            if (match == null) {
              throw FormatException('Invalid locked pod: $line');
            }
            currentPod = _unquote(match.group(1)!);
            pods[currentPod] = LockedPod(currentPod, match.group(2)!, []);
          } else if (indent > 2 &&
              line.startsWith('- ') &&
              currentPod != null) {
            pods[currentPod]!.dependencies.add(_unquote(line.substring(2)));
          }
        case 'DEPENDENCIES':
          if (line.startsWith('- ')) {
            dependencies.add(_unquote(line.substring(2)));
          }
        case 'SPEC REPOS':
          if (indent == 2 && line.endsWith(':')) {
            currentRepo = _unquote(line.substring(0, line.length - 1));
            specRepos[currentRepo] = [];
          } else if (line.startsWith('- ') && currentRepo != null) {
            specRepos[currentRepo]!.add(_unquote(line.substring(2)));
          }
        case 'EXTERNAL SOURCES':
          if (indent == 2 && line.endsWith(':')) {
            currentExternal = _unquote(line.substring(0, line.length - 1));
            externalSources[currentExternal] = {};
          } else if (currentExternal != null) {
            final pair = _pair(line);
            if (pair != null) {
              externalSources[currentExternal]![pair.$1] = pair.$2;
            }
          }
        case 'CHECKOUT OPTIONS':
          if (indent == 2 && line.endsWith(':')) {
            currentCheckout = _unquote(line.substring(0, line.length - 1));
            checkoutOptions[currentCheckout] = {};
          } else if (currentCheckout != null) {
            final pair = _pair(line);
            if (pair != null) {
              checkoutOptions[currentCheckout]![pair.$1] = pair.$2;
            }
          }
        case 'SPEC CHECKSUMS':
          final pair = _pair(line);
          if (pair != null) specChecksums[pair.$1] = pair.$2;
      }
    }
  }

  final Map<String, LockedPod> pods;
  final List<String> dependencies;
  final Map<String, List<String>> specRepos;
  final Map<String, Map<String, String>> externalSources;
  final Map<String, Map<String, String>> checkoutOptions;
  final Map<String, String> specChecksums;
  String? podfileChecksum;
  String? cocoapodsVersion;

  static (String, String)? _pair(String line) {
    final index = line.indexOf(': ');
    if (index < 0) return null;
    return (
      _unquote(line.substring(0, index)),
      _unquote(line.substring(index + 2)),
    );
  }

  static String _unquote(String value) {
    final text = value.trim();
    if (text.length >= 2 &&
        ((text.startsWith('"') && text.endsWith('"')) ||
            (text.startsWith("'") && text.endsWith("'")))) {
      return text.substring(1, text.length - 1);
    }
    return text;
  }
}
