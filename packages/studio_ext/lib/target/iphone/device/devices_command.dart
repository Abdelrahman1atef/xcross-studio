import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_mobile_device/host/shared/usbmux_listen.dart'; // studio: 017
import 'package:dart_mobile_device/shared/device/models/device.dart';
import 'package:studio_ext/src/target/iphone/device/device_codes.dart';
import 'package:studio_ext/src/target/iphone/device/device_watch.dart'; // studio: 017
import 'package:studio_ext/src/target/iphone/device/log_output.dart';
import 'package:studio_ext/target/iphone/device/device_log_backend.dart';

/// `xcross devices [--json]`: the iPhones connected by USB, with their iOS
/// version (feature 008, for the GUI's device picker).
final class DevicesCommand extends Command<void> {
  DevicesCommand({
    required DeviceLogBackend backend,
    required void Function(List<int>) writeBytes,
    Stream<UsbmuxEvent> Function()? listen,
    Future<void> Function()? untilStopped,
  }) : _backend = backend,
       _writeBytes = writeBytes,
       _listen = listen,
       _untilStopped =
           untilStopped ?? (() => ProcessSignal.sigint.watch().first) {
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help: 'One device JSON line per iPhone.',
      )
      // studio: 017
      ..addFlag(
        'watch',
        negatable: false,
        help:
            'Keep running and report the list again whenever an iPhone is '
            'plugged in or out (with --json: one "devices" snapshot per '
            'change).',
      );
  }

  final DeviceLogBackend _backend;
  final void Function(List<int>) _writeBytes;

  /// usbmuxd `Listen` sessions for `--watch`.
  final Stream<UsbmuxEvent> Function()? _listen;

  /// Completes when `--watch` should stop (Ctrl+C by default).
  final Future<void> Function() _untilStopped;

  @override
  String get name => 'devices';

  @override
  String get description => 'List the iPhones connected by USB.';

  @override
  String get invocation => 'xcross devices [--json] [--watch]';

  @override
  Future<void> run() async {
    final json = argResults!.flag('json');
    if (argResults!.flag('watch')) {
      await _watch(json: json);
      return;
    }
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

  // studio: 017
  Future<void> _watch({required bool json}) async {
    final listen = _listen;
    if (listen == null) {
      throw UsageException('--watch is not available here.', usage);
    }
    List<Device>? previous;
    void write(String text) => _writeBytes(utf8.encode(text));
    await DeviceWatch(
      listen: listen,
      list: _backend.usbDevices,
      onNotice: (message) => write(
        json
            ? ndjsonLine({'v': 1, 'type': 'notice', 'message': message})
            : '$message\n',
      ),
      onSnapshot: (devices) {
        if (json) {
          write(
            ndjsonLine({
              'v': 1,
              'type': 'devices',
              'devices': [for (final device in devices) _deviceJson(device)],
            }),
          );
        } else {
          write(_changes(previous, devices));
        }
        previous = devices;
      },
    ).run(_untilStopped());
  }

  static Map<String, Object?> _deviceJson(Device device) => {
    'udid': device.udid,
    'name': device.name,
    'osVersion': device.osVersion,
    'connection': device.type.name,
  };

  /// The first list in full, then `+`/`-` lines.
  static String _changes(List<Device>? before, List<Device> now) {
    final out = StringBuffer();
    if (before == null) {
      for (final device in now) {
        out.writeln(
          '${device.name}  iOS ${device.osVersion ?? '?'}  ${device.udid}',
        );
      }
      if (now.isEmpty) out.writeln('No iPhone is connected by USB.');
      return out.toString();
    }
    final had = {for (final d in before) d.udid};
    final has = {for (final d in now) d.udid};
    for (final device in before) {
      if (!has.contains(device.udid)) out.writeln('- ${device.name}');
    }
    for (final device in now) {
      if (!had.contains(device.udid)) {
        out.writeln('+ ${device.name} (iOS ${device.osVersion ?? '?'})');
      }
    }
    return out.toString();
  }
}
