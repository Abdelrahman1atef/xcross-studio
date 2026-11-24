// studio: 048 — live iPhone screen (specs in the Studio repo: 048-iphone-screen).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:studio_ext/src/target/iphone/device/log_output.dart';
import 'package:studio_ext/target/iphone/device/screen_core_device.dart';
import 'package:studio_ext/target/iphone/device/screen_helper.dart';
import 'package:studio_ext/target/iphone/device/screen_touch.dart';

/// `xcross screen`: the live screen of a USB-connected iPhone, through the
/// bundled `xcross-screen` helper.
final class ScreenCommand extends Command<void> {
  ScreenCommand({
    required ScreenHelper helper,
    required void Function(List<int>) writeBytes,
    required void Function(String) writeError,
    Future<void> Function()? untilStopped,
    ScreenTouch? touch,
    CoreDeviceScreen? coreDevice,
    Command<void>? touchSetup,
  }) {
    addSubcommand(
      ScreenStreamCommand(
        helper: helper,
        writeBytes: writeBytes,
        writeError: writeError,
        untilStopped: untilStopped,
        touch: touch,
        coreDevice: coreDevice,
      ),
    );
    addSubcommand(ScreenDevicesCommand(helper: helper, writeBytes: writeBytes));
    addSubcommand(ScreenDriverCommand(helper: helper, writeBytes: writeBytes));
    if (touchSetup != null) addSubcommand(touchSetup);
  }

  @override
  String get name => 'screen';

  @override
  String get description =>
      'Show the live screen of a USB-connected iPhone (spec 048).';
}

const _helperMissingMessage =
    'This engine has no screen helper (xcross-screen). Update the engine.';

/// The event a missing helper is reported with (JSON and text).
Map<String, Object?> _helperMissing() => {
  'v': 1,
  'type': 'screen_end',
  'reason': 'helper_missing',
  'message': _helperMissingMessage,
};

CliError _helperMissingError() => CliError(
  '[screen.helper_missing] $_helperMissingMessage\n'
  'hint: Update the engine from XCross Studio (Setup), then try again.',
);

/// `xcross screen stream --udid <udid> [--no-touch] [--json]`.
final class ScreenStreamCommand extends Command<void> {
  ScreenStreamCommand({
    required ScreenHelper helper,
    required void Function(List<int>) writeBytes,
    required void Function(String) writeError,
    Future<void> Function()? untilStopped,
    ScreenTouch? touch,
    CoreDeviceScreen? coreDevice,
  }) : _helper = helper,
       _touch = touch,
       _coreDevice = coreDevice,
       _writeBytes = writeBytes,
       _writeError = writeError,
       _untilStopped =
           untilStopped ?? (() => ProcessSignal.sigint.watch().first) {
    argParser
      ..addOption('udid', help: 'The iPhone to show.', mandatory: true)
      ..addFlag(
        'touch',
        defaultsTo: true,
        help:
            'Taps and swipes through the touch helper on the iPhone, when the '
            'picture has no touch of its own.',
      )
      ..addFlag('json', negatable: false, help: 'One JSON event per line.');
  }

  final ScreenHelper _helper;
  final ScreenTouch? _touch;
  final CoreDeviceScreen? _coreDevice;
  final void Function(List<int>) _writeBytes;
  final void Function(String) _writeError;
  final Future<void> Function() _untilStopped;

  @override
  String get name => 'stream';

  @override
  String get description =>
      'Stream the iPhone screen on 127.0.0.1 (H.264, random token) until '
      'stopped.';

  @override
  String get invocation =>
      'xcross screen stream --udid <udid> [--no-touch] [--json]';

