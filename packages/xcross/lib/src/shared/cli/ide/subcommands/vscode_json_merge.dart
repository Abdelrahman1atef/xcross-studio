import 'dart:convert';
import 'package:meta/meta.dart';

@internal
// studio: 009 — two named entries so the iPhone shows up in the IDE's run
// dropdown in both modes; iOS 15/16 only run release/profile builds.
/// The debug (hot reload) entry; needs iOS 17 or later.
const String xcrossLaunchName = 'xcross: iPhone · debug (iOS 17+)';

/// Earlier name of the debug entry, still recognised (and renamed) on update.
@internal
const String xcrossLegacyLaunchName = 'xcross: iOS device';

/// The release entry (`--release`); the one iOS 15/16 devices can run.
@internal
const String xcrossReleaseLaunchName = 'xcross: iPhone · release (iOS 15/16)';
@internal
const String dapPathSetting = 'dart.customFlutterDapPath';
@internal
const String dapPathValue = '.vscode/xcross_dap.dart';
@internal
const String promptErrorsSetting = 'dart.promptToRunIfErrors';

/// Marks a launch config as xcross-owned. Carried in the config's `env` (a
/// schema-valid Dart launch field) so editors don't flag an unknown key.
@internal
const String xcrossEnvKey = 'XCROSS';
@internal
const String xcrossEnvValue = 'true';

/// JSONC parse/merge helpers for VS Code launch.json / settings.json.
@internal
abstract final class VscodeJsonMerge {
  /// Strip JSONC sugar VS Code allows: `//` / `/* */` comments and trailing
  /// commas before `}` / `]`. Strings are left untouched.
  static String stripJsonc(String source) {
    final out = StringBuffer();
    var i = 0;
    while (i < source.length) {
      final c = source[i];
      if (c == '"') {
        i = _copyStringLiteral(source, i, out);
        continue;
      }
      if (_skipComment(source, i) case final afterComment?) {
        i = afterComment;
        continue;
      }
      if (c == ',') {
        final afterComma = _skipTrivia(source, i + 1);
        if (afterComma < source.length &&
            (source[afterComma] == '}' || source[afterComma] == ']')) {
          i = afterComma;
          continue;
        }
      }
      out.write(c);
      i++;
    }
    return out.toString();
  }

  /// Copy the string literal opening at [start] verbatim, escapes included,
  /// so that `//`, `/*` and `,` inside it survive. Returns the index just
  /// past the closing quote, or the end of input for an unterminated string.
  static int _copyStringLiteral(String source, int start, StringBuffer out) {
    out.write(source[start]);
    var i = start + 1;
    while (i < source.length) {
      final c = source[i];
      out.write(c);
      if (c == r'\' && i + 1 < source.length) {
        out.write(source[i + 1]);
        i += 2;
        continue;
      }
      i++;
      if (c == '"') return i;
    }
    return i;
  }

  /// Index just past the comment starting at [start], or null when [start]
  /// does not open one. A `//` comment stops *at* its newline so the line
  /// structure of the document is preserved.
  static int? _skipComment(String source, int start) {
    if (start + 1 >= source.length || source[start] != '/') return null;
    var i = start + 2;
    switch (source[start + 1]) {
      case '/':
        while (i < source.length && source[i] != '\n') {
          i++;
        }
        return i;
      case '*':
        while (i + 1 < source.length &&
            !(source[i] == '*' && source[i + 1] == '/')) {
          i++;
        }
        return i + 2 <= source.length ? i + 2 : source.length;
      default:
        return null;
    }
  }

  static bool _isSpace(String c) =>
      c == ' ' || c == '\t' || c == '\n' || c == '\r';

  /// Skip whitespace and comments; returns the index of the next real token.
  static int _skipTrivia(String source, int start) {
    var i = start;
    while (i < source.length) {
      if (_isSpace(source[i])) {
        i++;
        continue;
      }
      if (_skipComment(source, i) case final afterComment?) {
        i = afterComment;
        continue;
      }
      break;
    }
    return i;
  }

  /// Parse JSON or JSONC. Throws [FormatException] on failure.
  static Object? parseJsonc(String source) => jsonDecode(stripJsonc(source));

  static bool jsonDeepEqual(Object? a, Object? b) => switch ((a, b)) {
    _ when identical(a, b) => true,
    (final Map<Object?, Object?> x, final Map<Object?, Object?> y) =>
      x.length == y.length &&
          x.keys.every((k) => y.containsKey(k) && jsonDeepEqual(x[k], y[k])),
    (final List<Object?> x, final List<Object?> y) =>
      x.length == y.length &&
          x.indexed.every((e) => jsonDeepEqual(e.$2, y[e.$1])),
    _ => a == b,
  };

