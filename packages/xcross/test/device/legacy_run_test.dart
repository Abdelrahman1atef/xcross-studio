// studio: 005 — iOS 15/16 install and launch.
import 'dart:io';

import 'package:cli_kit/shared/logging/logging.dart';
import 'package:cli_kit/shared/process/process_models.dart';
import 'package:dart_mobile_device/shared/device/models/device.dart';
import 'package:dart_mobile_device/shared/errors/errors.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/models/pack_result.dart';
import 'package:xcross/src/target/iphone/device/core_device_launch_profile.dart';
import 'package:xcross/src/target/iphone/device/ddi_locator.dart';
import 'package:xcross/src/target/iphone/device/device_backend.dart';
import 'package:xcross/src/target/iphone/device/device_precheck.dart';
import 'package:xcross/src/target/iphone/device/device_run_operation.dart';
import 'package:xcross/src/target/iphone/device/legacy_device_launcher.dart';

import '../setup/host_ops_residual_fixtures.dart';
import 'test_log_output.dart';

void main() {
  const iphoneX = Device(
    name: 'iPhone X',
    udid: 'U16',
    type: ConnectionType.usb,
    osVersion: '16.7.16',
  );

  test('AC-005-1 iOS 16 is accepted and marked legacy', () async {
    final result = await DevicePrecheck(
      log: testLog(),
      serviceProblem: () async => null,
      resolveDevice: ({required mode, selector}) async => iphoneX,
      osMajor: (_) async => null,
    ).run(mode: DeviceSearchMode.usb);
    expect(result.legacy, isTrue);
    expect(result.osVersion, '16.7.16');
    expect(
      const PrecheckedDevice(device: iphoneX, osMajor: 17).legacy,
      isFalse,
    );
  });

  group('LegacyDeviceLauncher', () {
    late List<String> commands;
    PymdCommand fake({String? mountError, String? launchError}) =>
        (args, {timeout}) async {
          commands.add(args.take(3).join(' '));
          if (args.first == 'mounter' && mountError != null) {
            throw TunnelError(mountError);
          }
          if (args.first == 'developer' && launchError != null) {
            throw TunnelError(launchError);
          }
          return const CapturedProcess(0, '', '');
        };
    setUp(() => commands = []);

    test('AC-005-2 mounts the user image and launches', () async {
      final launched = await LegacyDeviceLauncher(run: fake(), log: testLog())
          .launch(
            udid: 'U16',
            bundleId: 'a.b',
            osVersion: '16.7.16',
            ddi: (image: '/d/DeveloperDiskImage.dmg', signature: '/d/x.sig'),
          );
      expect(launched, isTrue);
      expect(commands, [
        'mounter mount-developer /d/DeveloperDiskImage.dmg',
        'developer dvt launch',
      ]);
    });

    test('an already mounted image counts as mounted', () async {
      final launched =
          await LegacyDeviceLauncher(
            run: fake(
              mountError: 'AlreadyMountedError: image is already mounted',
            ),
            log: testLog(),
          ).launch(
            udid: 'U16',
            bundleId: 'a.b',
            osVersion: '16.7',
            ddi: (image: '/d/i.dmg', signature: '/d/i.dmg.signature'),
          );
      expect(launched, isTrue);
    });

    test(
      'AC-005-3 without an image: no device commands, tap guidance',
      () async {
        final output = TestLogOutput();
        final launched = await LegacyDeviceLauncher(
          run: fake(),
          log: Log(output: output),
        ).launch(udid: 'U16', bundleId: 'a.b', osVersion: '16.7', ddi: null);
        expect(launched, isFalse);
        expect(commands, isEmpty);
        final text = output.messages.join('\n');
        expect(text, contains('Tap the app icon'));
        expect(text, contains('xcross logs --app a.b'));
      },
    );

    test('a failed mount falls back to guidance instead of failing', () async {
      final launched =
          await LegacyDeviceLauncher(
            run: fake(mountError: 'ImageMountFailed: wrong version'),
            log: testLog(),
          ).launch(
            udid: 'U16',
            bundleId: 'a.b',
            osVersion: '16.7',
            ddi: (image: '/d/i.dmg', signature: '/d/i.dmg.signature'),
          );
      expect(launched, isFalse);
      expect(commands, ['mounter mount-developer /d/i.dmg']);
    });
  });

  test('AC-005-3 legacy run installs, then uses the legacy launcher', () async {
    final events = <String>[];
    final operation = DeviceRunOperation(
      log: testLog(),
      backend: RecordingInstallBackend(events),
      osMajorVersion: (_) async => 16,
      terminate: ({required udid, required bundleId}) async =>
          events.add('terminate'),
      launch:
          ({
            required udid,
            required bundleId,
            required profile,
            onRestartRequested,
          }) async => events.add('coredevice launch'),
      legacyLauncher: LegacyDeviceLauncher(
        run: (args, {timeout}) async {
          events.add('pymd ${args.first}');
          return const CapturedProcess(0, '', '');
        },
        log: testLog(),
      ),
    );
    await operation.run(
      pack: const PackResult(outputPath: '/b/A.app', bundleId: 'a.b'),
      selector: null,
      mode: DeviceSearchMode.usb,
      launchProfile: const CoreDeviceLaunchProfile.native(),
      prechecked: const PrecheckedDevice(
        device: iphoneX,
        osMajor: 16,
        osVersion: '16.7.16',
      ),
    );
    expect(events, ['install:U16'], reason: 'no image: guidance only');
  });

  group('DdiLocator', () {
    late Directory temp;
    late ResidualFileSystem files;
    setUp(() {
      temp = Directory.systemTemp.createTempSync('xcross-ddi-');
      files = ResidualFileSystem('/home/dev', temp);
    });
    tearDown(() => temp.deleteSync(recursive: true));

    void image(String dir, {bool signature = true}) {
      for (final name in [
        'DeveloperDiskImage.dmg',
        if (signature) 'DeveloperDiskImage.dmg.signature',
      ]) {
        files.file('$dir/$name')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('');
      }
    }

    DdiLocator locator([
      Map<String, String> env = const {'HOME': '/home/dev'},
    ]) => DdiLocator(fileSystem: files, paths: p.posix, environment: env);

    test('AC-005-2 finds ~/.xcross/DeviceSupport/<major.minor>', () {
      image('/home/dev/.xcross/DeviceSupport/16.4 (20E247)');
      image('/home/dev/.xcross/DeviceSupport/15.0');
      expect(
        locator().find('16.7.16')!.image,
        '/home/dev/.xcross/DeviceSupport/16.4 (20E247)/DeveloperDiskImage.dmg',
      );
      expect(locator().find('17.0'), isNull);
    });

    test('--ddi wins; an image without its signature is ignored', () {
      image('/home/dev/explicit');
      image('/home/dev/env/16.7', signature: false);
      expect(
        locator().find('16.7', explicitDir: '/home/dev/explicit')!.image,
        '/home/dev/explicit/DeveloperDiskImage.dmg',
      );
      expect(
        locator({
          'XCROSS_DDI_DIR': '/home/dev/env',
          'HOME': '/home/dev',
        }).find('16.7'),
        isNull,
      );
    });
  });
}

/// Records installs; resolving is not expected (the device is prechecked).
@internal
final class RecordingInstallBackend implements DeviceBackend {
  RecordingInstallBackend(this.events);

  final List<String> events;

  @override
  Future<Device> resolveDevice({
    required DeviceSearchMode mode,
    String? selector,
  }) => throw StateError('must not resolve');

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
