// studio: 011 — `xcross sign <ipa|app>`: write a re-signed, installable IPA
// without installing it (Sideloadly replacement, part 1; upstream #146).
@internal
library;

import 'dart:io';

import 'package:apple_developer_kit/shared/errors/errors.dart';
import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/inspect/signed_bundle_check.dart';
import 'package:studio_ext/shared/ipa/ipa_writer.dart';
import 'package:xcross/src/composition/cli/app_bundle_input.dart';
import 'package:xcross/src/shared/diagnostics/xcross_diagnostics.dart';

/// Provisions and signs the prepared `.app` at [appPath] in place for
/// [deviceUdids] (plus every device already on the team) and returns the
/// bundle id it was signed as.
@internal
typedef SignApp =
    Future<String> Function({
      required String appPath,
      required String bundleId,
      required List<String> deviceUdids,
    });

/// UDIDs of the iPhones connected by USB; empty when none (or no service).
@internal
typedef ConnectedDeviceUdids = Future<List<String>> Function();

/// Checks the written IPA.
@internal
typedef VerifySignedIpa = SignedBundleCheck Function(String ipaPath);

/// `xcross sign <ipa|app> [-o <out.ipa>] [--udid <id>]… [--bundle-id <id>]`.
@internal
final class SignCommand extends Command<void> {
  SignCommand({
    required this.fileSystem,
    required this.paths,
    required this.temporaryRoot,
    required this.signApp,
    required this.connectedDevices,
    required this.write,
    VerifySignedIpa? verify,
  }) : verify = verify ?? ((path) => SignedBundleCheck.run(fileSystem, path)) {
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Where to write the signed IPA (default: <input>-signed.ipa).',
      )
      ..addMultiOption(
        'udid',
        help:
            'Register this device on your team and include it (repeatable; '
            'it need not be connected).',
      )
      ..addOption(
        'bundle-id',
        help: "Sign under this bundle id instead of the app's own.",
      )
      ..addFlag(
        'usb',
        defaultsTo: true,
        help: 'Also register the iPhones connected by USB.',
      );
  }

  final HostFileSystemInterface fileSystem;
  final p.Context paths;
  final String temporaryRoot;
  final SignApp signApp;
  final ConnectedDeviceUdids connectedDevices;
  final void Function(String) write;
  final VerifySignedIpa verify;

  @override
  String get name => 'sign';

  @override
  String get description =>
      'Re-sign an .ipa or .app with your Apple ID or App Store Connect key '
      'and write an installable .ipa (nothing is installed).';

  @override
  String get invocation =>
      'xcross sign <ipa|app> [-o <out.ipa>] [--udid <id>]... '
      '[--bundle-id <id>] [--no-usb]';

  @override
  Future<void> run() async {
    final args = argResults!;
    if (args.rest.length != 1) {
      usageException('Pass exactly one .ipa file or .app directory.');
    }
    final source = args.rest.single;
    final output = _outputPath(source, args.option('output'));
    final input = AppBundleInput(fileSystem: fileSystem, paths: paths);
    final work = fileSystem
        .directory(temporaryRoot)
        .createTempSync('xcross-sign-');
    try {
      final appPath = input.prepare(source, work.path);
      final requestedId = args.option('bundle-id')?.trim();
      if (requestedId != null && requestedId.isNotEmpty) {
        input.setBundleId(appPath, requestedId);
      }
      final bundleId = input.bundleId(appPath);
      if (input.looksEncrypted(appPath)) {
        write(
          'warning: ${codedWarning(XcrossCodes.signEncryptedApp, '${paths.basename(appPath)} contains SC_Info (App Store encryption).')}\n',
        );
      }
      final udids = await _deviceUdids(
        args.multiOption('udid'),
        usb: args.flag('usb'),
      );
      write(
        udids.isEmpty
            ? 'No device given: the profile lists the devices already on '
                  'your team.\n'
            : 'Including ${udids.length} device${udids.length == 1 ? '' : 's'} '
                  '(registered on your team if new).\n',
      );
      final String signedId;
      try {
        signedId = await signApp(
          appPath: appPath,
          bundleId: bundleId,
          deviceUdids: udids,
        );
      } on AppleError catch (error) {
        if (!error.message.contains('No iOS devices are registered')) rethrow;
        throw codedError(
          XcrossCodes.signNoDevice,
          'Your team has no registered iPhone to sign for.',
        );
      }
      IpaWriter(fileSystem: fileSystem, paths: paths).write(appPath, output);
      final check = verify(output);
      if (!check.ok) {
        fileSystem.file(output).deleteSync();
        throw codedError(
          XcrossCodes.signVerifyFailed,
          'The signed app does not look installable: '
          '${check.problems.join('; ')}.',
        );
      }
      write(
        [
          '✔ Signed: $output',
          if (signedId != bundleId) '  (signed as $signedId)',
          ...check.summaryLines().map((line) => '  $line'),
          '  Install it with: xcross install --no-resign "$output"',
          '',
        ].join('\n'),
      );
    } finally {
      try {
        work.deleteSync(recursive: true);
      } on FileSystemException {
        // Best effort; the temp folder is cleaned by the OS eventually.
      }
    }
  }

  String _outputPath(String source, String? requested) {
    final trimmed = source.replaceAll(RegExp(r'[\\/]+$'), '');
    final output =
        requested ??
        paths.join(
          paths.dirname(trimmed),
          '${paths.basenameWithoutExtension(trimmed)}-signed.ipa',
        );
    if (!output.toLowerCase().endsWith('.ipa')) {
      throw codedError(
        XcrossCodes.signOutputInvalid,
        '${paths.basename(output)} is not an .ipa path.',
      );
    }
    if (paths.equals(paths.absolute(output), paths.absolute(trimmed))) {
      throw codedError(
        XcrossCodes.signOutputInvalid,
        'The output would overwrite the input ${paths.basename(trimmed)}.',
      );
    }
    return output;
  }

  Future<List<String>> _deviceUdids(
    List<String> given, {
    required bool usb,
  }) async {
    final udids = <String>[];
    void add(String udid) {
      final trimmed = udid.trim();
      if (trimmed.isEmpty) return;
      final wanted = trimmed.toUpperCase();
      if (udids.any((u) => u.toUpperCase() == wanted)) return;
      udids.add(trimmed);
    }

    given.forEach(add);
    if (usb) (await connectedDevices()).forEach(add);
    return udids;
  }
}
