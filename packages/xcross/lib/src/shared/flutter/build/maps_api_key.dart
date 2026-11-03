// studio: 016 — the Google Maps key AppDelegate passes to GMSServices, for
// the generic runner (specs/016-push-firebase-maps, AC-016-8).
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:xcross/src/shared/flutter/build/flutter_app_entitlements.dart';

/// Where the key came from; the key itself is never printed.
@internal
@immutable
final class MapsApiKey {
  const MapsApiKey({required this.source, this.key});

  /// `null` when the AppDelegate calls `provideAPIKey` with something xcross
  /// cannot resolve.
  final String? key;

  /// File name, plus the Info.plist key when it was read from there.
  final String source;

  bool get resolved => key != null && key!.isNotEmpty;
}

/// Finds `GMSServices.provideAPIKey(…)` in the app target's sources.
@internal
final class MapsApiKeyLocator {
  MapsApiKeyLocator({
    required this.fileSystem,
    required this.paths,
    required this.resolveVariable,
  });

  final HostFileSystemInterface fileSystem;
  final p.Context paths;

  /// Value of an xcconfig build setting (for `$(VAR)` in Info.plist), or
  /// `null` when it is not set.
  final String? Function(String name) resolveVariable;

  static final _swiftCall = RegExp(
    r'GMSServices\s*\.\s*provideAPIKey\s*\(\s*([^)]*?)\s*\)',
  );
  static final _objcCall = RegExp(
    r'\[\s*GMSServices\s+provideAPIKey\s*:\s*([^\]]*?)\s*\]',
  );
  static final _swiftPlist = RegExp(
    // The call pattern stops at the first `)`, so no closing paren here.
    r'''object\s*\(\s*forInfoDictionaryKey\s*:\s*"([^"]+)"''',
  );
  static final _objcPlist = RegExp(
    r'''objectForInfoDictionaryKey\s*:\s*@"([^"]+)"''',
  );
  static final _swiftLiteral = RegExp(r'^"([^"\\]+)"$');
  static final _objcLiteral = RegExp(r'^@"([^"\\]+)"$');
  static final _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
  static final _variable = RegExp(r'^\$[({]([A-Za-z_][A-Za-z0-9_]*)[)}]$');

  /// The key the app's `ios/Runner` sources pass, or `null` when none of
  /// them calls `provideAPIKey`.
  MapsApiKey? locate(String projectRoot) {
    final runner = fileSystem.directory(
      paths.join(projectRoot, 'ios', 'Runner'),
    );
    if (!runner.existsSync()) return null;
    final sources = [
      for (final entity in runner.listSync())
        if (const {
          '.swift',
          '.m',
          '.mm',
        }.contains(paths.extension(entity.path)))
          entity.path,
    ]..sort();
    for (final source in sources) {
      final text = stripComments(fileSystem.file(source).readAsStringSync());
      final name = paths.basename(source);
      final found = fromSource(text, objc: paths.extension(source) != '.swift');
      if (found == null) continue;
      return switch (found) {
        (literal: final String key, plistKey: null) => MapsApiKey(
          source: name,
          key: key,
        ),
        (literal: null, :final String plistKey) => MapsApiKey(
          source: '$name → Info.plist $plistKey',
          key: _fromInfoPlist(projectRoot, plistKey),
        ),
        _ => MapsApiKey(source: name),
      };
    }
    return null;
  }

  /// The argument of the first `provideAPIKey` call in [code] (comments
  /// already removed): a literal, an Info.plist key, or neither (both
  /// `null`); `null` without a call. A plain identifier is followed to its
  /// `let`/`var`/local declaration.
  @visibleForTesting
  static ({String? literal, String? plistKey})? fromSource(
    String code, {
    required bool objc,
  }) {
    final call = (objc ? _objcCall : _swiftCall).firstMatch(code);
    if (call == null) return null;
    var argument = call.group(1)!.trim();
    if (_identifier.hasMatch(argument)) {
      final declaration = RegExp(
        objc
            ? '\\b$argument\\s*=\\s*([^;]+);'
            : '(?:let|var)\\s+$argument\\s*(?::\\s*[A-Za-z?!]+\\s*)?=\\s*'
                  r'([^\n;]+)',
      ).firstMatch(code);
      if (declaration != null) argument = declaration.group(1)!.trim();
    }
    final literal = (objc ? _objcLiteral : _swiftLiteral).firstMatch(argument);
    if (literal != null) return (literal: literal.group(1), plistKey: null);
    final plist = (objc ? _objcPlist : _swiftPlist).firstMatch(argument);
    if (plist != null) return (literal: null, plistKey: plist.group(1));
    return (literal: null, plistKey: null);
  }

  /// [source] without `//` and `/* */` comments (string contents with `//`,
  /// such as URLs, are kept).
  @visibleForTesting
  static String stripComments(String source) {
    final out = StringBuffer();
    var i = 0;
    var inString = false;
    while (i < source.length) {
      final char = source[i];
      if (inString) {
        out.write(char);
        if (char == r'\' && i + 1 < source.length) {
          out.write(source[i + 1]);
          i += 2;
          continue;
        }
        if (char == '"') inString = false;
        i++;
        continue;
      }
      if (char == '"') {
        inString = true;
        out.write(char);
        i++;
      } else if (source.startsWith('//', i)) {
        final end = source.indexOf('\n', i);
        i = end < 0 ? source.length : end;
      } else if (source.startsWith('/*', i)) {
        final end = source.indexOf('*/', i + 2);
        i = end < 0 ? source.length : end + 2;
      } else {
        out.write(char);
        i++;
      }
    }
    return out.toString();
  }

  String? _fromInfoPlist(String projectRoot, String plistKey) {
    final file = fileSystem.file(
      paths.join(projectRoot, 'ios', 'Runner', 'Info.plist'),
    );
    if (!file.existsSync()) return null;
    final Object? value;
    try {
      value = FlutterAppEntitlements.parseDictionary(
        file.readAsStringSync(),
      )[plistKey];
    } on FormatException {
      return null;
    }
    if (value is! String || value.isEmpty) return null;
    final variable = _variable.firstMatch(value);
    if (variable == null) return value.contains(r'$') ? null : value;
    final resolved = resolveVariable(variable.group(1)!);
    return resolved == null || resolved.isEmpty ? null : resolved;
  }
}
