// studio: 017 — `xcross devices --watch` (specs/017-device-watcher).
import 'dart:async';
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:dart_mobile_device/host/shared/usbmux_listen.dart';
import 'package:dart_mobile_device/shared/device/models/device.dart';
import 'package:studio_ext/src/target/iphone/device/device_watch.dart';
import 'package:studio_ext/target/iphone/device/devices_command.dart';
import 'package:test/test.dart';

import '../../../support/fake_device_backend.dart';

const _phone = Device(
  name: 'Test Phone',
  udid: '00008020-001A2B3C4D5E6F70',
  type: ConnectionType.usb,
  osVersion: '16.7.16',
);

void main() {
  late List<StreamController<UsbmuxEvent>> sessions;
  late List<Device> connected;
  late int lists;
  late List<List<String>> snapshots;
  late List<String> notices;
  late Completer<void> stop;

  setUp(() {
    sessions = [];
    connected = [];
    lists = 0;
    snapshots = [];
    notices = [];
    stop = Completer<void>();
  });

  Stream<UsbmuxEvent> listen() {
    final controller = StreamController<UsbmuxEvent>();
    sessions.add(controller);
    return controller.stream;
  }

  DeviceWatch watch() => DeviceWatch(
    listen: listen,
    list: () async {
      lists++;
      return List.of(connected);
    },
    onSnapshot: (devices) => snapshots.add([for (final d in devices) d.name]),
    onNotice: notices.add,
    debounce: const Duration(milliseconds: 20),
    retry: const Duration(milliseconds: 50),
  );

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 80));

  group('AC-017-2 snapshots', () {
    test('a snapshot at start, even with no device', () async {
      final running = watch().run(stop.future);
      await settle();
      expect(snapshots, [<String>[]]);
      stop.complete();
      await running;
    });

    test('attach re-reads; detach drops at once; bursts are merged', () async {
      final running = watch().run(stop.future);
      await settle();
      connected.add(_phone);
      sessions.single
        ..add(UsbmuxAttached(5, udid: _phone.udid, connectionType: 'USB'))
        ..add(UsbmuxAttached(5, udid: _phone.udid, connectionType: 'USB'));
      await settle();
      expect(snapshots.last, ['Test Phone']);
      final readsAfterAttach = lists;
      expect(readsAfterAttach, 2, reason: 'start + one merged re-read');

      connected.clear();
      sessions.single.add(const UsbmuxDetached(5));
      await Future<void>.delayed(Duration.zero);
      expect(snapshots.last, isEmpty);
      expect(lists, readsAfterAttach, reason: 'a detach does not re-read');
      stop.complete();
      await running;
    });

    test(
      'network devices are ignored; unchanged lists are not repeated',
      () async {
        final running = watch().run(stop.future);
        await settle();
        sessions.single.add(
          const UsbmuxAttached(9, udid: 'WIFI', connectionType: 'Network'),
        );
        await settle();
        expect(snapshots, hasLength(1));
        stop.complete();
        await running;
      },
    );
  });

  test('AC-017-3 an outage is reported once, retried, and recovered', () async {
    final running = watch().run(stop.future);
    await settle();
    connected.add(_phone);
    sessions.single.add(
      UsbmuxAttached(1, udid: _phone.udid, connectionType: 'USB'),
    );
    await settle();
    expect(snapshots.last, ['Test Phone']);

    sessions.single.addError(const UsbmuxUnavailable('closed'));
    await settle();
    await settle();
    expect(notices, [DeviceWatch.unreachable]);
    // Empty once while the service is down, then the retry's first read.
    expect(
      snapshots,
      containsAllInOrder([
        ['Test Phone'],
        <String>[],
        ['Test Phone'],
      ]),
    );
    expect(sessions.length, greaterThanOrEqualTo(2));
    stop.complete();
    await running;
  });

  group('AC-017-2 / AC-017-4 the command', () {
    late List<int> out;
    setUp(() => out = []);

    Future<void> run(List<String> args, FakeDeviceBackend backend) =>
        (CommandRunner<void>('xcross', 'test')..addCommand(
              DevicesCommand(
                backend: backend,
                writeBytes: out.addAll,
                listen: listen,
                untilStopped: () => stop.future,
              ),
            ))
            .run(args);

    test('--watch --json prints devices snapshots', () async {
      final running = run([
        'devices',
        '--watch',
        '--json',
      ], FakeDeviceBackend(devices: const [_phone]));
      await settle();
      stop.complete();
      await running;
      final line = const LineSplitter().convert(utf8.decode(out)).single;
      expect(jsonDecode(line), {
        'v': 1,
        'type': 'devices',
        'devices': [
          {
            'udid': _phone.udid,
            'name': 'Test Phone',
            'osVersion': '16.7.16',
            'connection': 'usb',
          },
        ],
      });
    });

    test('--watch prints the list, then - and + lines', () async {
      final backend = FakeDeviceBackend(devices: const [_phone]);
      final running = run(['devices', '--watch'], backend);
      await settle();
      sessions.single
        ..add(UsbmuxAttached(2, udid: _phone.udid, connectionType: 'USB'))
        ..add(const UsbmuxDetached(2));
      await settle();
      stop.complete();
      await running;
      final text = utf8.decode(out);
      expect(text, contains('Test Phone  iOS 16.7.16'));
      expect(text, contains('- Test Phone'));
    });
  });
}
