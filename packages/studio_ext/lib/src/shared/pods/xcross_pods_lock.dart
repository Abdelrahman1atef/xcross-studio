import 'dart:io';

import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/pods/pod_resolver.dart';
import 'package:studio_ext/src/shared/pods/podfile_lock.dart';

/// Reads and writes `ios/xcross-pods.lock` when `ios/Podfile.lock` is not present (plan Q2, T409).
@internal
final class XcrossPodsLock {
  const XcrossPodsLock();

  static const defaultFileName = 'xcross-pods.lock';

  /// Serializes resolved pods into a Podfile.lock-compatible format.
  String serialize({
    required Map<String, PodCandidate> pods,
    Map<String, Set<String>> subspecs = const {},
    Map<String, String> checksums = const {},
  }) {
    final buffer = StringBuffer();
    buffer.writeln('PODS:');
    final sortedKeys = pods.keys.toList()..sort();
    for (final name in sortedKeys) {
      final candidate = pods[name]!;
      if (candidate.dependencies.isEmpty) {
        buffer.writeln('  - $name (${candidate.version})');
      } else {
        buffer.writeln('  - $name (${candidate.version}):');
        for (final dep in candidate.dependencies) {
          buffer.writeln('    - ${dep.name} (${dep.requirement})');
        }
      }
    }
    buffer.writeln();
    buffer.writeln('DEPENDENCIES:');
    for (final name in sortedKeys) {
      buffer.writeln('  - $name (= ${pods[name]!.version})');
    }
    buffer.writeln();
    buffer.writeln('SPEC REPOS:');
    buffer.writeln('  trunk:');
    for (final name in sortedKeys) {
      buffer.writeln('    - $name');
    }
    buffer.writeln();
    if (checksums.isNotEmpty) {
      buffer.writeln('SPEC CHECKSUMS:');
      for (final name in sortedKeys) {
        if (checksums.containsKey(name)) {
          buffer.writeln('  $name: ${checksums[name]}');
        }
      }
      buffer.writeln();
    }
    buffer.writeln('COCOAPODS: xcross-pods-1.0');
    return buffer.toString();
  }

  /// Parses locked pod version pins from serialized content.
  Map<String, String> parsePins(String content) {
    final parsed = PodfileLock.parse(content);
    return {
      for (final entry in parsed.pods.entries) entry.key: entry.value.version,
    };
  }

  /// Writes `xcrossLockFile` if `podfileLock` does not exist or is null.
  bool writeLockFile({
    required File xcrossLockFile,
    required Map<String, PodCandidate> pods,
    File? podfileLock,
    Map<String, Set<String>> subspecs = const {},
    Map<String, String> checksums = const {},
  }) {
    if (podfileLock != null && podfileLock.existsSync()) {
      return false;
    }
    xcrossLockFile.parent.createSync(recursive: true);
    xcrossLockFile.writeAsStringSync(
      serialize(pods: pods, subspecs: subspecs, checksums: checksums),
    );
    return true;
  }

  /// Loads lock pins from [podfileLock] if it exists, falling back to [xcrossLockFile].
  Map<String, String> loadPins({File? podfileLock, File? xcrossLockFile}) {
    if (podfileLock != null && podfileLock.existsSync()) {
      return parsePins(podfileLock.readAsStringSync());
    }
    if (xcrossLockFile != null && xcrossLockFile.existsSync()) {
      return parsePins(xcrossLockFile.readAsStringSync());
    }
    return const {};
  }
}
