// studio: 012 — xcross reports structured events in XCROSS_EVENTS=ndjson mode.
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/logging/logging.dart';
import 'package:dart_mobile_device/shared/device/models/device.dart';
import 'package:studio_ext/shared/events/ndjson_events.dart';
import 'package:test/test.dart';
import 'package:xcross/src/composition/cli/runner.dart';
import 'package:xcross/src/shared/cli/basic/doctor_command.dart';
import 'package:xcross/src/shared/cli/basic/doctor_models.dart';
import 'package:xcross/src/target/iphone/device/device_precheck.dart';

import '../device/test_log_output.dart';

void main() {
  late List<int> bytes;
  late Log log;

  setUp(() {
    bytes = [];
    final events = NdjsonEvents(bytes.addAll);
    log = Log(output: events.logOutput, events: events);
  });

  List<Map<String, Object?>> decoded() => [
    for (final line in const LineSplitter().convert(utf8.decode(bytes)))
      (jsonDecode(line) as Map).cast<String, Object?>(),
  ];

  test('AC-012-3 a failure becomes an error event with code and hint', () {
    XcrossCli.reportFailure(
      log,
      'error: [device.not_found] No iPhone is connected by USB.\n'
      'hint: Connect it, unlock it and tap Trust.',
    );
    expect(decoded().single, {
      'v': 1,
      'type': 'error',
      'code': 'device.not_found',
      'message': 'No iPhone is connected by USB.',
      'hint': 'Connect it, unlock it and tap Trust.',
    });

    final output = TestLogOutput();
    XcrossCli.reportFailure(Log(output: output), 'error: boom');
    expect(output.messages, ['error: boom'], reason: 'human mode unchanged');
  });

  test(
    'AC-012-4 the precheck reports the chosen device without its UDID',
    () async {
      final prechecked = await DevicePrecheck(
        log: log,
        serviceProblem: () async => null,
        resolveDevice: ({required mode, selector}) async => const Device(
          name: 'iPhone X',
          udid: '00000000-0000000000000000',
          type: ConnectionType.usb,
          osVersion: '16.7.16',
        ),
        osMajor: (_) async => 16,
      ).run(mode: DeviceSearchMode.usb);
      expect(prechecked.legacy, isTrue);
      final device = decoded().singleWhere((e) => e['type'] == 'device');
      expect(device, {
        'v': 1,
        'type': 'device',
        'name': 'iPhone X',
        'osVersion': '16.7.16',
        'legacy': true,
        'connection': 'usb',
      });
      expect(utf8.decode(bytes), isNot(contains('00000000-0000000000000000')));
    },
  );

  test('AC-012-5 the doctor reports one check event per check', () async {
    final runner = CommandRunner<void>('xcross', 'test')
      ..addCommand(
        DoctorCommand(
          framework: 'Flutter',
          log: log,
          sections: [
            DoctorSection(
              'Device service',
              () async => const [
                DoctorCheck.success('usbmuxd', 'Found', path: '/run/usbmuxd'),
                DoctorCheck.warning('Developer disk image', 'Not found'),
              ],
            ),
          ],
        ),
      );
    await runner.run(['doctor']);
    final checks = [
      for (final e in decoded())
        if (e['type'] == 'check') e,
    ];
    expect(checks, [
      {
        'v': 1,
        'type': 'check',
        'section': 'Device service',
        'name': 'usbmuxd',
        'status': 'success',
        'message': 'Found',
        'path': '/run/usbmuxd',
      },
      {
        'v': 1,
        'type': 'check',
        'section': 'Device service',
        'name': 'Developer disk image',
        'status': 'warning',
        'message': 'Not found',
        'path': null,
      },
    ]);
    expect(
      decoded().where((e) => e['type'] == 'log'),
      isNotEmpty,
      reason: 'the human report is kept as log events',
    );
  });
}
