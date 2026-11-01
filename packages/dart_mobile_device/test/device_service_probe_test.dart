// studio: 002 — host device service probe and listing OS version.
import 'dart:io';

import 'package:cli_kit/host/macos/macos_host.dart';
import 'package:cli_kit/shared/process/process.dart';
import 'package:dart_mobile_device/host/linux/linux_device_host.dart';
import 'package:dart_mobile_device/host/shared/usbmux_service_probe.dart';
import 'package:dart_mobile_device/host/windows/windows_device_host.dart';
import 'package:dart_mobile_device/target/iphone/device/pymd/pymd_devices.dart';
import 'package:test/test.dart';

import 'test_log_output.dart';

void main() {
  final runner = ProcessRunner(
    MacOSHost(),
    log: testLog(),
    stdinStream: const Stream.empty(),
    stdoutSink: testSink(),
    stderrSink: testSink(),
  );

  Future<(ServerSocket, int)> listener() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) => socket.destroy());
    return (server, server.port);
  }

  Future<int> closedPort() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();
    return port;
  }

  group('AC-002-3 service probe', () {
    test('a listening host:port is reachable; a closed port is not', () async {
      final (server, port) = await listener();
      try {
        expect(await usbmuxServiceReachable('127.0.0.1:$port'), isTrue);
      } finally {
        await server.close();
      }
      expect(
        await usbmuxServiceReachable('127.0.0.1:${await closedPort()}'),
        isFalse,
      );
    });

    test('Windows policy: null when reachable, hint when not', () async {
      final windows = WindowsDeviceHost(runner);
      final (server, port) = await listener();
      try {
        expect(await windows.deviceServiceProblem('127.0.0.1:$port'), isNull);
      } finally {
        await server.close();
      }
      final problem = await windows.deviceServiceProblem(
        '127.0.0.1:${await closedPort()}',
      );
      expect(problem, contains('Apple Mobile Device Service'));
      expect(problem, contains('Start-Service'));
    });

    test(
      'POSIX policy reports a missing unix socket with the usbmuxd hint',
      () async {
        final linux = LinuxDeviceHost(runner);
        final missing =
            '${Directory.systemTemp.path}/xcross-no-usbmuxd-$pid.sock';
        final problem = await linux.deviceServiceProblem(missing);
        expect(problem, contains('usbmuxd'));
        expect(problem, contains('systemctl start usbmuxd'));
      },
    );

    test('POSIX policy accepts a listening unix socket', () async {
      final directory = Directory.systemTemp.createTempSync('usbmux_');
      final path = '${directory.path}/usbmuxd';
      final server = await ServerSocket.bind(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      server.listen((socket) => socket.destroy());
      try {
        expect(
          await LinuxDeviceHost(runner).deviceServiceProblem(path),
          isNull,
        );
        expect(await usbmuxServiceReachable('unix:$path'), isTrue);
      } finally {
        await server.close();
        directory.deleteSync(recursive: true);
      }
    }, skip: Platform.isWindows ? 'unix domain sockets are POSIX-only' : false);
  });

  test('listing ProductVersion becomes Device.osVersion', () {
    final devices = PymdDevices.parseDevices('''
[
  {"ConnectionType": "USB", "DeviceName": "iPhone X", "ProductVersion": "16.7.10", "UniqueDeviceID": "u1"},
  {"ConnectionType": "USB", "DeviceName": "Other", "UniqueDeviceID": "u2"}
]
''');
    expect(devices.first.osVersion, '16.7.10');
    expect(devices.last.osVersion, isNull);
  });
}
