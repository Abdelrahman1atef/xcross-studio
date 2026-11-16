import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/pods/pod_xcconfig.dart';

/// Resolved and converted build settings for SwiftPM manifest generation (§8.4).
@internal
@immutable
final class PodTargetSettings {
  const PodTargetSettings({
    this.defines = const {},
    this.headerSearchPaths = const [],
    this.cFlags = const [],
    this.cxxFlags = const [],
    this.cLanguageStandard,
    this.cxxLanguageStandard,
    this.swiftDefines = const {},
    this.swiftFlags = const [],
    this.linkedFrameworks = const [],
    this.linkedLibraries = const [],
    this.linkerFlags = const [],
    this.ignoredSettings = const [],
  });

  final Map<String, String?> defines;
  final List<String> headerSearchPaths;
  final List<String> cFlags;
  final List<String> cxxFlags;
  final String? cLanguageStandard;
  final String? cxxLanguageStandard;
  final Map<String, String?> swiftDefines;
  final List<String> swiftFlags;
  final List<String> linkedFrameworks;
  final List<String> linkedLibraries;
  final List<String> linkerFlags;
  final List<String> ignoredSettings;
}

/// Applies §8.4 rules to convert parsed xcconfig into SwiftPM target settings.
@internal
final class PodSettingsConverter {
  const PodSettingsConverter();

