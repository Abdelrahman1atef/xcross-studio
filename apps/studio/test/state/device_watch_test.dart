// Feature 017: the device list follows plug and unplug live.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcross_studio/app/app.dart';
import 'package:xcross_studio/app/services.dart';
import 'package:xcross_studio/src/cli/xcross_commands.dart';
import 'package:xcross_studio/src/cli/xcross_events.dart';
import 'package:xcross_studio/src/host/host_platform.dart';
import 'package:xcross_studio/src/state/devices.dart';
import 'package:xcross_studio/src/state/job.dart';
import 'package:xcross_studio/src/state/log_session.dart';
import 'package:xcross_studio/src/state/settings.dart';

import '../support/fake_launcher.dart';
import '../ui/app_test.dart' show settle;

String _snapshot(List<String> names) => jsonEncode({
  'v': 1,
  'type': 'devices',
  'devices': [
    for (final name in names)
      {
        'udid': 'UDID-$name',
        'name': name,
        'osVersion': '16.7.16',
        'connection': 'usb',
      },
  ],
});

void main() {
  test('AC-017-5 the snapshot event and the watch command', () {
    final event = XcrossEvent.tryParse(_snapshot(['Phone']))! as DeviceSnapshot;
    expect(event.devices.single.name, 'Phone');
    expect(XcrossCommands.devicesWatch(), ['devices', '--watch', '--json']);
  });

  test('AC-017-5 snapshots replace the list; a lone device is selected; '
      'the watch is not a console job', () async {
    FakeProcess? watchProcess;
    final launcher = FakeLauncher(
      onStart: (process, arguments) {
        if (arguments.contains('--watch')) watchProcess = process;
      },
    );
    final jobs = JobCenter(
      launcher: launcher,
      invocation: () => const XcrossInvocation.binary(),
    );
    final settings = Settings();
    final controller = DeviceController(jobs, settings)..watch();
    await Future<void>.delayed(Duration.zero);
    expect(controller.watching, isTrue);
    expect(jobs.jobs, isEmpty);

    watchProcess!.out(_snapshot(['Phone']));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.devices!.single.name, 'Phone');
    expect(settings.udid, 'UDID-Phone');

    watchProcess!
      ..out(
        jsonEncode({
          'v': 1,
          'type': 'notice',
          'message': 'The device service is not reachable; retrying…',
        }),
      )
      ..out(_snapshot([]));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.devices, isEmpty);
    expect(controller.serviceDown, isFalse, reason: 'a snapshot clears it');

    watchProcess!.out(
      jsonEncode({
        'v': 1,
        'type': 'notice',
        'message': 'The device service is not reachable; retrying…',
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.serviceDown, isTrue);
    await watchProcess!.exit(0);
    controller.dispose();
  });

  test(
    'AC-017-5 a watch that ends at once (older CLI) is not restarted',
    () async {
      var watches = 0;
      final launcher = FakeLauncher(
        onStart: (process, arguments) async {
          if (arguments.contains('--watch')) watches++;
          await process.exit(64);
        },
      );
      final controller = DeviceController(
        JobCenter(
          launcher: launcher,
          invocation: () => const XcrossInvocation.binary(),
        ),
        Settings(),
        restartDelay: const Duration(milliseconds: 5),
      )..watch();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(watches, 1);
      controller.dispose();
    },
  );

  test('AC-017-5 a watch that ran long is restarted', () async {
    var watches = 0;
    var now = DateTime(2026, 11, 3, 12);
    final launcher = FakeLauncher(
      onStart: (process, arguments) async {
        if (!arguments.contains('--watch')) return;
        watches++;
        if (watches == 1) {
          now = now.add(const Duration(minutes: 1));
          await process.exit(1);
        }
      },
    );
    final controller = DeviceController(
      JobCenter(
        launcher: launcher,
        invocation: () => const XcrossInvocation.binary(),
      ),
      Settings(),
      restartDelay: const Duration(milliseconds: 5),
      clock: () => now,
    )..watch();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(watches, 2);
    controller.dispose();
  });

  testWidgets('AC-017-6 the top-bar badge follows the watch', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    FakeProcess? watchProcess;
    final launcher = FakeLauncher(
      onStart: (process, arguments) async {
        if (arguments.contains('--watch')) {
          watchProcess = process;
          return;
        }
        await process.exit(0);
      },
    );
    final settings = Settings()..wizardDismissed = true;
    final jobs = JobCenter(
      launcher: launcher,
      invocation: () => const XcrossInvocation.binary(),
    );
    final services = StudioServices(
      host: HostPlatform.current(),
      launcher: launcher,
      settings: settings,
      jobs: jobs,
      logs: LogSession(jobs, notifyEvery: Duration.zero),
    );
    await tester.pumpWidget(StudioApp(services: services));
    await settle(tester);
    expect(find.text('Plug in an iPhone'), findsOneWidget);

    watchProcess!.out(_snapshot(['Test Phone']));
    await settle(tester);
    expect(find.text('iPhone: Test Phone'), findsOneWidget);

    watchProcess!.out(
      jsonEncode({
        'v': 1,
        'type': 'notice',
        'message': 'The device service is not reachable; retrying…',
      }),
    );
    await settle(tester);
    expect(find.text('Device service not reachable'), findsOneWidget);

    watchProcess!.out(_snapshot([]));
    await settle(tester);
    expect(find.text('Plug in an iPhone'), findsOneWidget);
    await watchProcess!.exit(0);
    await settle(tester);
  });
}
