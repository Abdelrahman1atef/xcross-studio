// studio: 005 — `xcross install <ipa|app>`: sign with the user's account and
// install any app bundle (Sideloadly replacement, part 2).
@internal
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:xcross/src/composition/cli/app_bundle_input.dart'; // studio: 011

/// Signs (unless [resign] is false) and installs the prepared `.app` at
/// [appPath] on the device.
@internal
typedef InstallOnDevice =
    Future<void> Function({
      required String appPath,
      required String bundleId,
      required String? udid,
      required String? ddiDirectory,
      required bool launch,
      // studio: 011 — `--no-resign` installs an IPA `xcross sign` wrote.
      required bool resign,
    });

/// `xcross install <path>`: an `.ipa` or `.app` from any source, re-signed
/// with the saved Apple ID / App Store Connect key, installed over USB on
/// iOS 15+, then opened (iOS 17+ through CoreDevice; iOS 15/16 through the
/// user's developer disk image, or tap-to-open guidance).
@internal
final class InstallCommand extends Command<void> {
  InstallCommand({
    required this.fileSystem,
    required this.paths,
    required this.temporaryRoot,
    required this.installOnDevice,
  }) {
    argParser
      ..addOption('udid', help: 'Device UDID (when several are connected).')
      ..addOption(
        'ddi',
        help:
            'iOS 15/16: folder with DeveloperDiskImage.dmg + .signature from '
            'your own Xcode, used to open the app after install.',
      )
      ..addFlag('launch', defaultsTo: true, help: 'Open the app after install.')
      ..addFlag(
        'resign',
        defaultsTo: true,
        help:
            'Sign with your account before installing. --no-resign installs '
            'the app as it is signed (for example an IPA from xcross sign).',
      );
  }

  final HostFileSystemInterface fileSystem;
  final p.Context paths;
  final String temporaryRoot;
  final InstallOnDevice installOnDevice;

  @override
  String get name => 'install';

  @override
  String get description =>
      'Sign an .ipa or .app with your Apple ID and install it on the '
      'connected iPhone (iOS 15+).';

  @override
  String get invocation =>
      'xcross install <ipa|app> [--udid <id>] [--ddi <dir>] [--no-launch] '
      '[--no-resign]';

  @override
  Future<void> run() async {
    final args = argResults!;
    if (args.rest.length != 1) {
      usageException('Pass exactly one .ipa file or .app directory.');
    }
    final input = AppBundleInput(fileSystem: fileSystem, paths: paths);
    final work = fileSystem
        .directory(temporaryRoot)
        .createTempSync('xcross-install-');
    try {
      final appPath = input.prepare(
        args.rest.single,
        work.path,
        forSigning: args.flag('resign'),
      );
      await installOnDevice(
        appPath: appPath,
        bundleId: input.bundleId(appPath),
        udid: args.option('udid'),
        ddiDirectory: args.option('ddi'),
        launch: args.flag('launch'),
        resign: args.flag('resign'),
      );
    } finally {
      try {
        work.deleteSync(recursive: true);
      } on FileSystemException {
        // Best effort; the temp folder is cleaned by the OS eventually.
      }
    }
  }
}
