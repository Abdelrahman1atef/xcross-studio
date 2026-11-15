import 'package:meta/meta.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:xcross/src/shared/flutter/swiftpm/manifest_dependencies.dart';
import 'package:xcross/src/shared/flutter/swiftpm/manifest_lexer.dart';

/// One staged plugin manifest, as [SwiftPmPinConflicts.find] reads it.
@internal
typedef SwiftPmPluginManifest = ({
  /// Pub package name.
  String plugin,

  /// Its pubspec `version:`, when known.
  String? version,

  /// The text of its `Package.swift`.
  String manifest,
});

/// Two or more plugins whose `Package.swift` files ask for versions of the
/// same remote package that no single version satisfies, such as
/// firebase_messaging 17.0.0 (`exact: "13.0.0"`) and firebase_core 5.1.0
/// (`exact: "13.1.1"`) for firebase-ios-sdk. SwiftPM cannot resolve that
/// graph, and its own error names neither plugin.
@internal
final class SwiftPmPinConflict {
  const SwiftPmPinConflict({
    required this.package,
    required this.requirements,
    required this.upgrade,
  });

  /// The remote package's name, from its URL (`firebase-ios-sdk`).
  final String package;

  /// Every plugin's requirement on [package], lowest first.
  final List<SwiftPmPinRequirement> requirements;

  /// The plugins whose requirement leaves out the newest one asked for: the
  /// ones to upgrade.
  final List<String> upgrade;

  /// `firebase_messaging 17.0.0 pins firebase-ios-sdk 13.0.0; firebase_core
  /// 5.1.0 pins 13.1.1. Run "flutter pub upgrade firebase_messaging" so they
  /// agree.`
  String get message {
    final groups = <String, List<SwiftPmPinRequirement>>{};
    for (final requirement in requirements) {
      groups.putIfAbsent(requirement.display, () => []).add(requirement);
    }
    final clauses = <String>[];
    for (final MapEntry(key: display, value: members) in groups.entries) {
      final names = [
        for (final member in members)
          if (member.version case final version?)
            '${member.plugin} $version'
          else
            member.plugin,
      ];
      final who = names.length == 1
          ? names.single
          : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
      final exact = members.first.exact;
      final verb = switch ((exact, names.length == 1)) {
        (true, true) => 'pins',
        (true, false) => 'pin',
        (false, true) => 'requires',
        (false, false) => 'require',
      };
      final what = clauses.isEmpty ? '$package $display' : display;
      clauses.add('$who $verb $what');
    }
    return '${clauses.join('; ')}. Run "flutter pub upgrade '
        '${upgrade.join(' ')}" so they agree.';
  }
}

/// One plugin's requirement on a remote package.
@internal
final class SwiftPmPinRequirement {
  const SwiftPmPinRequirement({
    required this.plugin,
    required this.version,
    required this.constraint,
    required this.lowest,
    required this.exact,
  });

  final String plugin;
  final String? version;
  final VersionConstraint constraint;

  /// The lowest version [constraint] allows.
  final Version lowest;

  /// An `exact:` pin rather than a range.
  final bool exact;

  String get display => exact ? '$lowest' : '$constraint';
}

