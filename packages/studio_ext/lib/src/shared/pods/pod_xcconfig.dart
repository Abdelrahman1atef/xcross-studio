import 'package:meta/meta.dart';

@internal
final class PodBuildContext {
  const PodBuildContext({
    required this.simulator,
    required this.distribution,
    this.arch = 'arm64',
  });
  final bool simulator;
  final bool distribution;
  final String arch;
  String get sdk => simulator ? 'iphonesimulator' : 'iphoneos';
  String get config => distribution ? 'Release' : 'Debug';
}

@internal
final class ParsedXcconfig {
  const ParsedXcconfig(this.values, this.ignored);
  final Map<String, List<String>> values;
  final List<String> ignored;
}

/// Selects conditional CocoaPods build settings and expands known variables.
@internal
final class PodXcconfig {
  const PodXcconfig();

  static const supportedKeys = {
    'GCC_PREPROCESSOR_DEFINITIONS',
    'HEADER_SEARCH_PATHS',
    'USER_HEADER_SEARCH_PATHS',
    'OTHER_CFLAGS',
    'OTHER_CPLUSPLUSFLAGS',
    'CLANG_CXX_LANGUAGE_STANDARD',
    'GCC_C_LANGUAGE_STANDARD',
    'CLANG_CXX_LIBRARY',
    'CLANG_ENABLE_OBJC_WEAK',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS',
    'OTHER_SWIFT_FLAGS',
    'SWIFT_VERSION',
    'OTHER_LDFLAGS',
    'DEFINES_MODULE',
    'APPLICATION_EXTENSION_API_ONLY',
    'ENABLE_BITCODE',
    'VALID_ARCHS',
    'EXCLUDED_ARCHS',
    'IPHONEOS_DEPLOYMENT_TARGET',
  };

  ParsedXcconfig parse(
    Map<String, Object?> source, {
    required PodBuildContext context,
    required String pod,
    required Map<String, String> podRoots,
    required String publicHeaders,
  }) {
    final values = <String, List<String>>{};
    final ignored = <String>[];
    for (final entry in source.entries) {
      final separator = entry.key.indexOf('[');
      final key = separator < 0 ? entry.key : entry.key.substring(0, separator);
      final conditions = separator < 0 ? '' : entry.key.substring(separator);
      if (key.isEmpty || (conditions.isNotEmpty && !conditions.endsWith(']'))) {
        ignored.add('pod.setting_ignored: ${entry.key}');
        continue;
      }
      if (!_matches(conditions, context)) continue;
      if (!supportedKeys.contains(key)) {
        ignored.add('pod.setting_ignored: $key');
        continue;
      }
      final text = entry.value?.toString() ?? '';
      final expanded = text.replaceAllMapped(
        RegExp(r'\$\{([^}]+)\}|\$\(([^)]+)\)'),
        (variable) {
          final name = variable.group(1) ?? variable.group(2)!;
          if (name == 'inherited') return '';
          if (name == 'PODS_TARGET_SRCROOT') return podRoots[pod] ?? '';
          if (name == 'PODS_ROOT') return '<pods-root>';
          if (name == 'PODS_ROOT/Headers/Public') return publicHeaders;
          ignored.add('pod.setting_ignored: $name');
          return variable.group(0)!;
        },
      );
      var resolved = expanded;
      for (final root in podRoots.entries) {
        resolved = resolved.replaceAll('<pods-root>/${root.key}', root.value);
      }
      resolved = resolved.replaceAll(
        '<pods-root>/Headers/Public',
        publicHeaders,
      );
      if (resolved.contains('<pods-root>')) {
        ignored.add('pod.setting_ignored: unknown PODS_ROOT path');
      }
      values.putIfAbsent(key, () => []).add(resolved.trim());
    }
    return ParsedXcconfig(values, ignored);
  }

  bool _matches(String conditions, PodBuildContext context) {
    final matches = RegExp(
      r'\[([^=\]]+)=([^\]]+)\]',
    ).allMatches(conditions).toList();
    if (conditions.isNotEmpty && matches.isEmpty) return false;
    for (final match in matches) {
      final actual = switch (match.group(1)) {
        'sdk' => context.sdk,
        'arch' => context.arch,
        'config' => context.config,
        _ => null,
      };
      if (actual == null) return false;
      final pattern =
          '^${match.group(2)!.split('*').map(RegExp.escape).join('.*')}'
          r'$';
      if (!RegExp(pattern, caseSensitive: false).hasMatch(actual)) return false;
    }
    return true;
  }
}
