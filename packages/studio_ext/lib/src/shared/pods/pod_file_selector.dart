import 'package:meta/meta.dart';

/// Represents the categorized files selected for a pod (§8.2).
@internal
@immutable
final class PodFileSelection {
  const PodFileSelection({
    required this.sources,
    required this.headers,
    required this.preservePaths,
    required this.otherFiles,
  });

  /// Source files to be copied into `Sources/` (.c, .m, .mm, .cpp, .swift, etc.).
  final Set<String> sources;

  /// Header files (.h, .hpp, .inc, etc.).
  final Set<String> headers;

  /// Files specified in `preserve_paths` to be kept in the package root.
  final Set<String> preservePaths;

  /// Files matching globs that are neither sources nor headers (xib, storyboard, png, etc.).
  final Set<String> otherFiles;

  bool get isEmpty =>
      sources.isEmpty && headers.isEmpty && preservePaths.isEmpty;
}

/// Thrown when file selection fails, e.g. when source_files matches no file.
@internal
final class PodFileSelectionException implements Exception {
  PodFileSelectionException(this.message);

  final String message;

  @override
  String toString() => '[pod.conversion_failed] $message';
}

/// Implements CocoaPods file selection (§8.2, `file_accessor.rb` / `path_list.rb`).
@internal
final class PodFileSelector {
  const PodFileSelector();

  static const sourceExtensions = <String>{
    '.m',
    '.mm',
    '.i',
    '.c',
    '.cc',
    '.cxx',
    '.cpp',
    '.c++',
    '.swift',
  };

  static const headerExtensions = <String>{
    '.h',
    '.hh',
    '.hpp',
    '.ipp',
    '.tpp',
    '.hxx',
    '.def',
    '.inl',
    '.inc',
  };

  /// Selects and categorizes files from [allRelativePaths] based on [sourceFilesPatterns],
  /// [publicHeadersPatterns], [privateHeadersPatterns], and [preservePathsPatterns].
  PodFileSelection selectFiles({
    required Iterable<String> allRelativePaths,
    Iterable<String> sourceFilesPatterns = const [],
    Iterable<String> publicHeadersPatterns = const [],
    Iterable<String> privateHeadersPatterns = const [],
    Iterable<String> preservePathsPatterns = const [],
    Iterable<String> excludeFilesPatterns = const [],
  }) {
    final normalizedAll = allRelativePaths.map(_normalizePath).toList();
    final allDirs = _collectDirectories(normalizedAll);

    final excludeRegexes = _patternsToRegexes(excludeFilesPatterns, allDirs);
    bool isExcluded(String path) =>
        excludeRegexes.any((regex) => regex.hasMatch(path));

    final availableFiles = normalizedAll.where((f) => !isExcluded(f)).toList();

    // 1. Match source_files
    final sourceRegexes = _patternsToRegexes(
      sourceFilesPatterns,
      allDirs,
      defaultExtensions: {...sourceExtensions, ...headerExtensions},
    );

    final matchedSourcesAndHeaders = <String>{};
    for (final file in availableFiles) {
      if (sourceRegexes.any((r) => r.hasMatch(file))) {
        matchedSourcesAndHeaders.add(file);
      }
    }

    final selectedSources = <String>{};
    final selectedHeaders = <String>{};
    final otherFiles = <String>{};

    for (final file in matchedSourcesAndHeaders) {
      final ext = _extension(file).toLowerCase();
      if (sourceExtensions.contains(ext)) {
        selectedSources.add(file);
      } else if (headerExtensions.contains(ext)) {
        selectedHeaders.add(file);
      } else {
        otherFiles.add(file);
      }
    }

    // 2. Preserve paths
    final preserveRegexes = _patternsToRegexes(preservePathsPatterns, allDirs);
    final selectedPreserve = <String>{};
    for (final file in normalizedAll) {
      if (preserveRegexes.any((r) => r.hasMatch(file))) {
        selectedPreserve.add(file);
      }
    }

    if (sourceFilesPatterns.isNotEmpty &&
        selectedSources.isEmpty &&
        selectedHeaders.isEmpty) {
      throw PodFileSelectionException('source_files matched no file');
    }

    return PodFileSelection(
      sources: selectedSources,
      headers: selectedHeaders,
      preservePaths: selectedPreserve,
      otherFiles: otherFiles,
    );
  }

