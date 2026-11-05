// studio: 018 — iOS carries dynamic libraries only inside framework bundles
// (the Swift runtime is the one exception). A `libX.dylib` loose in
// `Frameworks` makes App Store Connect answer 90429, usually naming the Swift
// libraries instead of the real cause. The Swift Package Manager build of the
// plugins produces such a library (`libFlutterPluginsGenerated.dylib`), so an
// App Store export wraps each one in `X.framework/X` and points everything
// that loads it at the new place.
import 'dart:io';
import 'dart:typed_data';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/release/macho_rename.dart';
import 'package:xcross/src/shared/errors/errors.dart';

/// Turns the loose dylibs of an app's `Frameworks` folder into frameworks.
@internal
abstract final class LooseDylibs {
  /// Rewrites `<appPath>/Frameworks/lib<X>.dylib` as
  /// `<X>.framework/<X>` with an Info.plist, and every load of the old path
  /// in the app's binaries to the new one. Call before signing. Returns the
  /// file names converted, sorted.
  static Future<List<String>> frameworkize({
    required HostFileSystemInterface fileSystem,
    required String appPath,
    required String version,
    required String build,
    required String minimumOs,
  }) async {
    final frameworks = p.join(appPath, 'Frameworks');
    final directory = fileSystem.directory(frameworks);
    if (!directory.existsSync()) return const [];
    final loose = [
      for (final entity in directory.listSync())
        if (entity is File &&
            p.basename(entity.path).endsWith('.dylib') &&
            !p.basename(entity.path).startsWith('libswift'))
          p.basename(entity.path),
    ]..sort();
    if (loose.isEmpty) return const [];

    // File name -> framework (and executable) name.
    final names = <String, String>{};
    for (final fileName in loose) {
      final stem = fileName.substring(0, fileName.length - '.dylib'.length);
      final base = stem.startsWith('lib') && stem.length > 3
          ? stem.substring(3)
          : stem;
      var attempt = 0;
      String candidate() => attempt == 0 ? base : '${base}Lib$attempt';
      while (fileSystem
              .directory(p.join(frameworks, '${candidate()}.framework'))
              .existsSync() ||
          names.containsValue(candidate())) {
        attempt++;
      }
      names[fileName] = candidate();
    }

    // Every binary of the app: its own id, and what it loads.
    await for (final entity
        in fileSystem.directory(appPath).list(recursive: true)) {
      if (entity is! File) continue;
      final handle = await entity.open();
      final Uint8List head;
      try {
        head = Uint8List.fromList(await handle.read(4));
      } finally {
        await handle.close();
      }
      if (!looksLikeMachO(head)) continue;
      final bytes = await entity.readAsBytes();
      // Compared by name: a host may list paths in another spelling than the
      // one the app path was given in (a `\?\` prefix on Windows).
      final parent = p.dirname(entity.path);
      final ownName =
          p.basename(parent) == 'Frameworks' &&
              p.basename(p.dirname(parent)) == p.basename(appPath)
          ? names[p.basename(entity.path)]
          : null;
      final Uint8List? rewritten;
      try {
        rewritten = renameDylibPaths(bytes, (command, path) {
          if (command == 0xd) {
            return ownName == null
                ? null
                : '@rpath/$ownName.framework/$ownName';
          }
          final target = names[path.split('/').last];
          if (target == null || !path.startsWith('@')) return null;
          final folder = path.substring(
            0,
            path.length - path.split('/').last.length,
          );
          return '$folder$target.framework/$target';
        });
      } on FormatException catch (error) {
        throw XcrossError(
          'Cannot make ${p.relative(entity.path, from: appPath)} load the '
          'plugin library from a framework: ${error.message}\n'
          'hint: App Store Connect refuses standalone dynamic libraries '
          '(90429).',
        );
      }
      if (rewritten != null) await entity.writeAsBytes(rewritten);
    }

    for (final MapEntry(key: fileName, value: name) in names.entries) {
      final folder = p.join(frameworks, '$name.framework');
      await fileSystem.directory(folder).create(recursive: true);
      await fileSystem
          .file(p.join(frameworks, fileName))
          .rename(p.join(folder, name));
      await fileSystem
          .file(p.join(folder, 'Info.plist'))
          .writeAsString(
            _infoPlist(
              name: name,
              version: version,
              build: build,
              minimumOs: minimumOs,
            ),
          );
    }
    return loose;
  }

  static String _infoPlist({
    required String name,
    required String version,
    required String build,
    required String minimumOs,
  }) {
    String escape(String value) => value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    final identifier = name.replaceAll(RegExp('[^A-Za-z0-9.-]'), '-');
    final entries = {
      'CFBundleDevelopmentRegion': 'en',
      'CFBundleExecutable': name,
      'CFBundleIdentifier': 'io.xcross.$identifier',
      'CFBundleInfoDictionaryVersion': '6.0',
      'CFBundleName': name,
      'CFBundlePackageType': 'FMWK',
      'CFBundleShortVersionString': version,
      'CFBundleVersion': build,
      'MinimumOSVersion': minimumOs,
    };
    final body = StringBuffer();
    for (final MapEntry(:key, :value) in entries.entries) {
      body.writeln('\t<key>$key</key>\n\t<string>${escape(value)}</string>');
    }
    return '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
        '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
        '<plist version="1.0">\n<dict>\n'
        '$body'
        '\t<key>CFBundleSupportedPlatforms</key>\n'
        '\t<array>\n\t\t<string>iPhoneOS</string>\n\t</array>\n'
        '</dict>\n</plist>\n';
  }
}
