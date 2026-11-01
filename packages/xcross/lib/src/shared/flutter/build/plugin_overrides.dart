// studio: 006 — user-supplied Package.swift overrides for Flutter plugins
// (specs/006-plugin-overrides).
import 'dart:io';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:xcross/src/shared/diagnostics/build_warnings.dart';
import 'package:xcross/src/shared/diagnostics/xcross_diagnostics.dart';
import 'package:xcross/src/shared/flutter/build/ios_plugins.dart';
import 'package:yaml/yaml.dart';

/// Where an override folder was found.
@internal
enum PluginOverrideScope { project, user }

/// An override folder that applies to a plugin: a `Package.swift` plus any
/// extra files (sources, module maps, resources) laid over the plugin's own
/// Swift package.
@internal
final class PluginOverride {
  const PluginOverride({
    required this.directory,
    required this.scope,
    required this.versionSpecific,
  });

  final String directory;
  final PluginOverrideScope scope;

  /// Found in a `<plugin>/<version>/` folder (not the any-version one).
  final bool versionSpecific;
}

/// A candidate folder that was found but not used.
@internal
final class PluginOverrideProblem {
  const PluginOverrideProblem(
    this.directory,
    this.reason, {
    required this.versionMismatch,
  });

  final String directory;
  final String reason;

  /// The folder is fine but is meant for other plugin versions.
  final bool versionMismatch;
}

/// The result of looking up a plugin's override.
@internal
final class PluginOverrideLookup {
  const PluginOverrideLookup(this.override, this.problems);

  /// The override to apply, or null when none applies.
  final PluginOverride? override;

  /// Candidates that were skipped, in search order.
  final List<PluginOverrideProblem> problems;
}

/// Finds override folders, in this order (the first that applies wins):
/// `<project>/xcross_overrides/<plugin>/<version>/`,
/// `<project>/xcross_overrides/<plugin>/`,
/// `~/.xcross/overrides/<plugin>/<version>/`, `~/.xcross/overrides/<plugin>/`.
///
/// An any-version folder may hold an `override.yaml` with
/// `versions: ">=1.2.0 <2.0.0"` (a pub-style constraint).
@internal
final class PluginOverrideLocator {
  PluginOverrideLocator({
    required this.fileSystem,
    required this.paths,
    required this.projectRoot,
    Map<String, String> environment = const {},
  }) : home = environment['HOME'] ?? environment['USERPROFILE'];

  final HostFileSystemInterface fileSystem;
  final p.Context paths;
  final String projectRoot;
  final String? home;

  static const projectFolder = 'xcross_overrides';
  static const manifestName = 'Package.swift';
  static const settingsName = 'override.yaml';

  /// The override roots in search order.
  List<(String, PluginOverrideScope)> get roots => [
    (paths.join(projectRoot, projectFolder), PluginOverrideScope.project),
    if (home case final home? when home.isNotEmpty)
      (paths.join(home, '.xcross', 'overrides'), PluginOverrideScope.user),
  ];

  /// The override for [plugin] at [version] (`null` when the plugin's
  /// pubspec has no version: only any-version folders without a `versions`
  /// constraint apply then).
  PluginOverrideLookup find(String plugin, String? version) {
    final problems = <PluginOverrideProblem>[];
    for (final (root, scope) in roots) {
      final base = paths.join(root, plugin);
      if (!fileSystem.directory(base).existsSync()) continue;

      if (version != null) {
        final exact = paths.join(base, version);
        if (fileSystem.directory(exact).existsSync()) {
          if (!_hasManifest(exact)) {
            problems.add(
              PluginOverrideProblem(
                exact,
                'has no $manifestName',
                versionMismatch: false,
              ),
            );
          } else {
            return PluginOverrideLookup(
              PluginOverride(
                directory: exact,
                scope: scope,
                versionSpecific: true,
              ),
              problems,
            );
          }
        }
      }

      if (_hasManifest(base)) {
        final problem = _constraintProblem(base, version);
        if (problem == null) {
          return PluginOverrideLookup(
            PluginOverride(
              directory: base,
              scope: scope,
              versionSpecific: false,
            ),
            problems,
          );
        }
        problems.add(problem);
        continue;
      }

      final versions = versionFolders(base);
      if (versions.isNotEmpty) {
        if (version == null || !versions.contains(version)) {
          problems.add(
            PluginOverrideProblem(
              base,
              'has overrides for ${versions.join(', ')} but the plugin is '
              '${version ?? 'unversioned'}',
              versionMismatch: true,
            ),
          );
        }
      } else {
        problems.add(
          PluginOverrideProblem(
            base,
            'has no $manifestName',
            versionMismatch: false,
          ),
        );
      }
    }
    return PluginOverrideLookup(null, problems);
  }

