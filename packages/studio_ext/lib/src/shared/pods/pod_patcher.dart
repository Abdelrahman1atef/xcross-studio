import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// One patch applied to a pod's source or header file (§8.9).
@internal
@immutable
final class PodPatchRecord {
  const PodPatchRecord({
    required this.file,
    required this.kind,
    required this.original,
    required this.replacement,
  });

  final String file;
  final String kind;
  final String original;
  final String replacement;

  Map<String, Object?> toJson() => {
    'file': file,
    'kind': kind,
    'original': original,
    'replacement': replacement,
  };
}

/// Rewrites SWIFT_PACKAGE conditions so converted pods take the CocoaPods branch (§8.9.1).
@internal
final class PodSwiftPackagePatcher {
  const PodSwiftPackagePatcher();

  static const notSwiftPackagePlaceholder = 'XCROSS_POD_NOT_SWIFT_PACKAGE';

  static final RegExp _swiftPackageRegex = RegExp(r'\bSWIFT_PACKAGE\b');

  /// Rewrites `SWIFT_PACKAGE` macros in [content] for [relativePath].
  ({String content, List<PodPatchRecord> patches}) patchContent(
    String content,
    String relativePath,
  ) {
    if (!_swiftPackageRegex.hasMatch(content)) {
      return (content: content, patches: const []);
    }

    final patches = <PodPatchRecord>[];
    final lines = content.split('\n');
    final modifiedLines = <String>[];

    for (final line in lines) {
      if (_swiftPackageRegex.hasMatch(line) &&
          (line.trim().startsWith('#') || line.contains('defined('))) {
        final replaced = line.replaceAll(
          _swiftPackageRegex,
          notSwiftPackagePlaceholder,
        );
        patches.add(
          PodPatchRecord(
            file: relativePath.replaceAll(r'\', '/'),
            kind: 'swift_package_macro',
            original: line.trim(),
            replacement: replaced.trim(),
          ),
        );
        modifiedLines.add(replaced);
      } else {
        modifiedLines.add(line);
      }
    }

    return (content: modifiedLines.join('\n'), patches: patches);
  }

  /// Scans and patches [files] in place, returning all patch records.
  List<PodPatchRecord> patchFiles(
    Iterable<File> files, {
    String? baseDirectory,
  }) {
    final allPatches = <PodPatchRecord>[];
    for (final file in files) {
      if (!file.existsSync()) continue;
      final text = file.readAsStringSync();
      final relPath = baseDirectory != null
          ? p.relative(file.path, from: baseDirectory)
          : file.path;
      final result = patchContent(text, relPath);
      if (result.patches.isNotEmpty) {
        file.writeAsStringSync(result.content);
        allPatches.addAll(result.patches);
      }
    }
    return allPatches;
  }

  /// Writes `xcross-pod.json` metadata file recording all applied patches.
  void writePodMetadata({
    required File metadataFile,
    required String pod,
    required String version,
    required List<PodPatchRecord> patches,
    Map<String, Object?> extra = const {},
  }) {
    metadataFile.parent.createSync(recursive: true);
    final data = {
      'pod': pod,
      'version': version,
      'patches': [for (final p in patches) p.toJson()],
      ...extra,
    };
    metadataFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(data),
    );
  }
}