  /// Converts parsed [xcconfig] and [compilerFlags] into [PodTargetSettings].
  PodTargetSettings convert({
    required ParsedXcconfig xcconfig,
    required String pod,
    String? compilerFlags,
    Map<String, Object?>? userTargetXcconfig,
  }) {
    final defines = <String, String?>{};
    final headerSearchPaths = <String>[];
    final cFlags = <String>[];
    final cxxFlags = <String>[];
    String? cStandard;
    String? cxxStandard;
    final swiftDefines = <String, String?>{};
    final swiftFlags = <String>[];
    final frameworks = <String>[];
    final libraries = <String>[];
    final linkerFlags = <String>[];
    final ignored = List<String>.from(xcconfig.ignored);

    // 1. Process xcconfig keys
    for (final entry in xcconfig.values.entries) {
      final key = entry.key;
      final rawList = entry.value;

      switch (key) {
        case 'GCC_PREPROCESSOR_DEFINITIONS':
          for (final raw in rawList) {
            for (final token in _splitTokens(raw)) {
              if (token.isEmpty ||
                  token == r'$(inherited)' ||
                  token == r'${inherited}') {
                continue;
              }
              final (name, value) = _parseDefine(token);
              defines[name] = value;
            }
          }

        case 'HEADER_SEARCH_PATHS' || 'USER_HEADER_SEARCH_PATHS':
          for (final raw in rawList) {
            for (final token in _splitTokens(raw)) {
              if (token.isEmpty ||
                  token == r'$(inherited)' ||
                  token == r'${inherited}') {
                continue;
              }
              headerSearchPaths.add(token.replaceAll('"', ''));
            }
          }

        case 'OTHER_CFLAGS':
          for (final raw in rawList) {
            final res = _filterFlags(raw, ignored, pod);
            cFlags.addAll(res.flags);
            if (res.cStandard != null) cStandard = res.cStandard;
            for (final def in res.defines.entries) {
              defines[def.key] = def.value;
            }
          }

        case 'OTHER_CPLUSPLUSFLAGS':
          for (final raw in rawList) {
            final res = _filterFlags(raw, ignored, pod);
            cxxFlags.addAll(res.flags);
            if (res.cxxStandard != null) cxxStandard = res.cxxStandard;
            for (final def in res.defines.entries) {
              defines[def.key] = def.value;
            }
          }

        case 'CLANG_CXX_LANGUAGE_STANDARD':
          for (final raw in rawList) {
            cxxStandard = _mapCxxStandard(raw);
          }

        case 'GCC_C_LANGUAGE_STANDARD':
          for (final raw in rawList) {
            cStandard = _mapCStandard(raw);
          }

        case 'CLANG_CXX_LIBRARY':
          for (final raw in rawList) {
            if (raw.trim() != 'libc++') {
              ignored.add(
                'pod.setting_ignored: $pod CLANG_CXX_LIBRARY=$raw (only libc++ supported)',
              );
            }
          }

        case 'CLANG_ENABLE_OBJC_WEAK':
          for (final raw in rawList) {
            if (raw.trim().toLowerCase() == 'yes') {
              cFlags.add('-fobjc-weak');
              cxxFlags.add('-fobjc-weak');
            }
          }

        case 'SWIFT_ACTIVE_COMPILATION_CONDITIONS':
          for (final raw in rawList) {
            for (final token in _splitTokens(raw)) {
              if (token.isNotEmpty) swiftDefines[token] = null;
            }
          }

        case 'OTHER_SWIFT_FLAGS':
          for (final raw in rawList) {
            for (final token in _splitTokens(raw)) {
              if (token.startsWith('-D')) {
                swiftDefines[token.substring(2)] = null;
              } else if (token.isNotEmpty) {
                ignored.add(
                  'pod.setting_ignored: $pod OTHER_SWIFT_FLAGS $token',
                );
              }
            }
          }

        case 'OTHER_LDFLAGS':
          for (final raw in rawList) {
            final tokens = _splitTokens(raw);
            var i = 0;
            while (i < tokens.length) {
              final t = tokens[i];
              if (t == '-framework' && i + 1 < tokens.length) {
                frameworks.add(tokens[i + 1]);
                i += 2;
              } else if (t == '-weak_framework' && i + 1 < tokens.length) {
                linkerFlags.add('-weak_framework');
                linkerFlags.add(tokens[i + 1]);
                i += 2;
              } else if (t.startsWith('-l')) {
                libraries.add(t.substring(2));
                i++;
              } else if (t == '-ObjC') {
                // Already globally linked in xcross
                i++;
              } else if (t == '-force_load') {
                ignored.add(
                  'pod.setting_ignored: $pod OTHER_LDFLAGS -force_load',
                );
                i++;
              } else {
                linkerFlags.add(t);
                i++;
              }
            }
          }

        case 'DEFINES_MODULE' ||
            'APPLICATION_EXTENSION_API_ONLY' ||
            'ENABLE_BITCODE' ||
            'VALID_ARCHS' ||
            'EXCLUDED_ARCHS' ||
            'IPHONEOS_DEPLOYMENT_TARGET' ||
            'SWIFT_VERSION':
          // Ignored silently per plan §8.4
          break;

        default:
          ignored.add('pod.setting_ignored: $pod $key');
      }
    }

    // 2. Process compiler_flags (if any)
    if (compilerFlags != null && compilerFlags.isNotEmpty) {
      final res = _filterFlags(compilerFlags, ignored, pod);
      cFlags.addAll(res.flags);
      cxxFlags.addAll(res.flags);
      for (final def in res.defines.entries) {
        defines[def.key] = def.value;
      }
    }

    // 3. Process user_target_xcconfig (linker keys only)
    if (userTargetXcconfig != null) {
      for (final entry in userTargetXcconfig.entries) {
        final key = entry.key;
        if (key == 'OTHER_LDFLAGS') {
          final tokens = _splitTokens(entry.value?.toString() ?? '');
          var i = 0;
          while (i < tokens.length) {
            final t = tokens[i];
            if (t == '-framework' && i + 1 < tokens.length) {
              frameworks.add(tokens[i + 1]);
              i += 2;
            } else if (t == '-weak_framework' && i + 1 < tokens.length) {
              linkerFlags.add('-weak_framework');
              linkerFlags.add(tokens[i + 1]);
              i += 2;
            } else if (t.startsWith('-l')) {
              libraries.add(t.substring(2));
              i++;
            } else if (t == '-ObjC') {
              i++;
            } else {
              linkerFlags.add(t);
              i++;
            }
          }
        } else {
          ignored.add('pod.setting_ignored: $pod user_target_xcconfig $key');
        }
      }
    }

    return PodTargetSettings(
      defines: defines,
      headerSearchPaths: headerSearchPaths,
      cFlags: cFlags,
      cxxFlags: cxxFlags,
      cLanguageStandard: cStandard,
      cxxLanguageStandard: cxxStandard,
      swiftDefines: swiftDefines,
      swiftFlags: swiftFlags,
      linkedFrameworks: frameworks,
      linkedLibraries: libraries,
      linkerFlags: linkerFlags,
      ignoredSettings: ignored,
    );
  }

