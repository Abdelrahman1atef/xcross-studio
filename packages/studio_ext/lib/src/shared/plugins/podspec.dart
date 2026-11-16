// studio: 006 — read the parts of a CocoaPods podspec that a Swift package
// draft needs. Podspecs are Ruby; this reads the common declarative forms
// (`s.key = 'v'`, arrays, comma lists, hashes, `s.dependency`), not Ruby code.
import 'package:meta/meta.dart';

/// A pod the plugin depends on, with its CocoaPods requirement (`~> 8.4`).
@internal
final class PodDependency {
  const PodDependency(this.name, [this.requirement]);

  final String name;
  final String? requirement;

  @override
  String toString() => requirement == null ? name : '$name ($requirement)';
}

/// What a podspec declares for iOS.
@internal
final class Podspec {
  const Podspec({
    this.name,
    this.version,
    this.sourceFiles = const [],
    this.publicHeaderFiles = const [],
    this.excludeFiles = const [],
    this.dependencies = const [],
    this.frameworks = const [],
    this.weakFrameworks = const [],
    this.libraries = const [],
    this.deploymentTarget,
    this.resourceBundles = const {},
    this.resources = const [],
  });

  /// Parses podspec Ruby [source]. Unknown statements are ignored; macOS-only
  /// (`s.osx.…`) statements are skipped.
  factory Podspec.parse(String source) {
    final text = _stripComments(source);
    final variable =
        RegExp(
          r'Pod::Spec\.new\s+do\s*\|\s*(\w+)\s*\|',
        ).firstMatch(text)?.group(1) ??
        's';
    final v = RegExp.escape(variable);

    List<String> values(String key) {
      final out = <String>[];
      for (final match in RegExp(
        '(?<![\\w.])$v\\.(?:ios\\.)?$key\\s*=\\s*',
      ).allMatches(text)) {
        out.addAll(_strings(_valueAt(text, match.end)));
      }
      return out;
    }

    String? single(String key) {
      final list = values(key);
      return list.isEmpty ? null : list.first;
    }

    final dependencies = [
      for (final match in RegExp(
        '(?<![\\w.])$v\\.(?:ios\\.)?dependency\\s*\\(?\\s*'
        r'''['"]([^'"]+)['"](?:\s*,\s*['"]([^'"]+)['"])?''',
      ).allMatches(text))
        PodDependency(match.group(1)!, match.group(2)),
    ];

    String? deployment = single('deployment_target');
    if (deployment == null) {
      final platform = RegExp(
        '(?<![\\w.])$v\\.platform\\s*=\\s*:ios\\s*,\\s*'
        '''['"]([^'"]+)['"]''',
      ).firstMatch(text);
      deployment = platform?.group(1);
    }

    final bundles = <String, List<String>>{};
    for (final match in RegExp(
      '(?<![\\w.])$v\\.(?:ios\\.)?resource_bundles?\\s*=\\s*',
    ).allMatches(text)) {
      final value = _valueAt(text, match.end);
      for (final entry in RegExp(
        r'''['"]([^'"]+)['"]\s*=>\s*(\[[^\]]*\]|['"][^'"]+['"])''',
      ).allMatches(value)) {
        bundles[entry.group(1)!] = _strings(entry.group(2)!);
      }
    }

    final name = single('name');

    // Parse own subspec blocks (§10.4): s.subspec 'name' do |ss| ... end
    final subspecSourceFiles = <String>[];
    final subspecPublicHeaders = <String>[];
    final subspecExcludeFiles = <String>[];
    final subspecDependencies = <PodDependency>[];
    final subspecFrameworks = <String>[];
    final subspecWeakFrameworks = <String>[];
    final subspecLibraries = <String>[];
    final subspecResources = <String>[];
    final subspecBundles = <String, List<String>>{};
    final ownSubspecNames = <String>{};

    final subspecHeaderRegex = RegExp(
      '(?<![\\w.])$v\\.subspec\\s+[\'"]([^\'"]+)[\'"]\\s+do\\s*\\|\\s*(\\w+)\\s*\\|',
    );
    for (final match in subspecHeaderRegex.allMatches(text)) {
      final subspecName = match.group(1)!;
      final subspecVar = match.group(2)!;
      ownSubspecNames.add(subspecName);

      final blockStart = match.end;
      final blockEnd = _findBlockEnd(text, blockStart);
      final blockText = blockEnd >= 0
          ? text.substring(blockStart, blockEnd)
          : text.substring(blockStart);

      final sv = RegExp.escape(subspecVar);

      List<String> subValues(String key) {
        final out = <String>[];
        for (final m in RegExp(
          '(?<![\\w.])$sv\\.(?:ios\\.)?$key\\s*=\\s*',
        ).allMatches(blockText)) {
          out.addAll(_strings(_valueAt(blockText, m.end)));
        }
        return out;
      }

      subspecSourceFiles.addAll(subValues('source_files'));
      subspecPublicHeaders.addAll(subValues('public_header_files'));
      subspecExcludeFiles.addAll(subValues('exclude_files'));
      subspecFrameworks.addAll([
        ...subValues('frameworks'),
        ...subValues('framework'),
      ]);
      subspecWeakFrameworks.addAll([
        ...subValues('weak_frameworks'),
        ...subValues('weak_framework'),
      ]);
      subspecLibraries.addAll([
        ...subValues('libraries'),
        ...subValues('library'),
      ]);
      subspecResources.addAll([
        ...subValues('resources'),
        ...subValues('resource'),
      ]);

      for (final m in RegExp(
        '(?<![\\w.])$sv\\.(?:ios\\.)?dependency\\s*\\(?\\s*'
        r'''['"]([^'"]+)['"](?:\s*,\s*['"]([^'"]+)['"])?''',
      ).allMatches(blockText)) {
        subspecDependencies.add(PodDependency(m.group(1)!, m.group(2)));
      }

      for (final m in RegExp(
        '(?<![\\w.])$sv\\.(?:ios\\.)?resource_bundles?\\s*=\\s*',
      ).allMatches(blockText)) {
        final val = _valueAt(blockText, m.end);
        for (final entry in RegExp(
          r'''['"]([^'"]+)['"]\s*=>\s*(\[[^\]]*\]|['"][^'"]+['"])''',
        ).allMatches(val)) {
          subspecBundles[entry.group(1)!] = _strings(entry.group(2)!);
        }
      }
    }

    final finalDependencies = <PodDependency>[];
    for (final dep in dependencies) {
      final isDeclaredSubspec =
          ownSubspecNames.contains(dep.name) ||
          (name != null &&
              dep.name.startsWith('$name/') &&
              ownSubspecNames.contains(dep.name.substring(name.length + 1)));
      if (!isDeclaredSubspec) {
        finalDependencies.add(dep);
      }
    }

    if (ownSubspecNames.isNotEmpty) {
      for (final dep in subspecDependencies) {
        final isDeclaredSubspec =
            ownSubspecNames.contains(dep.name) ||
            (name != null &&
                dep.name.startsWith('$name/') &&
                ownSubspecNames.contains(dep.name.substring(name.length + 1)));
        if (!isDeclaredSubspec &&
            !finalDependencies.any((d) => d.name == dep.name)) {
          finalDependencies.add(dep);
        }
      }
    }

    return Podspec(
      name: name,
      version: single('version'),
      sourceFiles: [...values('source_files'), ...subspecSourceFiles],
      publicHeaderFiles: [
        ...values('public_header_files'),
        ...subspecPublicHeaders,
      ],
      excludeFiles: [...values('exclude_files'), ...subspecExcludeFiles],
      dependencies: finalDependencies,
      frameworks: [
        ...values('frameworks'),
        ...values('framework'),
        ...subspecFrameworks,
      ],
      weakFrameworks: [
        ...values('weak_frameworks'),
        ...values('weak_framework'),
        ...subspecWeakFrameworks,
      ],
      libraries: [
        ...values('libraries'),
        ...values('library'),
        ...subspecLibraries,
      ],
      deploymentTarget: deployment,
      resourceBundles: {...bundles, ...subspecBundles},
      resources: [
        ...values('resources'),
        ...values('resource'),
        ...subspecResources,
      ],
    );
  }

