import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcross_studio/src/cli/xcross_commands.dart';
import 'package:xcross_studio/src/host/host_platform.dart';
import 'package:xcross_studio/src/state/job.dart';
import 'package:xcross_studio/src/state/log_session.dart';
import 'package:xcross_studio/src/state/settings.dart';
import 'package:xcross_studio/src/ui/services.dart';
import 'package:xcross_studio/src/ui/studio_app.dart';

import '../support/fake_launcher.dart';

const _appInfo =
    '{"v":1,"type":"appinfo","bundleId":"com.example.app","name":"Demo",'
    '"version":"1.0","build":"3","executable":"Runner","signer":"development",'
    '"teamId":"TEAM123456","entitlements":{"aps-environment":"development"},'
    '"push":"development","associatedDomains":[]}';

const _device =
    '{"v":1,"type":"device","udid":"00008020-001A2B3C4D5E6F70",'
    '"name":"Test Phone","osVersion":"16.7.16","connection":"usb"}';

/// Lets the fake processes finish and pumps frames (spinners never
/// "settle", and stream shutdown needs real async turns).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<FakeLauncher> pumpStudio(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1500, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final launcher = FakeLauncher(
    onStart: (process, arguments) async {
      if (arguments.first == 'devices') process.out(_device);
      if (arguments.take(2).join(' ') == 'app info') process.out(_appInfo);
      await process.exit(0);
    },
  );
  final settings = Settings()..logApp = 'com.example.app';
  final jobs = JobCenter(
    launcher: launcher,
    invocation: () => const XcrossInvocation.binary(),
  );
  await tester.pumpWidget(
    StudioApp(
      services: (child) => Services(
        host: HostPlatform.current(),
        launcher: launcher,
        settings: settings,
        jobs: jobs,
        logs: LogSession(jobs, notifyEvery: Duration.zero),
        child: child,
      ),
    ),
  );
  await tester.pump();
  return launcher;
}

void main() {
  testWidgets('AC-008-9 every page opens from the rail', (tester) async {
    await pumpStudio(tester);
    expect(find.text('Before you start'), findsOneWidget);
    for (final (label, marker) in [
      ('Project', 'Flutter project'),
      ('Device', 'Install an app (.ipa)'),
      ('Device logs', 'App info'),
      ('Console', 'Commands'),
    ]) {
      await tester.tap(find.text(label).first);
      await settle(tester);
      expect(find.text(marker), findsWidgets, reason: label);
    }
  });

  testWidgets('AC-008-1 the device page lists the iPhone from devices --json', (
    tester,
  ) async {
    final launcher = await pumpStudio(tester);
    await tester.tap(find.text('Device').first);
    await settle(tester);
    await settle(tester);
    expect(
      launcher.starts.map((s) => s.arguments.join(' ')),
      contains('devices --json'),
    );
    expect(find.text('Test Phone'), findsOneWidget);
    expect(find.textContaining('iOS 16.7.16'), findsOneWidget);
    expect(find.textContaining('release/profile only'), findsOneWidget);
  });

  testWidgets('AC-008-7 app info shows push and associated-domain badges', (
    tester,
  ) async {
    await pumpStudio(tester);
    await tester.tap(find.text('Device logs').first);
    await settle(tester);
    await tester.tap(find.text('Read installed app info'));
    await settle(tester);
    expect(find.textContaining('Demo 1.0'), findsOneWidget);
    expect(
      find.textContaining('Push entitlement  development'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_circle), findsWidgets);
    expect(find.textContaining('Associated domains  none'), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsOneWidget);
  });

  testWidgets('FR-001 "Run from source" shows the repository field', (
    tester,
  ) async {
    await pumpStudio(tester);
    expect(find.text('XCross Studio repository folder'), findsNothing);
    await tester.tap(find.text('Run from source'));
    await settle(tester);
    expect(find.text('XCross Studio repository folder'), findsOneWidget);
    await tester.tap(find.text('Installed xcross'));
    await settle(tester);
    expect(find.text('xcross executable'), findsOneWidget);
  });

  test('AC-008-8 the GUI never imports the xcross packages', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final package in [
      'xcross:',
      'studio_ext:',
      'cli_kit:',
      'dart_mobile_device:',
      'apple_developer_kit:',
    ]) {
      expect(pubspec, isNot(contains('  $package')), reason: package);
    }
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(matches(RegExp(r"import 'package:(xcross|studio_ext|cli_kit)/"))),
        reason: file.path,
      );
    }
  });
}
