// studio: 016 — `xcross project bundle-id [original|prefixed] [--json]`:
// which App ID the project is signed under (specs/016-push-firebase-maps).
// studio: 022 — `xcross project version`: the pubspec version and build
// number, shown, set or bumped from the Release page.
@internal
library;

import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:xcross/src/shared/config/project_settings.dart';
import 'package:xcross/src/shared/errors/errors.dart';
import 'package:xcross/src/shared/flutter/build/ios_bundle_id.dart';
import 'package:xcross/src/shared/flutter/project/pbx_project_reader.dart';
import 'package:xcross/src/shared/flutter/project/pubspec_version.dart';
import 'package:xcross/src/target/iphone/device/internal/bundle_identity_resolver.dart';

/// `xcross project …`: settings committed with the project.
@internal
final class ProjectCommand extends Command<void> {
  ProjectCommand({
    required HostFileSystemInterface fileSystem,
    required p.Context paths,
    required String Function() projectRoot,
    required Map<String, String> environment,
    required void Function(String text) write,
  }) {
    addSubcommand(
      ProjectBundleIdCommand(
        fileSystem: fileSystem,
        paths: paths,
        projectRoot: projectRoot,
        environment: environment,
        write: write,
      ),
    );
    addSubcommand(
      ProjectVersionCommand(
        fileSystem: fileSystem,
        paths: paths,
        projectRoot: projectRoot,
        write: write,
      ),
    );
  }

  @override
  String get name => 'project';

  @override
  String get description => 'Show or change settings saved with the project.';
}

/// What `xcross project bundle-id` reports.
@internal
@immutable
final class BundleIdStatus {
  const BundleIdStatus({
    required this.bundleId,
    required this.saved,
    required this.override,
    required this.settingsPath,
  });

  final String? bundleId;
  final BundleIdMode? saved;
  final BundleIdMode? override;

  /// The file the choice is read from and written to.
  final String settingsPath;

  /// What the next build uses: the override, the saved choice, or the real
  /// App ID (the default since feature 016).
  BundleIdMode get next => override ?? saved ?? BundleIdMode.original;

  Map<String, Object?> toJson() => {
    'v': 1,
    'type': 'bundle_id',
    'bundleId': bundleId,
    'saved': saved?.name,
    'override': override?.name,
    'settingsPath': settingsPath,
    'next': next.name,
  };
}

/// `xcross project bundle-id [original|prefixed] [--json]`.
@internal
final class ProjectBundleIdCommand extends Command<void> {
  ProjectBundleIdCommand({
    required this.fileSystem,
    required this.paths,
    required this.projectRoot,
    required this.environment,
    required this.write,
  }) {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print one JSON object instead of text.',
    );
  }

  final HostFileSystemInterface fileSystem;
  final p.Context paths;
  final String Function() projectRoot;
  final Map<String, String> environment;
  final void Function(String text) write;

  @override
  String get name => 'bundle-id';

  @override
  String get description =>
      'Show or save the App ID the app is signed under: original (the bundle '
      'ID in the project, needed for push, Firebase and the App Store) or '
      'prefixed (XCR-<identity>.<bundle ID>).';

  @override
  String get invocation => 'xcross project bundle-id [original|prefixed]';

  @override
  Future<void> run() async {
    final results = argResults!;
    final rest = results.rest;
    if (rest.length > 1) usageException('Pass at most one value.');
    final root = projectRoot();
    final settings = ProjectSettings(fileSystem: fileSystem, projectRoot: root);
    if (!_isProject(root)) {
      throw XcrossError(
        'No project here: run `xcross project bundle-id` in the folder that '
        'holds pubspec.yaml or the iOS project.',
      );
    }
    if (rest.length == 1) {
      final mode = BundleIdMode.tryParse(rest.single);
      if (mode == null) {
        usageException(
          'The App ID mode must be "original" or "prefixed", not '
          '"${rest.single}".',
        );
      }
      await settings.write(BundleIdentityResolver.settingKey, mode.name);
    }
    final status = read(root, settings);
    if (results.flag('json')) {
      write('${jsonEncode(status.toJson())}\n');
      return;
    }
    final shownPath = paths.relative(status.settingsPath, from: root);
    if (rest.length == 1) {
      write(
        'Saved ${BundleIdentityResolver.settingKey}: ${status.saved!.name} '
        '($shownPath)\n',
      );
    }
    final id = status.bundleId ?? '(not found in the iOS project)';
    write('Bundle ID      $id\n');
    write(
      'Saved choice   ${status.saved == null ? 'not saved' : '${status.saved!.name} ($shownPath)'}\n',
    );
    if (status.override case final override?) {
      write(
        'Override       ${BundleIdentityResolver.modeVariable}='
        '${override.name}\n',
      );
    }
    write(switch (status.next) {
      BundleIdMode.original =>
        'Next build     the real App ID $id'
            '${status.override == null && status.saved == null ? ' (default; a prefixed App ID the team already has is kept)' : ''}\n',
      BundleIdMode.prefixed =>
        'Next build     the prefixed App ID XCR-<identity>.$id (push, '
            'Firebase and Sign in with Apple do not work under it)\n',
    });
  }

  bool _isProject(String root) =>
      fileSystem
          .file(paths.join(root, ProjectSettings.pubspecFileName))
          .existsSync() ||
      fileSystem
          .file(paths.join(root, ProjectSettings.projectFileName))
          .existsSync() ||
      fileSystem.directory(paths.join(root, 'ios')).existsSync();

  /// The project's bundle ID and App ID choices.
  BundleIdStatus read(String root, ProjectSettings settings) {
    String? bundleId;
    try {
      bundleId = IosBundleId(
        fileSystem,
        paths,
        PbxProjectReader(fileSystem, paths),
      ).resolve(root);
    } on Object {
      bundleId = null;
    }
    final rawOverride = environment[BundleIdentityResolver.modeVariable];
    final override = rawOverride == null || rawOverride.trim().isEmpty
        ? null
        : BundleIdMode.tryParse(rawOverride) ??
              (throw XcrossError(
                '${BundleIdentityResolver.modeVariable} must be "original" or '
                '"prefixed", not "${rawOverride.trim()}".',
              ));
    final rawSaved = settings.read(BundleIdentityResolver.settingKey);
    final saved = rawSaved == null
        ? null
        : BundleIdMode.tryParse(rawSaved) ??
              (throw XcrossError(
                '${settings.path}: ${BundleIdentityResolver.settingKey} must '
                'be "original" or "prefixed", not "${rawSaved.trim()}".',
              ));
    return BundleIdStatus(
      bundleId: bundleId,
      saved: saved,
      override: override,
      settingsPath: settings.path,
    );
  }
}

