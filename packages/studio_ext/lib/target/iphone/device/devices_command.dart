import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:studio_ext/src/target/iphone/device/device_codes.dart';
import 'package:studio_ext/src/target/iphone/device/log_output.dart';
import 'package:studio_ext/target/iphone/device/device_log_backend.dart';

/// `xcross devices [--json]`: the iPhones connected by USB, with their iOS
/// version (feature 008, for the GUI's device picker).
final class DevicesCommand extends Command<void> {
  DevicesCommand({
    required DeviceLogBackend backend,
    required void Function(List<int>) writeBytes,
  }) : _backend = backend,
       _writeBytes = writeBytes {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'One device JSON line per iPhone.',
    );
  }

  final DeviceLogBackend _backend;
  final void Function(List<int>) _writeBytes;

  @override
  String get name => 'devices';

  @override
  String get description => 'List the iPhones connected by USB.';

  @override
  String get invocation => 'xcross devices [--json]';

  @override
  Future<void> run() async {
    final json = argResults!.flag('json');
    try {
      final devices = await _backend.usbDevices();
      final out = StringBuffer();
      for (final device in devices) {
        if (json) {
          out.write(
            ndjsonLine({
              'v': 1,
              'type': 'device',
              'udid': device.udid,
              'name': device.name,
              'osVersion': device.osVersion,
              'connection': device.type.name,
            }),
          );
        } else {
          out.writeln(
            '${device.name}  iOS ${device.osVersion ?? '?'}  ${device.udid}',
          );
        }
      }
      if (!json && devices.isEmpty) {
        out.writeln('No iPhone is connected by USB.');
      }
      _writeBytes(utf8.encode(out.toString()));
    } on DeviceFailure catch (failure) {
      throw failure.toCliError();
    }
  }
}