  @override
  Future<void> run() async {
    final json = argResults!.flag('json');
    final udid = argResults!.option('udid')!;
    final core = _coreDevice;
    if (core != null &&
        await core.iosMajor(udid) >= PymdCoreDeviceScreen.firstIos) {
      await _runCoreDevice(core, udid, json: json);
      return;
    }
    final process = await _helper.start(['stream', '--serial', udid]);
    if (process == null) {
      _write(_helperMissing(), json: json);
      throw _helperMissingError();
    }
    String? endReason;
    var stopping = false;
    Future<ScreenTouchLink?>? touch;
    final touchWanted = argResults!.flag('touch') && _touch != null;
    final linesDone = process.lines.forEach((line) {
      final event = _parse(line);
      if (event == null) return; // never pass through non-JSON stdout
      if (event['type'] == 'screen_end') endReason = event['reason'] as String?;
      _write(event, json: json);
      if (event['type'] == 'screen_ready' &&
          event['touch'] != true &&
          touchWanted &&
          touch == null) {
        touch = _startTouch(
          udid,
          process,
          json: json,
          stopping: () => stopping,
        );
      }
    });
    final errorsDone = process.errors.forEach(_writeError);
    final stop = _untilStopped().then((_) => process.stop());
    final code = await process.exitCode;
    stopping = true;
    await Future.wait([linesDone, errorsDone]);
    unawaited(stop);
    // The touch helper's processes must not outlive the screen.
    final link = await touch?.timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );
    await link?.close();
    if (code != 0) {
      throw CliError(
        '[screen.${endReason ?? 'error'}] The iPhone screen stopped '
        '(helper exit $code).',
      );
    }
  }

  /// iOS 27+: Apple's screen service (HEVC picture and live touch in its
  /// viewer page), no driver change and no touch helper.
  Future<void> _runCoreDevice(
    CoreDeviceScreen core,
    String udid, {
    required bool json,
  }) async {
    _write({
      'v': 1,
      'type': 'screen_preparing',
      'detail': "Starting Apple's screen service",
    }, json: json);
    final CoreDeviceScreenSession session;
    try {
      session = await core.start(udid);
    } on CoreDeviceScreenUnavailable catch (e) {
      _write({
        'v': 1,
        'type': 'screen_end',
        'reason': 'coredevice_failed',
        'message': e.message,
      }, json: json);
      throw CliError('[screen.coredevice_failed] ${e.message}');
    }
    final viewer = session.viewer.toString();
    _write({
      'v': 1,
      'type': 'screen_ready',
      'url': viewer,
      'viewer': viewer,
      'codec': 'hevc',
      'width': 0,
      'height': 0,
      'method': 'coredevice',
      'touch': true,
    }, json: json);
    final outputDone = session.output.drain<void>();
    var stopped = false;
    final stop = _untilStopped().then((_) {
      stopped = true;
      return session.stop();
    });
    final code = await session.exitCode;
    unawaited(stop);
    unawaited(outputDone);
    _write({
      'v': 1,
      'type': 'screen_end',
      'reason': stopped ? 'stopped' : 'coredevice_ended',
      'message': stopped ? '' : "Apple's screen service stopped (exit $code).",
    }, json: json);
    if (!stopped) {
      throw CliError(
        "[screen.coredevice_ended] Apple's screen service stopped.",
      );
    }
  }

  /// Starts the touch helper and hands its address to the screen helper,
  /// which says `screen_touch` available once it answers.
  Future<ScreenTouchLink?> _startTouch(
    String udid,
    ScreenHelperProcess process, {
    required bool json,
    required bool Function() stopping,
  }) async {
    void touchEvent(Map<String, Object?> fields) =>
        _write({'v': 1, 'type': 'screen_touch', ...fields}, json: json);
    touchEvent({'state': 'starting'});
    try {
      final link = await _touch!.start(udid);
      if (stopping()) {
        await link.close();
        return null;
      }
      process.send('wda ${link.url}');
      unawaited(
        link.ended.then((why) {
          if (stopping()) return;
          touchEvent({
            'available': false,
            'reason': 'error',
            'message': why.isEmpty
                ? 'The touch helper on the iPhone stopped.'
                : 'The touch helper on the iPhone stopped: $why',
          });
        }),
      );
      return link;
    } on ScreenTouchUnavailable catch (e) {
      touchEvent({
        'available': false,
        'reason': e.reason,
        'message': e.message,
      });
    } on Object catch (e) {
      touchEvent({
        'available': false,
        'reason': 'error',
        'message': 'Touch could not start: $e',
      });
    }
    return null;
  }

  void _write(Map<String, Object?> event, {required bool json}) {
    if (json) {
      _writeBytes(utf8.encode(ndjsonLine(event)));
      return;
    }
    final text = _describe(event);
    if (text != null) _writeBytes(utf8.encode('$text\n'));
  }
}

/// `xcross screen devices [--json]`: iPhones the screen driver can reach.
final class ScreenDevicesCommand extends Command<void> {
  ScreenDevicesCommand({
    required ScreenHelper helper,
    required void Function(List<int>) writeBytes,
  }) : _helper = helper,
       _writeBytes = writeBytes {
    argParser.addFlag('json', negatable: false, help: 'One JSON line.');
  }

  final ScreenHelper _helper;
  final void Function(List<int>) _writeBytes;

  @override
  String get name => 'devices';

  @override
  String get description => 'List the iPhones on the screen driver.';

  @override
  Future<void> run() async {
    final json = argResults!.flag('json');
    final process = await _helper.start(['devices']);
    if (process == null) {
      _out(_helperMissing(), json: json);
      throw _helperMissingError();
    }
    // Read the helper's log output too, so a full pipe can never block it.
    final errorsDone = process.errors.drain<void>();
    await process.lines.forEach((line) {
      final event = _parse(line);
      if (event != null) _out(event, json: json);
    });
    await Future.wait([process.exitCode, errorsDone]);
  }