  static String encodePrettyJson(Object? value) =>
      '${const JsonEncoder.withIndent('  ').convert(value)}\n';

  /// Canonical launch.json fields for the xcross entry (except `args`).
  static Map<String, Object?> xcrossLaunchFields([
    String name = xcrossLaunchName,
  ]) => {
    'name': name,
    'type': 'dart',
    'request': 'launch',
    'debuggerType': 'flutter',
    'program': 'lib/main.dart',
    'cwd': r'${workspaceFolder}',
  };

  /// The xcross marker merged onto the entry's own `env` entries.
  static Map<String, Object?> _withMarker(
    Object? env,
    Map<String, String> generatedEnvironment,
  ) => {
    if (env case final Map<Object?, Object?> existing)
      for (final e in existing.entries) '${e.key}': e.value,
    ...generatedEnvironment,
    xcrossEnvKey: xcrossEnvValue,
  };

  /// Overwrite the xcross-managed fields on an existing launch entry while
  /// keeping the user's own keys, their original order, their `env` and their
  /// `args` (device flags they typed there must survive a re-run).
  /// The legacy top-level `xcross` flag is migrated into `env`.
  static Map<String, Object?> _withCanonicalFields(
    Map<Object?, Object?> entry,
    Map<String, String> generatedEnvironment, {
    String name = xcrossLaunchName,
    bool release = false,
  }) {
    final merged = <String, Object?>{
      for (final e in entry.entries) '${e.key}': e.value,
    };
    final args = merged.containsKey('args') ? merged['args'] : <Object?>[];
    final env = _withMarker(merged['env'], generatedEnvironment);
    return merged
      ..remove('xcross')
      ..addAll(xcrossLaunchFields(name))
      ..['env'] = env
      ..['args'] = release && !_hasModeArg(args)
          ? [...?(args as List<Object?>?), '--release']
          : args;
  }

  static bool _hasModeArg(Object? args) =>
      args is List &&
      (args.contains('--release') || args.contains('--profile'));

  static bool _isXcrossConfig(Object? config) =>
      config is Map &&
      (config['name'] == xcrossLaunchName ||
          config['name'] == xcrossLegacyLaunchName ||
          config['name'] == xcrossReleaseLaunchName ||
          config['xcross'] == true ||
          (config['env'] is Map &&
              (config['env']! as Map)[xcrossEnvKey] == xcrossEnvValue));

  /// The xcross release/profile entry (by name, or marker + mode flag).
  static bool _isXcrossRelease(Object? config) =>
      config is Map &&
      (config['name'] == xcrossReleaseLaunchName ||
          (_isXcrossConfig(config) && _hasModeArg(config['args'])));

  /// Upsert the xcross launch configuration into a launch.json document.
  static Map<String, Object?> mergeLaunchDoc(
    Map<String, Object?>? existing, {
    Map<String, String> generatedEnvironment = const {},
  }) {
    final doc = <String, Object?>{...?existing};
    doc.putIfAbsent('version', () => '0.2.0');

    final configs = <Object?>[...?doc['configurations'] as List<Object?>?];
    final index = configs.indexWhere(
      (config) => _isXcrossConfig(config) && !_isXcrossRelease(config),
    );
    if (index < 0) {
      configs.add({
        ...xcrossLaunchFields(),
        'env': _withMarker(null, generatedEnvironment),
        'args': <Object?>[],
      });
    } else {
      configs[index] = _withCanonicalFields(
        configs[index]! as Map,
        generatedEnvironment,
      );
    }
    final release = configs.indexWhere(_isXcrossRelease);
    if (release < 0) {
      configs.add({
        ...xcrossLaunchFields(xcrossReleaseLaunchName),
        'env': _withMarker(null, generatedEnvironment),
        'args': <Object?>['--release'],
      });
    } else {
      configs[release] = _withCanonicalFields(
        configs[release]! as Map,
        generatedEnvironment,
        name: xcrossReleaseLaunchName,
        release: true,
      );
    }

    doc['configurations'] = configs;
    return doc;
  }

  /// Upsert xcross DAP settings onto a settings.json document.
  static Map<String, Object?> mergeSettingsDoc(
    Map<String, Object?>? existing,
  ) => {...?existing, dapPathSetting: dapPathValue, promptErrorsSetting: false};
}