@internal
abstract final class SwiftPmPinConflicts {
  /// The first remote package (by name) the [manifests] ask for in versions
  /// that do not overlap, or null when SwiftPM can pick one version of each.
  ///
  /// Requirements it cannot read (`branch:`, `revision:`, computed versions)
  /// are left out rather than guessed.
  static SwiftPmPinConflict? find(Iterable<SwiftPmPluginManifest> manifests) {
    final byPackage = <String, ({String name, List<SwiftPmPinRequirement> all})>{};
    for (final (:plugin, :version, :manifest) in manifests) {
      final constants = SwiftPmManifestLexer.manifestStringConstants(manifest);
      for (final dependency in SwiftPmManifestDependencies.parseUrlPackageDeps(
        manifest,
      )) {
        final parsed = requirement(dependency.match, constants);
        if (parsed == null) continue;
        final name = SwiftPmManifestDependencies.packageIdentityFromUrl(
          dependency.url,
        );
        final entry = byPackage.putIfAbsent(
          name.toLowerCase(),
          () => (name: name, all: []),
        );
        if (entry.all.any((existing) => existing.plugin == plugin)) continue;
        entry.all.add(
          SwiftPmPinRequirement(
            plugin: plugin,
            version: version,
            constraint: parsed.constraint,
            lowest: parsed.lowest,
            exact: parsed.exact,
          ),
        );
      }
    }
    for (final key in byPackage.keys.toList()..sort()) {
      final (:name, :all) = byPackage[key]!;
      if (all.length < 2) continue;
      final common = all.fold<VersionConstraint>(
        VersionConstraint.any,
        (shared, requirement) => shared.intersect(requirement.constraint),
      );
      if (!common.isEmpty) continue;
      final newest = all
          .map((requirement) => requirement.lowest)
          .reduce((a, b) => a > b ? a : b);
      final upgrade = [
        for (final requirement in all)
          if (!requirement.constraint.allows(newest)) requirement.plugin,
      ]..sort();
      final ordered = [...all]
        ..sort((a, b) {
          final byVersion = a.lowest.compareTo(b.lowest);
          return byVersion != 0 ? byVersion : a.plugin.compareTo(b.plugin);
        });
      return SwiftPmPinConflict(
        package: name,
        requirements: ordered,
        upgrade: upgrade,
      );
    }
    return null;
  }

  /// The version requirement of one `.package(url: …, <requirement>)` call:
  /// `exact:`/`.exact()`, `from:`/`.upToNextMajor(from:)`,
  /// `.upToNextMinor(from:)`, `"a"..<"b"` or `"a"..."b"`. Versions are string
  /// literals or `let` string constants from the same manifest ([constants]).
  static ({VersionConstraint constraint, Version lowest, bool exact})?
  requirement(String call, Map<String, String> constants) {
    const value = r'("[^"]*"|[A-Za-z_]\w*)';
    Version? read(String? token) {
      if (token == null) return null;
      final text = token.startsWith('"')
          ? token.substring(1, token.length - 1)
          : constants[token];
      return text == null ? null : _version(text);
    }

    if (RegExp('(?:exact:|\\.exact\\()\\s*$value').firstMatch(call)
        case final match?) {
      final version = read(match[1]);
      return version == null
          ? null
          : (constraint: version, lowest: version, exact: true);
    }
    if (RegExp('\\.upToNextMinor\\(\\s*from:\\s*$value').firstMatch(call)
        case final match?) {
      final version = read(match[1]);
      return version == null
          ? null
          : (
              constraint: VersionRange(
                min: version,
                max: version.nextMinor,
                includeMin: true,
              ),
              lowest: version,
              exact: false,
            );
    }
    if (RegExp('from:\\s*$value').firstMatch(call) case final match?) {
      final version = read(match[1]);
      return version == null
          ? null
          : (
              constraint: VersionRange(
                min: version,
                max: version.nextMajor,
                includeMin: true,
              ),
              lowest: version,
              exact: false,
            );
    }
    if (RegExp('$value\\s*(\\.\\.<|\\.\\.\\.)\\s*$value').firstMatch(call)
        case final match?) {
      final low = read(match[1]);
      final high = read(match[3]);
      if (low == null || high == null) return null;
      return (
        constraint: VersionRange(
          min: low,
          max: high,
          includeMin: true,
          includeMax: match[2] == '...',
        ),
        lowest: low,
        exact: false,
      );
    }
    return null;
  }

  /// A SwiftPM version (`13`, `13.1`, `13.1.1`, `13.1.1-beta`), padded to
  /// three numbers.
  static Version? _version(String text) {
    final match = RegExp(r'^(\d+)(?:\.(\d+))?(?:\.(\d+))?([-+].*)?$')
        .firstMatch(text.trim());
    if (match == null) return null;
    try {
      return Version.parse(
        '${match[1]}.${match[2] ?? '0'}.${match[3] ?? '0'}${match[4] ?? ''}',
      );
    } on FormatException {
      return null;
    }
  }
}
