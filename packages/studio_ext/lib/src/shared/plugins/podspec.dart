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

    return Podspec(
      name: single('name'),
      version: single('version'),
      sourceFiles: values('source_files'),
      publicHeaderFiles: values('public_header_files'),
      excludeFiles: values('exclude_files'),
      dependencies: dependencies,
      frameworks: [...values('frameworks'), ...values('framework')],
      weakFrameworks: [
        ...values('weak_frameworks'),
        ...values('weak_framework'),
      ],
      libraries: [...values('libraries'), ...values('library')],
      deploymentTarget: deployment,
      resourceBundles: bundles,
      resources: [...values('resources'), ...values('resource')],
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
}
