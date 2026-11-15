// studio: privacy — `xcross privacy init`: the app's own privacy manifest,
// written and added to the Runner target in one step, so a developer without
// Xcode can clear `release.privacy_manifest_missing` (and a GUI can offer it
// as a Fix button).
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:studio_ext/shared/icons/icons_generate_command.dart' as icons;
import 'package:studio_ext/shared/permissions/permissions_command.dart';
import 'package:studio_ext/src/shared/permissions/project_plists.dart';
import 'package:studio_ext/src/shared/privacy/pbxproj_resources.dart';

/// `xcross privacy init`.
final class PrivacyCommand extends Command<void> {
  PrivacyCommand(PermissionsContext context) {
    addSubcommand(PrivacyInitCommand(context));
  }

  @override
  String get name => 'privacy';

  @override
  String get description =>
      "The app's privacy manifest (ios/Runner/PrivacyInfo.xcprivacy).";
}

/// Writes a starting `ios/Runner/PrivacyInfo.xcprivacy` when there is none
/// and adds it to the Runner target, so the build copies it into the app.
final class PrivacyInitCommand extends Command<void> {
  PrivacyInitCommand(this.context) {
    argParser
      ..addFlag('json', negatable: false, help: 'Print one JSON object.')
      ..addOption(
        'project',
        valueHelp: 'dir',
        help: 'The Flutter project (default: the current folder).',
      );
  }

  final PermissionsContext context;

  static const manifestPath = 'ios/Runner/PrivacyInfo.xcprivacy';
  static const _pbxprojPath = 'ios/Runner.xcodeproj/project.pbxproj';

  /// A manifest that says the app does not track and declares nothing yet:
  /// the developer adds the data the app collects, and `release check` names
  /// any required-reason API the app's code uses.
  static const starter =
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
      '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
      '<plist version="1.0">\n'
      '<dict>\n'
      '\t<key>NSPrivacyTracking</key>\n'
      '\t<false/>\n'
      '\t<key>NSPrivacyTrackingDomains</key>\n'
      '\t<array/>\n'
      '\t<key>NSPrivacyCollectedDataTypes</key>\n'
      '\t<array/>\n'
      '\t<key>NSPrivacyAccessedAPITypes</key>\n'
      '\t<array/>\n'
      '</dict>\n'
      '</plist>\n';

  @override
  String get name => 'init';

  @override
  String get description =>
      'Write ios/Runner/PrivacyInfo.xcprivacy (when missing) and add it to '
      'the Runner target.';

  @override
  Future<void> run() async {
    final json = argResults!.flag('json');
    final root = icons.projectOption(
      this,
      context.fileSystem,
      context.currentDirectory(),
    );
    final plists = ProjectPlists(
      fileSystem: context.fileSystem,
      paths: context.paths,
      root: root,
      now: context.now,
    );
    if (!plists.hasIos) {
      throw CliError(
        '[privacy.no_ios] No ios/Runner/Info.plist in $root.\n'
        'hint: Run in a Flutter project folder, or pass --project <dir>.',
      );
    }
    final pbxproj = _read(root, _pbxprojPath);
    if (!pbxproj.exists) {
      throw CliError(
        '[privacy.no_xcode_project] No $_pbxprojPath in $root.\n'
        'hint: Run `flutter create --platforms ios .` to bring the iOS '
        'project back.',
      );
    }

    // Read the project first, so a project this cannot change leaves no
    // half-done work behind.
    final PbxResourceResult edit;
    try {
      edit = addRunnerResource(pbxproj.text!, 'PrivacyInfo.xcprivacy');
    } on PbxEditException catch (error) {
      throw CliError(
        '[privacy.xcode_project_unsupported] $error\n'
        'hint: Add $manifestPath to the Runner target in Xcode (File > Add '
        'Files to "Runner").',
      );
    }

    final manifest = _read(root, manifestPath);
    final created = !manifest.exists;
    if (created) plists.write(manifest, starter);
    final backup = plists.write(pbxproj, edit.text, backups: 'privacy-backups');

    final xcode = switch (edit.state) {
      PbxResourceState.added => 'added',
      PbxResourceState.listed => 'listed',
      PbxResourceState.synchronized => 'synchronized',
    };
    final relativeBackup = backup == null
        ? null
        : context.paths.relative(backup, from: root).replaceAll(r'\', '/');
    final text = StringBuffer()
      ..writeln(
        created
            ? '✔ Wrote $manifestPath (no tracking, nothing declared yet).'
            : '✔ $manifestPath is already there; left as it is.',
      )
      ..writeln(switch (edit.state) {
        PbxResourceState.added =>
          '✔ Added it to the Runner target (Copy Bundle Resources).',
        PbxResourceState.listed => '✔ The Runner target already copies it.',
        PbxResourceState.synchronized =>
          '✔ The Runner folder is synced by Xcode, so the build copies it.',
      });
    if (relativeBackup != null) {
      text.writeln('  The old project file is in $relativeBackup.');
    }
    text.writeln(
      'Next: add the data your app collects to the manifest, then build '
      'again and run `xcross release check`.',
    );
    context.write(
      json
          ? '${jsonEncode({'v': 1, 'type': 'privacy_init', 'project': root, 'manifest': manifestPath, 'created': created, 'xcode': xcode, 'backup': relativeBackup})}\n'
          : text.toString(),
    );
  }

  ProjectPlist _read(String root, String relative) {
    final path = context.paths.joinAll([root, ...relative.split('/')]);
    final file = context.fileSystem.file(path);
    return ProjectPlist(
      path,
      relative,
      file.existsSync() ? file.readAsStringSync() : null,
    );
  }
}