  static String _normalizePath(String path) {
    return path.replaceAll(r'\', '/').replaceAll(RegExp(r'^/+|/+$'), '');
  }

  static String _extension(String path) {
    final lastDot = path.lastIndexOf('.');
    final lastSlash = path.lastIndexOf('/');
    if (lastDot > lastSlash && lastDot != -1) {
      return path.substring(lastDot);
    }
    return '';
  }

  static Set<String> _collectDirectories(Iterable<String> files) {
    final dirs = <String>{};
    for (final file in files) {
      var current = file;
      while (current.contains('/')) {
        current = current.substring(0, current.lastIndexOf('/'));
        dirs.add(current.toLowerCase());
      }
    }
    return dirs;
  }

  static List<RegExp> _patternsToRegexes(
    Iterable<String> patterns,
    Set<String> directories, {
    Set<String>? defaultExtensions,
  }) {
    final regexes = <RegExp>[];
    for (final rawPattern in patterns) {
      final normalized = _normalizePath(rawPattern);
      if (normalized.isEmpty) continue;

      for (final expanded in _expandBraces(normalized)) {
        // Check if pattern names a directory (either ends with / or exists in known directories)
        final isDir =
            expanded.endsWith('/') ||
            directories.contains(expanded.toLowerCase());

        if (isDir &&
            defaultExtensions != null &&
            defaultExtensions.isNotEmpty) {
          // CocoaPods appends default extensions only for direct children of the directory
          final dirBase = expanded.endsWith('/')
              ? expanded.substring(0, expanded.length - 1)
              : expanded;
          for (final ext in defaultExtensions) {
            regexes.add(_globToRegex('$dirBase/*$ext'));
          }
        } else {
          regexes.add(_globToRegex(expanded));
        }
      }
    }
    return regexes;
  }

  /// Expands bash-style braces e.g. `{a,b}` or `{a,{b,c}}`.
  static List<String> _expandBraces(String pattern) {
    final openIdx = pattern.indexOf('{');
    if (openIdx == -1) return [pattern];

    var depth = 0;
    var closeIdx = -1;
    final commas = <int>[];

    for (var i = openIdx; i < pattern.length; i++) {
      if (pattern[i] == '{') {
        depth++;
      } else if (pattern[i] == '}') {
        depth--;
        if (depth == 0) {
          closeIdx = i;
          break;
        }
      } else if (pattern[i] == ',' && depth == 1) {
        commas.add(i);
      }
    }

    if (closeIdx == -1 || commas.isEmpty) {
      return [pattern];
    }

    final prefix = pattern.substring(0, openIdx);
    final suffix = pattern.substring(closeIdx + 1);

    final parts = <String>[];
    var start = openIdx + 1;
    for (final comma in commas) {
      parts.add(pattern.substring(start, comma));
      start = comma + 1;
    }
    parts.add(pattern.substring(start, closeIdx));

    final results = <String>[];
    for (final part in parts) {
      for (final expandedSuffix in _expandBraces('$prefix$part$suffix')) {
        results.add(expandedSuffix);
      }
    }
    return results;
  }

  /// Converts a file glob to a case-insensitive RegExp.
  static RegExp globToRegex(String glob) => _globToRegex(glob);

  /// Converts a file glob to a case-insensitive RegExp.
  static RegExp _globToRegex(String glob) {
    final buffer = StringBuffer('^');
    var i = 0;
    while (i < glob.length) {
      final c = glob[i];
      if (c == '*') {
        if (i + 1 < glob.length && glob[i + 1] == '*') {
          // '**'
          if (i + 2 < glob.length && glob[i + 2] == '/') {
            buffer.write('(?:.+/)?');
            i += 3;
            continue;
          } else {
            buffer.write('.*');
            i += 2;
            continue;
          }
        } else {
          // '*' matches anything except '/'
          buffer.write('[^/]*');
          i++;
          continue;
        }
      } else if (c == '?') {
        buffer.write('[^/]');
        i++;
        continue;
      } else if (c == '[') {
        final closeIdx = glob.indexOf(']', i);
        if (closeIdx != -1) {
          buffer.write(glob.substring(i, closeIdx + 1));
          i = closeIdx + 1;
          continue;
        } else {
          buffer.write(r'\[');
          i++;
          continue;
        }
      } else if (r'\.+^$()|'.contains(c)) {
        buffer.write('\\$c');
        i++;
        continue;
      } else {
        buffer.write(c);
        i++;
      }
    }
    buffer.write(r'$');
    return RegExp(buffer.toString(), caseSensitive: false);
  }
}
