import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:studio_ext/src/target/iphone/device/device_codes.dart';
import 'package:studio_ext/src/target/iphone/device/installed_app_info.dart';
import 'package:studio_ext/src/target/iphone/device/log_output.dart';
import 'package:studio_ext/target/iphone/device/device_log_backend.dart';

/// `xcross app`: facts about apps installed on the iPhone (feature 010).
final class AppCommand extends Command<void> {
  AppCommand({
    required DeviceLogBackend backend,
    required void Function(List<int>) writeBytes,
  }) {
    addSubcommand(AppInfoCommand(backend: backend, writeBytes: writeBytes));
  }

  @override
  String get name => 'app';

  @override
  String get description => 'Inspect apps installed on the connected iPhone.';
}

/// `xcross app info <bundle-id>`: version, signer and entitlements as
/// installed, with ✔/✖ for push and associated domains.
final class AppInfoCommand extends Command<void> {
  AppInfoCommand({
    required DeviceLogBackend backend,
    required void Function(List<int>) writeBytes,
  }) : _backend = backend,
       _writeBytes = writeBytes {
    argParser
      ..addOption('udid', help: 'Device UDID (when several are connected).')
      ..addFlag('json', negatable: false, help: 'One appinfo JSON line.')
      ..addFlag(
        'show-sensitive',
        negatable: false,
        help: 'Also show the raw signing identity.',
      );
  }

  final DeviceLogBackend _backend;
  final void Function(List<int>) _writeBytes;

  @override
  String get name => 'info';

  @override
  String get description =>
      'Version, signer type, team and entitlements as installed '
      '(answers "did the signer keep aps-environment?").';

  @override
  String get invocation => 'xcross app info <bundle-id> [--udid <id>] [--json]';

  @override
  Future<void> run() async {
    final args = argResults!;
    if (args.rest.length != 1) usageException('Pass exactly one bundle id.');
    final bundleId = args.rest.single;
    try {
      final udid = await _backend.ensureDevice(args.option('udid'));
      final entry = (await _backend.installedApps(udid))[bundleId];
      if (entry == null) {
        throw DeviceFailure(
          DeviceCodes.appNotInstalled,
          '$bundleId is not installed on the iPhone.',
        );
      }
      final info = InstalledAppInfo.fromAppsList(bundleId, entry);
      _writeBytes(
        utf8.encode(
          args.flag('json')
              ? ndjsonLine(info.toJson())
              : info.toHuman(showSensitive: args.flag('show-sensitive')),
        ),
      );
    } on DeviceFailure catch (failure) {
      throw failure.toCliError();
    }
  }
}