  void _out(Map<String, Object?> event, {required bool json}) {
    if (json) {
      _writeBytes(utf8.encode(ndjsonLine(event)));
    } else if (event['type'] == 'screen_devices') {
      final devices = (event['devices'] as List?) ?? const [];
      final text = devices.isEmpty
          ? 'No iPhone on the screen driver (${event['driver']}).'
          : [
              for (final d in devices.cast<Map<Object?, Object?>>())
                '${d['serial']}  ${d['captureReady'] == true ? 'ready (capture on)' : 'ready'}',
            ].join('\n');
      _writeBytes(utf8.encode('$text\n'));
    } else {
      final text = _describe(event);
      if (text != null) _writeBytes(utf8.encode('$text\n'));
    }
  }
}

/// `xcross screen driver status|enable|restore [--udid <udid>] [--json]`:
/// Smooth mode on Windows (the iPhone's USB driver; one admin prompt to
/// change it). Studio asks the user before `enable`.
final class ScreenDriverCommand extends Command<void> {
  ScreenDriverCommand({
    required ScreenHelper helper,
    required void Function(List<int>) writeBytes,
  }) : _helper = helper,
       _writeBytes = writeBytes {
    argParser
      ..addOption('udid', help: 'The iPhone (required for enable/restore).')
      ..addFlag('json', negatable: false, help: 'One JSON line.');
  }

  final ScreenHelper _helper;
  final void Function(List<int>) _writeBytes;

  @override
  String get name => 'driver';

  @override
  String get description =>
      'Smooth mode: show (status) or switch (enable / restore) the iPhone USB '
      'driver. Windows asks for administrator permission to switch.';

  @override
  String get invocation =>
      'xcross screen driver status|enable|restore [--udid <udid>] [--json]';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    final action = rest.isEmpty ? 'status' : rest.first;
    if (!const {'status', 'enable', 'restore'}.contains(action)) {
      throw UsageException('Unknown action "$action".', usage);
    }
    final udid = argResults!.option('udid');
    if (action != 'status' && (udid == null || udid.isEmpty)) {
      throw UsageException('--udid is required for $action.', usage);
    }
    final json = argResults!.flag('json');
    final process = await _helper.start([
      'driver',
      action,
      if (action != 'status') ...['--serial', udid!],
    ]);
    if (process == null) {
      if (json) _writeBytes(utf8.encode(ndjsonLine(_helperMissing())));
      throw _helperMissingError();
    }
    final errorsDone = process.errors.drain<void>();
    Map<String, Object?>? change;
    await process.lines.forEach((line) {
      final event = _parse(line);
      if (event == null) return;
      if (event['type'] == 'screen_driver_change') change = event;
      if (json) {
        _writeBytes(utf8.encode(ndjsonLine(event)));
      } else {
        _writeBytes(utf8.encode('${_describeDriver(event)}\n'));
      }
    });
    final code = await process.exitCode;
    await errorsDone;
    if (code != 0) {
      throw CliError(
        '[screen.driver] ${change?['message'] ?? 'The driver switch failed.'}',
      );
    }
  }
}

String _describeDriver(Map<String, Object?> e) {
  if (e['type'] == 'screen_driver') {
    final devices = (e['devices'] as List?) ?? const [];
    if (devices.isEmpty) return 'No iPhone plugged in by USB.';
    return [
      for (final d in devices.cast<Map<Object?, Object?>>())
        '${d['serial']}  ${switch (d['state']) {
          'smooth' => 'Smooth mode on',
          'apple' => "Apple's driver (Smooth mode off)",
          _ => 'other driver',
        }}',
    ].join('\n');
  }
  final ok = e['ok'] == true;
  return '${ok ? 'Done' : 'Not changed'}: ${e['message'] ?? ''}';
}

Map<String, Object?>? _parse(String line) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is Map && decoded['type'] is String) {
      return {'v': 1, ...decoded.cast<String, Object?>()};
    }
  } on FormatException {
    // Not an event.
  }
  return null;
}

String? _describe(Map<String, Object?> e) => switch (e['type']) {
  'screen_preparing' => '… ${e['detail'] ?? e['step']}',
  'screen_device' => 'iPhone model: ${e['productType']}',
  'screen_format' => 'Picture: ${e['width']}x${e['height']} ${e['codec']}',
  'screen_ready' =>
    'Screen ready: ${e['url']} (${e['width']}x${e['height']}, ${e['codec']}, ${e['method']})',
  'screen_stats' => 'Live: ${e['fps']} fps, ${e['mbps']} Mbps',
  'screen_touch' => switch (e) {
    {'state': 'starting'} => '… Starting the touch helper on the iPhone',
    {'available': true} => 'Touch: on (click = tap, drag = swipe)',
    _ => 'Touch: off (${e['message'] ?? e['reason']})',
  },
  'screen_end' =>
    'Screen ended: ${e['reason']}'
        '${(e['message'] as String?)?.isNotEmpty == true ? ' (${e['message']})' : ''}',
  _ => null,
};