  static ({
    List<String> flags,
    Map<String, String?> defines,
    String? cStandard,
    String? cxxStandard,
  })
  _filterFlags(String raw, List<String> ignored, String pod) {
    final tokens = _splitTokens(raw);
    final keptFlags = <String>[];
    final defs = <String, String?>{};
    String? cStd;
    String? cxxStd;

    var i = 0;
    while (i < tokens.length) {
      final token = tokens[i];

      // -Werror / -Werror=* -> always dropped
      if (token == '-Werror' || token.startsWith('-Werror=')) {
        i++;
        continue;
      }

      // Language standard mapping
      if (token.startsWith('-std=c++') || token.startsWith('-std=gnu++')) {
        cxxStd = _mapCxxStandard(token.substring(5));
        i++;
        continue;
      }
      if (token.startsWith('-std=c') || token.startsWith('-std=gnu')) {
        cStd = _mapCStandard(token.substring(5));
        i++;
        continue;
      }

      // -D / -U
      if (token.startsWith('-D')) {
        final (name, val) = _parseDefine(token.substring(2));
        defs[name] = val;
        i++;
        continue;
      }
      if (token.startsWith('-U')) {
        keptFlags.add(token);
        i++;
        continue;
      }

      // Allowed warning / silence flags
      if (token.startsWith('-W') ||
          token.startsWith('-Wno-') ||
          token == '-w') {
        keptFlags.add(token);
        i++;
        continue;
      }

      // ARC / weak flags
      if (token == '-fno-objc-arc' ||
          token == '-fobjc-arc' ||
          token == '-fobjc-arc-exceptions' ||
          token == '-fobjc-weak') {
        keptFlags.add(token);
        i++;
        continue;
      }

      // Visibility
      if (token.startsWith('-fvisibility=')) {
        keptFlags.add(token);
        i++;
        continue;
      }

      // Other flags dropped with warning
      ignored.add('pod.setting_ignored: $pod flag $token');
      i++;
    }

    return (
      flags: keptFlags,
      defines: defs,
      cStandard: cStd,
      cxxStandard: cxxStd,
    );
  }

  static (String name, String? value) _parseDefine(String token) {
    final eqIdx = token.indexOf('=');
    if (eqIdx == -1) return (token, null);
    return (token.substring(0, eqIdx), token.substring(eqIdx + 1));
  }

  static List<String> _splitTokens(String text) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (c == ' ' && !inQuotes) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
      } else {
        buffer.write(c);
      }
    }
    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
    }
    return tokens;
  }

  static String _mapCxxStandard(String std) {
    final lower = std.toLowerCase().replaceAll('+', 'x');
    if (lower.contains('17')) return 'cxx17';
    if (lower.contains('14')) return 'cxx14';
    if (lower.contains('20')) return 'cxx20';
    if (lower.contains('11')) return 'cxx11';
    return std;
  }

  static String _mapCStandard(String std) {
    final lower = std.toLowerCase();
    if (lower.contains('17') || lower.contains('18')) return 'c17';
    if (lower.contains('11')) return 'c11';
    if (lower.contains('99')) return 'c99';
    return std;
  }
}
