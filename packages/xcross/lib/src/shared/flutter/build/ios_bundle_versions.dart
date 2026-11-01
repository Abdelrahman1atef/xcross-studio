import 'package:meta/meta.dart';

/// The version pair every bundle in an app must agree on.
///
/// iOS requires an embedded app extension's `CFBundleShortVersionString` and
/// `CFBundleVersion` to match its host app's; installd rejects a mismatched
/// pair, and a stale extension version silently breaks upgrades.
@internal
@immutable
final class IosBundleVersions {
  const IosBundleVersions({
    required this.shortVersion,
    required this.bundleVersion,
    // studio: 002 — where each value came from (reported in the build log).
    this.shortVersionSource = VersionSource.fallback,
    this.bundleVersionSource = VersionSource.fallback,
  });

  /// Fallbacks matching Flutter's own defaults.
  static const fallback = IosBundleVersions(
    shortVersion: '1.0.0',
    bundleVersion: '1',
  );

  /// `CFBundleShortVersionString`, from `MARKETING_VERSION`.
  final String shortVersion;

  /// `CFBundleVersion`, from `CURRENT_PROJECT_VERSION`.
  final String bundleVersion;

  final VersionSource shortVersionSource;
  final VersionSource bundleVersionSource;

  /// `1.0.7 (7) · name: pubspec.yaml · number: pubspec.yaml` (logged after
  /// a `Version` label).
  String describe() =>
      '$shortVersion ($bundleVersion) · name: '
      '${shortVersionSource.nameLabel} · number: '
      '${bundleVersionSource.numberLabel}';

  @override
  String toString() => '$shortVersion ($bundleVersion)';
}

// studio: 002 — version precedence: flag > pubspec > xcconfig > project file.
/// Where a bundle version value came from.
@internal
enum VersionSource {
  flag('--build-name', '--build-number'),
  pubspec('pubspec.yaml', 'pubspec.yaml'),
  xcconfig('xcconfig', 'xcconfig'),
  projectFile('project.pbxproj', 'project.pbxproj'),
  fallback('default', 'default');

  const VersionSource(this.nameLabel, this.numberLabel);

  final String nameLabel;
  final String numberLabel;
}
