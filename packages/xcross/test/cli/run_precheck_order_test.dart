// studio: 002 — the device precheck runs before the build (#147).
import 'package:args/command_runner.dart';
import 'package:dart_mobile_device/shared/device/models/device.dart';
import 'package:test/test.dart';
import 'package:xcross/src/composition/cli/compose_run_command.dart';
import 'package:xcross/src/composition/cli/flutter_run_command.dart';
import 'package:xcross/src/shared/diagnostics/xcross_diagnostics.dart';
import 'package:xcross/src/shared/errors/errors.dart';
import 'package:xcross/src/shared/models/pack_result.dart';
import 'package:xcross/src/target/iphone/device/device_precheck.dart';

import '../log_fixture.dart';
import 'runtime_fixture.dart';

void main() {
  const device = Device(name: 'Phone', udid: 'U1', type: ConnectionType.usb);
  const pack = PackResult(outputPath: 'build/A.app', bundleId: 'a.b');

  late List<String> events;
  setUp(() => events = []);

  Future<PrecheckedDevice?> okPrecheck({
    required DeviceSearchMode mode,
    String? selector,
  }) {
    events.add('precheck:${selector ?? '-'}:${mode.name}');
    return Future.value(const PrecheckedDevice(device: device, osMajor: 17));
  }

  Future<PrecheckedDevice?> failingPrecheck({
    required DeviceSearchMode mode,
    String? selector,
  }) {
    events.add('precheck');
    return Future.error(
      codedError(XcrossCodes.deviceIosUnsupported, 'Phone runs iOS 16.'),
    );
  }

  CommandRunner<void> flutterRunner(FlutterRunPrecheck precheck) {
    final application = testApplication();
    return CommandRunner<void>('xcross', 'test')..addCommand(
      FlutterRunCommand.withSeams(
        application.runtime,
        application.pymd,
        sockets: application.sockets,
        precheck: precheck,
        pack: (options) async {
          events.add('pack');
          return pack;
        },
        runDevice:
            ({
              required pack,
              required selector,
              required mode,
              required launchProfile,
            }) async => events.add('run'),
      ),
    );
  }

  CommandRunner<void> composeRunner(ComposeRunPrecheck precheck) =>
      CommandRunner<void>('xcross', 'test')..addCommand(
        ComposeRunCommand.withSeams(
          projectRoot: '/test/project',
          log: testLog(),
          files: testRuntime().host.fileSystem,
          precheck: precheck,
          packOperation:
              ({
                required options,
                required requireRunnableApp,
                required targetPlatform,
              }) async {
                events.add('pack');
                return pack;
              },
          runDevice:
              ({
                required pack,
                required selector,
                required mode,
                required launchProfile,
                onRestartRequested,
              }) async => events.add('run'),
        ),
      );

  test('AC-002-4 flutter run prechecks once, before the build', () async {
    await flutterRunner(
      okPrecheck,
    ).run(['run', '--profile', '-u', 'U1', '--usb']);
    expect(events, ['precheck:U1:usb', 'pack', 'run']);
  });

  test('AC-002-1 flutter run: a failing precheck means no build', () async {
    await expectLater(
      flutterRunner(failingPrecheck).run(['run']),
      throwsA(isA<XcrossError>()),
    );
    expect(events, ['precheck']);
  });

  test('AC-002-4 compose run prechecks once, before the build', () async {
    await composeRunner(okPrecheck).run(['run', '-d', 'Phone']);
    expect(events, ['precheck:Phone:all', 'pack', 'run']);
  });

  test('AC-002-1 compose run: a failing precheck means no build', () async {
    await expectLater(
      composeRunner(failingPrecheck).run(['run']),
      throwsA(isA<XcrossError>()),
    );
    expect(events, ['precheck']);
  });
}
