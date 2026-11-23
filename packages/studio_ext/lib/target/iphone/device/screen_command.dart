// studio: 048 — live iPhone screen (specs in the Studio repo: 048-iphone-screen).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:studio_ext/src/target/iphone/device/log_output.dart';
import 'package:studio_ext/target/iphone/device/screen_helper.dart';

/// `xcross screen`: the live screen of a USB-connected iPhone, through the
/// bundled `xcross-screen` helper.
final class ScreenCommand extends Command<void> {
  ScreenCommand({
    required ScreenHelper helper,
    required void Function(List<int>) writeBytes,
    required void Function(String) writeError,
    Future<void> Function()? untilStopped,
  }) {
    addSubcommand(
      ScreenStreamCommand(
        helper: helper,
        writeBytes: writeBytes,
        writeError: writeError,
        untilStopped: untilStopped,
      ),
    );
    addSubcommand(ScreenDevicesCommand(helper: helper, writeBytes: writeBytes));
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

/// `xcross screen stream --udid <udid> [--json]`.
final class ScreenStreamCommand extends Command<void> {
  ScreenStreamCommand({
    required ScreenHelper helper,
    required void Function(List<int>) writeBytes,
    required void Function(String) writeError,
    Future<void> Function()? untilStopped,
  }) : _helper = helper,
       _writeBytes = writeBytes,
       _writeError = writeError,
       _untilStopped =
           untilStopped ?? (() => ProcessSignal.sigint.watch().first) {
    argParser
      ..addOption('udid', help: 'The iPhone to show.', mandatory: true)
      ..addFlag('json', negatable: false, help: 'One JSON event per line.');
  }

  final ScreenHelper _helper;
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
  String get invocation => 'xcross screen stream --udid <udid> [--json]';

  @override
  Future<void> run() async {
    final json = argResults!.flag('json');
    final udid = argResults!.option('udid')!;
    final process = await _helper.start(['stream', '--serial', udid]);
    if (process == null) {
      _write(_helperMissing(), json: json);
      throw _helperMissingError();
    }
    String? endReason;
    final linesDone = process.lines.forEach((line) {
      final event = _parse(line);
      if (event == null) return; // never pass through non-JSON stdout
      if (event['type'] == 'screen_end') endReason = event['reason'] as String?;
      _write(event, json: json);
    });
    final errorsDone = process.errors.forEach(_writeError);
    final stop = _untilStopped().then((_) => process.stop());
    final code = await process.exitCode;
    await Future.wait([linesDone, errorsDone]);
    unawaited(stop);
    if (code != 0) {
      throw CliError(
        '[screen.${endReason ?? 'error'}] The iPhone screen stopped '
        '(helper exit $code).',
      );
    }
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
    } else if (event['type'] == 'devices') {
      final devices = (event['devices'] as List?) ?? const [];
      final text = devices.isEmpty
          ? 'No iPhone on the screen driver (${event['driver']}).'
          : [
              for (final d in devices.cast<Map<Object?, Object?>>())
                '${d['serial']}  ${d['captureReady'] == true ? 'capture ready' : 'needs replug'}',
            ].join('\n');
      _writeBytes(utf8.encode('$text\n'));
    } else {
      final text = _describe(event);
      if (text != null) _writeBytes(utf8.encode('$text\n'));
    }
  }
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
  'screen_end' =>
    'Screen ended: ${e['reason']}'
        '${(e['message'] as String?)?.isNotEmpty == true ? ' (${e['message']})' : ''}',
  _ => null,
};
