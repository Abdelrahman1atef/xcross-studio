import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/plugins/podspec.dart';

/// Result of looking up a podspec in a spec repository.
@internal
@immutable
final class PodspecLookupResult {
  const PodspecLookupResult({
    required this.pod,
    required this.version,
    required this.repoUrl,
    this.podspec,
    this.jsonSpec,
    this.unreadLines = const [],
    this.specPath,
  });

  final String pod;
  final String version;
  final String repoUrl;
  final Podspec? podspec;
  final Map<String, Object?>? jsonSpec;
  final List<String> unreadLines;
  final String? specPath;

  bool get hasUnreadLines => unreadLines.isNotEmpty;
  String? get unreadWarning => hasUnreadLines
      ? 'pod.podspec_unread: lines in $pod $version podspec not understood by subset parser: ${unreadLines.join('; ')}'
      : null;
}

/// Resolves specs from git or filesystem spec repositories (§10, T501).
@internal
final class PodSpecRepoResolver {
  const PodSpecRepoResolver();

  /// Locates and reads a podspec file in [repoDir] for [pod] and [version].
  PodspecLookupResult? lookupSpec({
    required Directory repoDir,
    required String repoUrl,
    required String pod,
    required String version,
  }) {
    if (!repoDir.existsSync()) return null;

    final targetSuffixJson = '$pod/$version/$pod.podspec.json';
    final targetSuffixRuby = '$pod/$version/$pod.podspec';

    File? foundJsonFile;
    File? foundRubyFile;

    for (final entity in repoDir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final normalized = entity.path.replaceAll(r'\', '/');
      if (normalized.endsWith(targetSuffixJson)) {
        foundJsonFile = entity;
        break;
      }
      if (normalized.endsWith(targetSuffixRuby)) {
        foundRubyFile = entity;
      }
    }

    final targetFile = foundJsonFile ?? foundRubyFile;
    if (targetFile == null) return null;

    final content = targetFile.readAsStringSync();
    if (targetFile.path.endsWith('.json')) {
      try {
        final json = jsonDecode(content) as Map<String, Object?>;
        return PodspecLookupResult(
          pod: pod,
          version: version,
          repoUrl: repoUrl,
          jsonSpec: json,
          specPath: targetFile.path,
        );
      } on Object {
        // Malformed JSON fallback
      }
    } else {
      // Ruby podspec
      final (spec, unread) = _parseRubyPodspec(content);
      return PodspecLookupResult(
        pod: pod,
        version: version,
        repoUrl: repoUrl,
        podspec: spec,
        unreadLines: unread,
        specPath: targetFile.path,
      );
    }
    return null;
  }

  /// Shard path from md5 of pod name (CocoaPods standard).
  static List<String> shardFor(String pod) {
    final digest = md5.convert(utf8.encode(pod)).toString();
    return [digest[0], digest[1], digest[2]];
  }

  static (Podspec, List<String>) _parseRubyPodspec(String source) {
    final spec = Podspec.parse(source);
    final unread = <String>[];

    final recognizedKeys = {
      'name',
      'version',
      'source_files',
      'public_header_files',
      'exclude_files',
      'frameworks',
      'weak_frameworks',
      'libraries',
      'ios.deployment_target',
      'deployment_target',
      'resource_bundles',
      'resources',
      'subspec',
      'dependency',
      'summary',
      'description',
      'homepage',
      'license',
      'author',
      'authors',
      'source',
      'module_name',
    };

    for (final rawLine in source.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('Pod::Spec.new') || line == 'end') continue;

      final match = RegExp(
        r'^\s*s\.(?:ios\.)?([a-zA-Z0-9_]+)',
      ).firstMatch(line);
      if (match != null) {
        final key = match.group(1);
        if (key != null && !recognizedKeys.contains(key)) {
          unread.add(line);
        }
      } else if (line.contains('prepare_command') || line.contains('system(')) {
        unread.add(line);
      }
    }

    return (spec, unread);
  }
}
