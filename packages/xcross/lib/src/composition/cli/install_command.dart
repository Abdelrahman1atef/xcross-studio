// studio: 005 — `xcross install <ipa|app>`: sign with the user's account and
// install any app bundle (Sideloadly replacement, part 2).
@internal
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:xcross/src/shared/diagnostics/xcross_diagnostics.dart';

/// Signs and installs the prepared `.app` at [appPath] on the device.
@internal
typedef InstallOnDevice =
    Future<void> Function({
      required String appPath,
      required String bundleId,
      required String? udid,
      required String? ddiDirectory,
      required bool launch,
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
      ..addFlag(
        'launch',
        defaultsTo: true,
        help: 'Open the app after install.',
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
      'xcross install <ipa|app> [--udid <id>] [--ddi <dir>] [--no-launch]';

  @override
  Future<void> run() async {
    final args = argResults!;
    if (args.rest.length != 1) {
      usageException('Pass exactly one .ipa file or .app directory.');
    }
    final input = args.rest.single;
    final work = fileSystem
        .directory(temporaryRoot)
        .createTempSync('xcross-install-');
    try {
      final appPath = _prepare(input, work.path);
      await installOnDevice(
        appPath: appPath,
        bundleId: _bundleId(appPath),
        udid: args.option('udid'),
        ddiDirectory: args.option('ddi'),
        launch: args.flag('launch'),
      );
    } finally {
      try {
        work.deleteSync(recursive: true);
      } on FileSystemException {
        // Best effort; the temp folder is cleaned by the OS eventually.
      }
    }
  }

  /// A private copy of the app bundle under [work] (the signer rewrites the
  /// bundle in place, so the user's file is never touched).
  String _prepare(String input, String work) {
    final trimmed = input.replaceAll(RegExp(r'[\\/]+$'), '');
    final lower = trimmed.toLowerCase();
    if (fileSystem.directory(input).existsSync() && lower.endsWith('.app')) {
      final target = paths.join(work, paths.basename(trimmed));
      _copyDirectory(fileSystem.directory(input), target);
      return target;
    }
    if (fileSystem.file(input).existsSync() && lower.endsWith('.ipa')) {
      return _extractIpa(input, work);
    }
    throw codedError(
      XcrossCodes.installUnsupportedInput,
      '${paths.basename(input)} is not an existing .ipa file or .app '
      'directory.',
    );
  }

  String _extractIpa(String ipa, String work) {
    final stream = InputFileStream(fileSystem.file(ipa).path);
    try {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeStream(stream);
        // archive reports damaged zips with assorted exception types.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        throw codedError(
          XcrossCodes.installUnsupportedInput,
          '${paths.basename(ipa)} is not a readable zip archive.',
        );
      }
      final apps = <String>{
        for (final entry in archive.files)
          if (entry.name.replaceAll(r'\', '/').split('/') case [
            'Payload',
            final app,
            ...,
          ] when app.endsWith('.app'))
            app,
      };
      if (apps.length != 1) {
        throw codedError(
          XcrossCodes.installNoApp,
          '${paths.basename(ipa)} has ${apps.length} app bundles under '
          'Payload/.',
        );
      }
      final prefix = 'Payload/${apps.single}/';
      final root = paths.join(work, apps.single);
      for (final entry in archive.files) {
        final name = entry.name.replaceAll(r'\', '/');
        if (!entry.isFile || !name.startsWith(prefix)) continue;
        final relative = name.substring(prefix.length);
        if (relative.isEmpty || relative.split('/').contains('..')) continue;
        final target = fileSystem.file(
          paths.joinAll([root, ...relative.split('/')]),
        );
        target.parent.createSync(recursive: true);
        final output = OutputMemoryStream();
        entry.decompress(output);
        target.writeAsBytesSync(output.getBytes());
        if (entry.mode & 0x49 != 0) fileSystem.makeExecutable(target.path);
      }
      return root;
    } finally {
      stream.closeSync();
    }
  }

  void _copyDirectory(Directory source, String target) {
    final root = source.path.replaceAll(RegExp(r'[\\/]+$'), '');
    fileSystem.directory(target).createSync(recursive: true);
    for (final entity in source.listSync(recursive: true, followLinks: false)) {
      final relative = entity.path.substring(root.length + 1);
      final destination = paths.join(target, relative);
      if (entity is Directory) {
        fileSystem.directory(destination).createSync(recursive: true);
      } else if (entity is File) {
        fileSystem.file(destination).parent.createSync(recursive: true);
        entity.copySync(fileSystem.file(destination).path);
      }
    }
  }

  /// `CFBundleIdentifier` from the bundle's Info.plist (binary or XML).
  String _bundleId(String appPath) {
    final file = fileSystem.file(paths.join(appPath, 'Info.plist'));
    if (!file.existsSync()) {
      throw codedError(
        XcrossCodes.installNoApp,
        '${paths.basename(appPath)} has no Info.plist.',
      );
    }
    final bytes = file.readAsBytesSync();
    final Object root;
    try {
      root =
          bytes.length >= 8 &&
              ascii.decode(bytes.sublist(0, 8), allowInvalid: true) ==
                  'bplist00'
          ? PropertyListSerialization.propertyListWithData(
              ByteData.sublistView(bytes),
            )
          : PropertyListSerialization.propertyListWithString(
              utf8.decode(bytes),
            );
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      throw codedError(
        XcrossCodes.installNoApp,
        '${paths.basename(appPath)}/Info.plist is not a valid property list.',
      );
    }
    final id = root is Map ? root['CFBundleIdentifier'] : null;
    if (id is! String || id.isEmpty) {
      throw codedError(
        XcrossCodes.installNoApp,
        '${paths.basename(appPath)} has no CFBundleIdentifier.',
      );
    }
    return id;
  }
}