  /// Names of the version folders (`1.2.3`) directly under [base], sorted.
  List<String> versionFolders(String base) {
    final directory = fileSystem.directory(base);
    if (!directory.existsSync()) return const [];
    return [
      for (final entity in directory.listSync(followLinks: false))
        if (entity is Directory &&
            OverrideVersion.tryParse(paths.basename(entity.path)) != null)
          paths.basename(entity.path),
    ]..sort();
  }

  bool _hasManifest(String directory) =>
      fileSystem.file(paths.join(directory, manifestName)).existsSync();

  /// Why the any-version folder [base] does not apply, or null when it does.
  PluginOverrideProblem? _constraintProblem(String base, String? version) {
    final settings = fileSystem.file(paths.join(base, settingsName));
    if (!settings.existsSync()) return null;
    final Object? yaml;
    try {
      yaml = loadYaml(settings.readAsStringSync());
    } on Object catch (error) {
      return PluginOverrideProblem(
        base,
        '$settingsName is not valid YAML ($error)',
        versionMismatch: false,
      );
    }
    if (yaml == null) return null;
    if (yaml is! Map) {
      return PluginOverrideProblem(
        base,
        '$settingsName must be a map',
        versionMismatch: false,
      );
    }
    final raw = yaml['versions'];
    if (raw == null) return null;
    final constraint = raw is String
        ? OverrideVersionConstraint.tryParse(raw)
        : null;
    if (constraint == null) {
      return PluginOverrideProblem(
        base,
        '$settingsName versions "$raw" is not a version constraint',
        versionMismatch: false,
      );
    }
    final parsed = version == null ? null : OverrideVersion.tryParse(version);
    if (parsed == null || !constraint.allows(parsed)) {
      return PluginOverrideProblem(
        base,
        'is for versions "$raw" but the plugin is '
        '${version ?? 'unversioned'}',
        versionMismatch: true,
      );
    }
    return null;
  }
}

/// Applies overrides to discovered plugins.
@internal
final class PluginOverrides {
  PluginOverrides({required this.locator, required this.warnings});

  final PluginOverrideLocator locator;
  final BuildWarnings warnings;

  HostFileSystemInterface get _fileSystem => locator.fileSystem;
  p.Context get _paths => locator.paths;

  /// The `version:` in the plugin's `pubspec.yaml`, if any.
  static String? versionOf(IosPlugin plugin, p.Context paths) {
    final file = plugin.fileSystem.file(
      paths.join(plugin.packageRoot, 'pubspec.yaml'),
    );
    if (!file.existsSync()) return null;
    try {
      final yaml = loadYaml(file.readAsStringSync());
      if (yaml is Map && yaml['version'] != null) {
        return '${yaml['version']}'.trim();
      }
    } on Object {
      return null;
    }
    return null;
  }

  /// [plugins] with every overridden plugin re-rooted at a staged package
  /// under [stagingRoot] (`<stagingRoot>/<plugin>`). Skipped candidates are
  /// reported as warnings; a plugin with no applicable override is returned
  /// unchanged.
  List<IosPlugin> apply(
    List<IosPlugin> plugins, {
    required String stagingRoot,
  }) {
    return [
      for (final plugin in plugins) _apply(plugin, stagingRoot: stagingRoot),
    ];
  }

