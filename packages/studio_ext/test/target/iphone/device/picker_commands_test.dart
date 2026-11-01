// studio: 008 — device and app pickers for the GUI.
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:dart_mobile_device/shared/device/models/device.dart';
import 'package:studio_ext/src/target/iphone/device/device_codes.dart';
import 'package:studio_ext/target/iphone/device/app_command.dart';
import 'package:studio_ext/target/iphone/device/devices_command.dart';
import 'package:test/test.dart';

import '../../../support/fake_device_backend.dart';
import '../../../support/json_schema_lite.dart';

void main() {
  late List<int> out;
  final schema = JsonSchemaLite.devicelogContract();

  setUp(() => out = []);

  String text() => utf8.decode(out);
  List<Map<String, Object?>> events() => [
    for (final line in const LineSplitter().convert(text()))
      (jsonDecode(line) as Map).cast<String, Object?>(),
  ];

  CommandRunner<void> runner(FakeDeviceBackend backend) =>
      CommandRunner<void>('xcross', 'test')
        ..addCommand(DevicesCommand(backend: backend, writeBytes: out.addAll))
        ..addCommand(AppCommand(backend: backend, writeBytes: out.addAll));

  const phone = Device(
    name: 'Test Phone',
    udid: '00008020-001A2B3C4D5E6F70',
    type: ConnectionType.usb,
    osVersion: '16.7.16',
  );

  test('AC-008-1 devices lists USB iPhones as device events', () async {
    await runner(
      FakeDeviceBackend(devices: const [phone]),
    ).run(['devices', '--json']);
    final event = events().single;
    expect(event, {
      'v': 1,
      'type': 'device',
      'udid': phone.udid,
      'name': 'Test Phone',
      'osVersion': '16.7.16',
      'connection': 'usb',
    });
    expect(schema.validate(event), isEmpty);

    out.clear();
    await runner(FakeDeviceBackend(devices: const [phone])).run(['devices']);
    expect(text(), contains('Test Phone  iOS 16.7.16  ${phone.udid}'));

    out.clear();
    await runner(FakeDeviceBackend()).run(['devices', '--json']);
    expect(text(), isEmpty, reason: 'no devices: no events');
    await runner(FakeDeviceBackend()).run(['devices']);
    expect(text(), contains('No iPhone is connected by USB.'));
  });

  test('AC-008-1 a host-service failure is a coded error', () async {
    final backend = FakeDeviceBackend(
      ensureError: DeviceFailure(
        DeviceCodes.hostServiceUnavailable,
        'Apple Mobile Device Service is not running.',
      ),
    );
    await expectLater(
      runner(backend).run(['devices', '--json']),
      throwsA(
        isA<CliError>().having(
          (e) => e.message,
          'message',
          contains('[device.host_service_unavailable]'),
        ),
      ),
    );
    expect(out, isEmpty);
  });

  test('AC-008-2 app list prints the user apps sorted by bundle id', () async {
    final backend = FakeDeviceBackend(
      apps: {
        'com.example.zeta': appEntry(executable: 'Zeta', version: '2.0'),
        'com.example.alpha': appEntry(executable: 'Runner'),
      },
    );
    await runner(backend).run(['app', 'list', '--json']);
    final list = events();
    expect(
      [for (final e in list) e['bundleId']],
      ['com.example.alpha', 'com.example.zeta'],
    );
    expect(list.first, {
      'v': 1,
      'type': 'app',
      'bundleId': 'com.example.alpha',
      'name': 'Fixture',
      'version': '1.2.3',
      'build': '45',
      'executable': 'Runner',
    });
    for (final event in list) {
      expect(schema.validate(event), isEmpty, reason: '$event');
    }
    expect(text(), isNot(contains('Planted Person')));

    out.clear();
    await runner(backend).run(['app', 'list']);
    expect(text(), contains('com.example.zeta  Fixture  2.0'));
  });
}