/// `xcross project version [<x.y.z>[+<n>]] [--build <n>]
/// [--bump major|minor|patch|build] [--json]`.
@internal
final class ProjectVersionCommand extends Command<void> {
  ProjectVersionCommand({
    required this.fileSystem,
    required this.paths,
    required this.projectRoot,
    required this.write,
  }) {
    argParser
      ..addOption(
        'build',
        valueHelp: 'n',
        help: 'Set the build number (CFBundleVersion).',
      )
      ..addOption(
        'bump',
        allowed: [for (final part in VersionPart.values) part.name],
        help:
            'Raise one part by one. A new major, minor or patch version also '
            'raises the build number.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print one JSON object instead of text.',
      );
  }

  final HostFileSystemInterface fileSystem;
  final p.Context paths;
  final String Function() projectRoot;
  final void Function(String text) write;

  @override
  String get name => 'version';

  @override
  String get description =>
      "Show or change the app's version and build number (the version: line "
      'of pubspec.yaml).';

  @override
  String get invocation =>
      'xcross project version [<x.y.z>[+<n>]] [--build <n>] '
      '[--bump major|minor|patch|build]';

  @override
  Future<void> run() async {
    final results = argResults!;
    final rest = results.rest;
    final buildText = results.option('build');
    final bump = results.option('bump');
    if (rest.length > 1) usageException('Pass at most one version.');
    if (bump != null && (rest.isNotEmpty || buildText != null)) {
      usageException('Pass --bump alone, or a version and --build.');
    }
    // Reported as joined: the file system may add a long-path prefix.
    final pubspecPath = paths.join(
      projectRoot(),
      ProjectSettings.pubspecFileName,
    );
    final pubspec = fileSystem.file(pubspecPath);
    if (!pubspec.existsSync()) {
      throw XcrossError(
        'No pubspec.yaml here: run `xcross project version` in the Flutter '
        'project.',
      );
    }
    final text = pubspec.readAsStringSync();
    final current = PubspecVersion.read(text);

    PubspecVersion? next;
    if (bump != null) {
      next = (current ?? const PubspecVersion('1.0.0', 0)).bump(
        VersionPart.values.byName(bump),
      );
    } else if (rest.isNotEmpty || buildText != null) {
      var name = current?.name ?? '1.0.0';
      var build = current?.build;
      if (rest.isNotEmpty) {
        final given = PubspecVersion.parse(rest.single);
        if (given == null) {
          usageException(
            'The version must be up to three numbers (1.2.3), optionally '
            'with +<build>, not "${rest.single}".',
          );
        }
        name = given.name;
        build = given.build ?? build;
      }
      if (buildText != null) {
        final number = int.tryParse(buildText.trim());
        if (number == null || number < 1) {
          usageException(
            'The build number must be a whole number of 1 or more, not '
            '"$buildText".',
          );
        }
        build = number;
      }
      next = PubspecVersion(name, build);
    }

    final changed = next != null && next.text != current?.text;
    if (changed) {
      pubspec.writeAsStringSync(PubspecVersion.write(text, next));
    }
    final shown = next ?? current;
    if (results.flag('json')) {
      final json = jsonEncode({
        'v': 1,
        'type': 'project_version',
        'version': shown?.name,
        'build': shown?.build,
        'previous': changed ? current?.text : null,
        'changed': changed,
        'pubspec': pubspecPath,
      });
      write('$json\n');
      return;
    }
    if (shown == null) {
      write(
        'pubspec.yaml has no version: line. Set one with '
        '`xcross project version 1.0.0+1`.\n',
      );
      return;
    }
    write('Version  ${shown.name}\n');
    write('Build    ${shown.build ?? '(none: iOS uses 1)'}\n');
    if (changed) {
      write(
        'Saved in pubspec.yaml (was '
        '${current == null ? 'not set' : current.text}).\n',
      );
    }
  }
}
