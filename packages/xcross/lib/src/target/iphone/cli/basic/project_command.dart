// studio: 016 — `xcross project bundle-id [original|prefixed] [--json]`:
// which App ID the project is signed under (specs/016-push-firebase-maps).
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