  IosPlugin _apply(IosPlugin plugin, {required String stagingRoot}) {
    final lookup = locator.find(plugin.name, versionOf(plugin, _paths));
    for (final problem in lookup.problems) {
      warnings.warn(
        XcrossCodes.buildPluginOverrideInvalid,
        subject: problem.directory,
        message:
            'Override folder ${problem.directory} for plugin '
            '"${plugin.name}" ${problem.reason}; it is not used.',
        hint: problem.versionMismatch
            ? 'Add a folder named after the plugin version, or widen '
                  'versions: in override.yaml.'
            : null,
      );
    }
    final override = lookup.override;
    if (override == null) return plugin;
    final IosPlugin staged;
    try {
      staged = materialize(
        plugin,
        override,
        _paths.join(stagingRoot, plugin.name),
      );
    } on FileSystemException catch (error) {
      warnings.warn(
        XcrossCodes.buildPluginOverrideInvalid,
        subject: override.directory,
        message:
            'Override folder ${override.directory} for plugin '
            '"${plugin.name}" could not be staged (${error.message}); it is '
            'not used.',
      );
      return plugin;
    }
    warnings.warn(
      XcrossCodes.buildPluginOverrideApplied,
      subject: plugin.name,
      message:
          'Plugin "${plugin.name}" is built with the Package.swift from '
          '${override.directory}'
          '${plugin.usesSwiftPackageManager ? ' instead of its own' : ''}.',
    );
    return staged;
  }

  /// Writes the staged package root [destination] (only files whose content
  /// changed, so SwiftPM's incremental state stays warm) and returns the
  /// plugin re-rooted there:
  ///
  /// - `pubspec.yaml` from the plugin (for its `pluginClass`);
  /// - `<platformDir>/<name>/`: the plugin's own Swift package directory when
  ///   it has one, else the contents of its `<platformDir>/` folder
  ///   (`Classes/`, `Assets/`, … without the podspec), with the override's
  ///   files on top.
  IosPlugin materialize(
    IosPlugin plugin,
    PluginOverride override,
    String destination,
  ) {
    final packageDir = _paths.join(plugin.platformDirectoryName, plugin.name);
    final planned = <String, String>{};
    final pubspec = _paths.join(plugin.packageRoot, 'pubspec.yaml');
    if (_fileSystem.file(pubspec).existsSync()) {
      planned['pubspec.yaml'] = pubspec;
    }
    if (_fileSystem.directory(plugin.swiftPackageDir).existsSync()) {
      _plan(planned, plugin.swiftPackageDir, packageDir);
    } else {
      _plan(
        planned,
        _paths.join(plugin.packageRoot, plugin.platformDirectoryName),
        packageDir,
        skipTopLevel: (entity) =>
            entity is File &&
            _paths.basename(entity.path).toLowerCase().endsWith('.podspec'),
      );
    }
    _plan(
      planned,
      override.directory,
      packageDir,
      skipTopLevel: (entity) {
        final name = _paths.basename(entity.path);
        return name == PluginOverrideLocator.settingsName ||
            (entity is Directory &&
                !override.versionSpecific &&
                OverrideVersion.tryParse(name) != null);
      },
    );
    _sync(planned, destination);
    return IosPlugin(
      name: plugin.name,
      fileSystem: plugin.fileSystem,
      packageRoot: destination,
      sharedDarwinSource: plugin.sharedDarwinSource,
    );
  }

  /// Adds every file under [source] to [planned] as
  /// `<prefix>/<relative path>` → source path (later entries win).
  void _plan(
    Map<String, String> planned,
    String source,
    String prefix, {
    bool Function(FileSystemEntity entity)? skipTopLevel,
  }) {
    final root = _fileSystem.directory(source);
    if (!root.existsSync()) return;
    for (final entity in root.listSync(followLinks: false)) {
      final name = _paths.basename(entity.path);
      final isDirectory = entity is Directory;
      if (skipTopLevel?.call(entity) ?? false) continue;
      if (entity is File) {
        planned[_paths.join(prefix, name)] = entity.path;
      } else if (isDirectory) {
        for (final nested
            in _fileSystem
                .directory(entity.path)
                .listSync(recursive: true, followLinks: false)) {
          if (nested is! File) continue;
          final relative = _paths.relative(nested.path, from: source);
          planned[_paths.join(prefix, relative)] = nested.path;
        }
      }
    }
  }

