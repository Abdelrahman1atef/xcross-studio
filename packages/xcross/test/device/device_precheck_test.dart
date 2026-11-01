// studio: 002 — device precheck before the build (#147).
import 'package:dart_mobile_device/shared/device/models/device.dart';
import 'package:dart_mobile_device/shared/errors/errors.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart';
import 'package:xcross/src/shared/errors/errors.dart';
import 'package:xcross/src/shared/models/pack_result.dart';
import 'package:xcross/src/target/iphone/device/core_device_launch_profile.dart';
import 'package:xcross/src/target/iphone/device/device_backend.dart';
import 'package:xcross/src/target/iphone/device/device_precheck.dart';
import 'package:xcross/src/target/iphone/device/device_run_operation.dart';

import 'test_log_output.dart';

void main() {
  const iphoneX = Device(
    name: 'iPhone X',
    udid: 'U16',
    type: ConnectionType.usb,
    osVersion: '14.8',
  );
  const modern = Device(name: 'Phone', udid: 'U17', type: ConnectionType.usb);

  late List<String> events;

  setUp(() => events = []);

  DevicePrecheck precheck({
    String? serviceProblem,
    Object resolve = modern,
    int? osMajor = 17,
  }) => DevicePrecheck(
    log: testLog(),
    serviceProblem: () async {
      events.add('service');
      return serviceProblem;
    },
    resolveDevice: ({required mode, selector}) async {
      events.add('resolve:${mode.name}');
      if (resolve is Device) return resolve;
      throw resolve as Exception;
    },
    osMajor: (device) async {
      events.add('version');
      return osMajor;
    },
  );

  Matcher coded(String code) => throwsA(
    isA<XcrossError>().having(
      (e) => e.message,
      'message',
      startsWith('[$code]'),
    ),
  );

  // studio: 005 - minimum is iOS 15 now; iOS 14 stands in for unsupported.
  test('AC-002-1 unsupported iOS is rejected before the build within 5 s', () async {
    final stopwatch = Stopwatch()..start();
    await expectLater(
      precheck(resolve: iphoneX).run(mode: DeviceSearchMode.all),
      throwsA(
        isA<XcrossError>().having(
          (e) => e.message,
          'message',
          allOf(
            startsWith('[device.ios_unsupported] iPhone X runs iOS 14.8'),
            contains('hint: '),
          ),
        ),
      ),
    );
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(events, ['service', 'resolve:all'], reason: 'listing version used');
  });

  test('AC-002-2 no device is device.not_found', () async {
    await expectLater(
      precheck(
        resolve: DeviceNotFoundError('No devices connected.'),
      ).run(mode: DeviceSearchMode.all),
      coded('device.not_found'),
    );
  });

  group('AC-002-3 host device service', () {
    const down = 'usbmuxd is not reachable at /var/run/usbmuxd. Start it.';

    test('USB search with the service down stops before resolving', () async {
      await expectLater(
        precheck(serviceProblem: down).run(mode: DeviceSearchMode.usb),
        throwsA(
          isA<XcrossError>().having(
            (e) => e.message,
            'message',
            '[device.host_service_unavailable] usbmuxd is not reachable at '
                '/var/run/usbmuxd.\nhint: Start it.',
          ),
        ),
      );
      expect(events, ['service']);
    });

    test(
      'default search, service down and no device: service is the cause',
      () async {
        await expectLater(
          precheck(
            serviceProblem: down,
            resolve: DeviceNotFoundError('No devices connected.'),
          ).run(mode: DeviceSearchMode.all),
          coded('device.host_service_unavailable'),
        );
      },
    );

    test(
      'default search, service down but a tunnel device exists: proceed',
      () async {
        final result = await precheck(
          serviceProblem: down,
        ).run(mode: DeviceSearchMode.all);
        expect(result.device, modern);
      },
    );

    test('Wi-Fi only search does not probe the service', () async {
      await precheck(serviceProblem: down).run(mode: DeviceSearchMode.wifi);
      expect(events, isNot(contains('service')));
    });
  });

  test('a hanging listing is device.query_timeout', () async {
    await expectLater(
      precheck(
        resolve: PymdTimeoutError('usbmux list timed out after 20s'),
      ).run(mode: DeviceSearchMode.all),
      coded('device.query_timeout'),
    );
  });

  test('an unreadable version warns and proceeds', () async {
    final result = await precheck(
      osMajor: null,
    ).run(mode: DeviceSearchMode.all);
    expect(result.osMajor, isNull);
    expect(events, ['service', 'resolve:all', 'version']);
  });

  test(
    'AC-002-4 run() reuses the prechecked device without resolving',
    () async {
      final backend = RecordingBackend(events);
      final operation = DeviceRunOperation(
        log: testLog(),
        backend: backend,
        osMajorVersion: (_) async => 17,
        terminate: ({required udid, required bundleId}) async {},
        launch:
            ({
              required udid,
              required bundleId,
              required profile,
              onRestartRequested,
            }) async => events.add('launch:$udid'),
      );
      await operation.run(
        pack: const PackResult(outputPath: '/build/A.app', bundleId: 'a.b'),
        selector: null,
        mode: DeviceSearchMode.all,
        launchProfile: const CoreDeviceLaunchProfile.native(),
        prechecked: const PrecheckedDevice(device: modern, osMajor: 17),
      );
      expect(events, ['install:U17', 'launch:U17']);
    },
  );
}

/// Records installs; resolving would be a bug once a device is prechecked.
@internal
final class RecordingBackend implements DeviceBackend {
  RecordingBackend(this.events);

  final List<String> events;

  @override
  Future<Device> resolveDevice({
    required DeviceSearchMode mode,
    String? selector,
  }) {
    events.add('resolve');
    throw StateError('must not resolve again');
  }

  @override
  Future<String> install(
    String appOrIpaPath, {
    required Device device,
    required String bundleId,
    String? projectRoot,
  }) async {
    events.add('install:${device.udid}');
    return bundleId;
  }
}
