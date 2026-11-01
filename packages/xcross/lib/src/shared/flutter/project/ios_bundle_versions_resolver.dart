import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:xcross/src/shared/flutter/build/ios_bundle_versions.dart';
import 'package:xcross/src/shared/flutter/project/pbx_project_reader.dart';

@internal
final class IosBundleVersionsResolver {
  IosBundleVersionsResolver(this.fileSystem, this.projects);

  final HostFileSystemInterface fileSystem;
  final PbxProjectReader projects;

  /// Resolve the application target's versions from `project.pbxproj`.
  ///
  /// Xcode expands `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` from
  /// the *application* target's build settings, so those are read here rather
  /// than taking whichever value appears first in the file (which, in a
  /// project with extensions, is usually an extension's).
  ///
  /// studio: 002 — each value is the first usable one of: the CLI flag, the
  /// pubspec `version`, the xcconfig value, the project file value, the
  /// default; the chosen source is recorded.
  IosBundleVersions resolve(
    String projectRoot, {
    String? buildName,
    String? buildNumber,
    String? pubspecBuildName,
    String? pubspecBuildNumber,
    String? xcconfigBuildName,
    String? xcconfigBuildNumber,
  }) {
    final settings = _applicationBuildSettings(projectRoot);
    return decide(
      buildName: buildName,
      buildNumber: buildNumber,
      pubspecBuildName: pubspecBuildName,
      pubspecBuildNumber: pubspecBuildNumber,
      xcconfigBuildName: xcconfigBuildName,
      xcconfigBuildNumber: xcconfigBuildNumber,
      projectBuildName: _setting(settings, 'MARKETING_VERSION'),
      projectBuildNumber: _setting(settings, 'CURRENT_PROJECT_VERSION'),
    );
  }

  /// The precedence itself, independent of any file: flag > pubspec >
  /// xcconfig > project file > default, separately for name and number.
  @visibleForTesting
  static IosBundleVersions decide({
    String? buildName,
    String? buildNumber,
    String? pubspecBuildName,
    String? pubspecBuildNumber,
    String? xcconfigBuildName,
    String? xcconfigBuildNumber,
    String? projectBuildName,
    String? projectBuildNumber,
  }) {
    final (shortVersion, shortSource) = _first([
      (_clean(buildName), VersionSource.flag),
      (_clean(pubspecBuildName), VersionSource.pubspec),
      (_clean(xcconfigBuildName), VersionSource.xcconfig),
      (_clean(projectBuildName), VersionSource.projectFile),
      (IosBundleVersions.fallback.shortVersion, VersionSource.fallback),
    ]);
    final (bundleVersion, bundleSource) = _first([
      (_clean(buildNumber), VersionSource.flag),
      (_clean(pubspecBuildNumber), VersionSource.pubspec),
      (_clean(xcconfigBuildNumber), VersionSource.xcconfig),
      (_clean(projectBuildNumber), VersionSource.projectFile),
      (IosBundleVersions.fallback.bundleVersion, VersionSource.fallback),
    ]);
    return IosBundleVersions(
      shortVersion: shortVersion,
      bundleVersion: bundleVersion,
      shortVersionSource: shortSource,
      bundleVersionSource: bundleSource,
    );
  }

  static (String, VersionSource) _first(
    List<(String?, VersionSource)> candidates,
  ) {
    for (final (value, source) in candidates) {
      if (value != null) return (value, source);
    }
    throw StateError('the fallback candidate is always present');
  }

  /// A usable version value: non-empty and without an unresolved `$(VAR)`.
  static String? _clean(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed.contains(r'$')) {
      return null;
    }
    return trimmed;
  }

  Map<String, Object?> _applicationBuildSettings(String projectRoot) {
    final pbxprojPath = projects.findPbxproj(projectRoot);
    if (pbxprojPath == null) return const {};
    final project = projects.parseFile(pbxprojPath);
    if (project == null) return const {};

    Map<String, Object?>? fallbackSettings;
    for (final target in project.nativeTargets) {
      if (target.string('productType') !=
          'com.apple.product-type.application') {
        continue;
      }
      final settings = project.buildSettings(target);
      if (target.string('name') == 'Runner') return settings;
      fallbackSettings ??= settings;
    }
    return fallbackSettings ?? const {};
  }

  static String? _setting(Map<String, Object?> settings, String key) {
    final value = settings[key];
    if (value is! String) return null;
    final trimmed = value.trim();
    // An unresolved $(VAR) is worse than the documented default.
    if (trimmed.isEmpty || trimmed.contains(r'$')) return null;
    return trimmed;
  }

  /// Read `CFBundleShortVersionString`/`CFBundleVersion` straight out of a
  /// built `Info.plist`, used to make an extension match its host exactly.
  IosBundleVersions? fromBuiltPlist(String plistPath) {
    final file = fileSystem.file(plistPath);
    if (!file.existsSync()) return null;
    final xml = file.readAsStringSync();

    final short = _plistString(xml, 'CFBundleShortVersionString');
    final bundle = _plistString(xml, 'CFBundleVersion');
    if (short == null || bundle == null) return null;
    return IosBundleVersions(shortVersion: short, bundleVersion: bundle);
  }

  static String? _plistString(String xml, String key) {
    final match = RegExp(
      '<key>${RegExp.escape(key)}</key>\\s*<string>([^<]*)</string>',
    ).firstMatch(xml);
    final value = match?.group(1)?.trim();
    if (value == null || value.isEmpty || value.contains(r'$')) return null;
    return value;
  }
}