  void _sync(Map<String, String> planned, String destination) {
    for (final MapEntry(key: relative, value: source) in planned.entries) {
      final bytes = _fileSystem.file(source).readAsBytesSync();
      final target = _fileSystem.file(_paths.join(destination, relative));
      if (target.existsSync() && _same(target.readAsBytesSync(), bytes)) {
        continue;
      }
      target.parent.createSync(recursive: true);
      target.writeAsBytesSync(bytes, flush: true);
    }
    final root = _fileSystem.directory(destination);
    if (!root.existsSync()) return;
    final wanted = {
      for (final relative in planned.keys)
        _paths.normalize(_paths.join(destination, relative)),
    };
    final directories = <String>[];
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is Directory) {
        directories.add(entity.path);
      } else if (!wanted.contains(_paths.normalize(entity.path))) {
        entity.deleteSync();
      }
    }
    // Deepest first, so emptied parents go too. An empty target folder would
    // make SwiftPM fail with "target has no sources".
    directories.sort((a, b) => b.length.compareTo(a.length));
    for (final path in directories) {
      final directory = _fileSystem.directory(path);
      if (directory.listSync().isEmpty) directory.deleteSync();
    }
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A semantic version as used by pub (`1.2.3`, `1.2.3-dev.1`, `1.2.3+4`).
@internal
final class OverrideVersion implements Comparable<OverrideVersion> {
  const OverrideVersion(this.major, this.minor, this.patch, [this.pre = '']);

  final int major;
  final int minor;
  final int patch;

  /// The pre-release part without the `-`; empty for a release.
  final String pre;

  static final _pattern = RegExp(
    r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
  );

  static OverrideVersion? tryParse(String text) {
    final match = _pattern.firstMatch(text.trim());
    if (match == null) return null;
    return OverrideVersion(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      match[4] ?? '',
    );
  }

  @override
  int compareTo(OverrideVersion other) {
    for (final (a, b) in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      if (a != b) return a.compareTo(b);
    }
    if (pre == other.pre) return 0;
    if (pre.isEmpty) return 1;
    if (other.pre.isEmpty) return -1;
    final left = pre.split('.');
    final right = other.pre.split('.');
    for (var i = 0; i < left.length && i < right.length; i++) {
      final l = int.tryParse(left[i]);
      final r = int.tryParse(right[i]);
      final order = l != null && r != null
          ? l.compareTo(r)
          : l != null
          ? -1
          : r != null
          ? 1
          : left[i].compareTo(right[i]);
      if (order != 0) return order;
    }
    return left.length.compareTo(right.length);
  }

  @override
  String toString() => '$major.$minor.$patch${pre.isEmpty ? '' : '-$pre'}';
}

/// A pub-style version constraint: `any`, `1.2.3`, `^1.2.3`, or
/// space-separated `>=`, `>`, `<=`, `<` comparisons that must all hold.
@internal
final class OverrideVersionConstraint {
  const OverrideVersionConstraint._(this._checks);

  final List<bool Function(OverrideVersion)> _checks;

  static final _comparison = RegExp(r'^(>=|<=|>|<|=)?(.+)$');

  static OverrideVersionConstraint? tryParse(String text) {
    final parts = text.trim().split(RegExp(r'\s+'));
    if (parts.length == 1 && parts.single == 'any') {
      return const OverrideVersionConstraint._([]);
    }
    final checks = <bool Function(OverrideVersion)>[];
    for (final part in parts) {
      if (part.startsWith('^')) {
        final low = OverrideVersion.tryParse(part.substring(1));
        if (low == null) return null;
        final high = low.major > 0
            ? OverrideVersion(low.major + 1, 0, 0)
            : low.minor > 0
            ? OverrideVersion(0, low.minor + 1, 0)
            : OverrideVersion(0, 0, low.patch + 1);
        checks
          ..add((v) => v.compareTo(low) >= 0)
          ..add((v) => v.compareTo(high) < 0);
        continue;
      }
      final match = _comparison.firstMatch(part);
      final version = match == null
          ? null
          : OverrideVersion.tryParse(match[2]!);
      if (version == null) return null;
      checks.add(switch (match![1]) {
        '>=' => (v) => v.compareTo(version) >= 0,
        '>' => (v) => v.compareTo(version) > 0,
        '<=' => (v) => v.compareTo(version) <= 0,
        '<' => (v) => v.compareTo(version) < 0,
        _ => (v) => v.compareTo(version) == 0,
      });
    }
    return OverrideVersionConstraint._(checks);
  }

  bool allows(OverrideVersion version) =>
      _checks.every((check) => check(version));
}