  final String? name;
  final String? version;
  final List<String> sourceFiles;
  final List<String> publicHeaderFiles;
  final List<String> excludeFiles;
  final List<PodDependency> dependencies;
  final List<String> frameworks;
  final List<String> weakFrameworks;
  final List<String> libraries;

  /// `s.ios.deployment_target` or `s.platform = :ios, 'x'`.
  final String? deploymentTarget;
  final Map<String, List<String>> resourceBundles;
  final List<String> resources;

  /// [source] without Ruby `#` comments (outside quotes).
  static String _stripComments(String source) {
    final out = StringBuffer();
    for (final line in source.split('\n')) {
      String? quote;
      var cut = line.length;
      for (var i = 0; i < line.length; i++) {
        final c = line[i];
        if (quote != null) {
          if (c == quote) quote = null;
        } else if (c == "'" || c == '"') {
          quote = c;
        } else if (c == '#') {
          cut = i;
          break;
        }
      }
      out.writeln(line.substring(0, cut));
    }
    return out.toString();
  }

  /// The Ruby value starting at [start]: a bracketed array or hash (to its
  /// matching close), otherwise the rest of the line.
  static String _valueAt(String text, int start) {
    var i = start;
    while (i < text.length && (text[i] == ' ' || text[i] == '\t')) {
      i++;
    }
    if (i < text.length && (text[i] == '[' || text[i] == '{')) {
      final open = text[i];
      final close = open == '[' ? ']' : '}';
      var depth = 0;
      for (var j = i; j < text.length; j++) {
        if (text[j] == open) depth++;
        if (text[j] == close) depth--;
        if (depth == 0) return text.substring(i, j + 1);
      }
      return text.substring(i);
    }
    final end = text.indexOf('\n', i);
    return text.substring(i, end < 0 ? text.length : end);
  }

  /// Every quoted string in [value], plus `%w[…]` words.
  static List<String> _strings(String value) {
    final words = RegExp(r'%w[\[(]([^\])]*)[\])]').firstMatch(value);
    if (words != null) {
      return words
          .group(1)!
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
    }
    return [
      for (final match in RegExp('''['"]([^'"]*)['"]''').allMatches(value))
        match.group(1)!,
    ];
  }

  /// Finds the end of a Ruby `do ... end` block starting after [start].
  static int _findBlockEnd(String text, int start) {
    var depth = 1;
    final tokenRegex = RegExp(r'\b(do|end)\b');
    for (final match in tokenRegex.allMatches(text, start)) {
      if (match.group(1) == 'do') {
        depth++;
      } else if (match.group(1) == 'end') {
        depth--;
        if (depth == 0) {
          return match.start;
        }
      }
    }
    return -1;
  }
}
