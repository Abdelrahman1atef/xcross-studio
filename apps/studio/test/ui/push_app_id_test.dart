// Feature 016: the App ID switch and push readiness.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcross_studio/app/app.dart';
import 'package:xcross_studio/app/services.dart';
import 'package:xcross_studio/design_system/design_system.dart';
import 'package:xcross_studio/features/signing/app_id_card.dart';
import 'package:xcross_studio/src/cli/xcross_commands.dart';
import 'package:xcross_studio/src/cli/xcross_events.dart';
import 'package:xcross_studio/src/host/host_platform.dart';
import 'package:xcross_studio/src/state/job.dart';
import 'package:xcross_studio/src/state/log_session.dart';
import 'package:xcross_studio/src/state/readiness.dart';
import 'package:xcross_studio/src/state/settings.dart';

import '../support/fake_launcher.dart';
import 'app_test.dart' show settle, go;

String _bundleId(String? saved) => jsonEncode({
  'v': 1,
  'type': 'bundle_id',
  'bundleId': 'com.example.app',
  'saved': saved,
  'override': null,
  'settingsPath': 'pubspec.yaml',
  'next': saved ?? 'original',
});

String _check(String name, String status, String message) => jsonEncode({
  'v': 1,
  'type': 'check',
  'section': 'Push notifications',
  'name': name,
  'status': status,
  'message': message,
  'path': null,
});

Future<FakeLauncher> _pump(
  WidgetTester tester, {
  required String project,
  List<String> doctor = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(1600, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  var saved = 'prefixed';
  final launcher = FakeLauncher(
    onStart: (process, arguments) async {
      final command = arguments.join(' ');
      if (command == 'flutter doctor') doctor.forEach(process.out);
      if (command == 'project bundle-id original --json') saved = 'original';
      if (command.startsWith('project bundle-id')) {
        process.out(_bundleId(saved));
      }
      await process.exit(0);
    },
  );
  final settings = Settings()
    ..wizardDismissed = true
    ..projectPath = project;
  final jobs = JobCenter(
    launcher: launcher,
    invocation: () => const XcrossInvocation.binary(),
  );
  await tester.pumpWidget(
    StudioApp(
      services: StudioServices(
        host: HostPlatform.current(),
        launcher: launcher,
        settings: settings,
        jobs: jobs,
        logs: LogSession(jobs, notifyEvery: Duration.zero),
      ),
    ),
  );
  await settle(tester);
  return launcher;
}

void main() {
  late Directory project;
  setUp(() {
    project = Directory.systemTemp.createTempSync('studio-016-');
    File('${project.path}/pubspec.yaml').writeAsStringSync('name: demo\n');
    Directory('${project.path}/ios').createSync();
  });
  tearDown(() => project.deleteSync(recursive: true));

  test('AC-016-3 the bundle-id event and command', () {
    final event = XcrossEvent.tryParse(_bundleId(null))! as BundleIdStatus;
    expect(event.bundleId, 'com.example.app');
    expect(event.saved, isNull);
    expect(event.usesRealAppId, isTrue);
    expect(XcrossCommands.projectBundleId(), [
      'project',
      'bundle-id',
      '--json',
    ]);
    expect(XcrossCommands.projectBundleId(realAppId: false), [
      'project',
      'bundle-id',
      'prefixed',
      '--json',
    ]);
  });

  testWidgets('AC-016-3 Signing shows the prefixed App ID and switches it', (
    tester,
  ) async {
    final launcher = await _pump(tester, project: project.path);
    await go(tester, 'Signing');
    expect(find.byType(AppIdCard), findsOneWidget);
    expect(find.text('Prefixed App ID'), findsOneWidget);

    await tester.tap(find.widgetWithText(XButton, 'Use the real App ID'));
    await settle(tester);
    expect(find.textContaining('Push notifications, Firebase'), findsOneWidget);
    await tester.tap(find.widgetWithText(XButton, 'Use the real App ID').last);
    await settle(tester);

    final commands = [
      for (final start in launcher.starts) start.arguments.join(' '),
    ];
    expect(commands, contains('project bundle-id original --json'));
    expect(
      launcher.starts
          .where((s) => s.arguments.first == 'project')
          .every((s) => s.workingDirectory == project.path),
      isTrue,
    );
    expect(find.text('Real App ID'), findsOneWidget);
  });

  group('AC-016-7 push readiness', () {
    DoctorCheckResult check(String name, String status) =>
        DoctorCheckResult.fromJson(
          jsonDecode(_check(name, status, 'm')) as Map<String, Object?>,
        );

    test('push checks form their own area, not a setup problem', () {
      expect(
        ReadinessController.areaOf(check('Push App ID', 'failure')),
        ReadinessArea.push,
      );
      expect(
        ReadinessController.areaOf(check('Firebase config', 'success')),
        ReadinessArea.push,
      );
    });

    testWidgets('Overview shows the push card only with push checks', (
      tester,
    ) async {
      await _pump(
        tester,
        project: project.path,
        doctor: [
          _check(
            'Push App ID',
            'failure',
            'Signed as XCR-<identity>.com.example.app (saved); run '
                '`xcross project bundle-id original`.',
          ),
        ],
      );
      await go(tester, 'Overview');
      final services = Services.of(tester.element(find.byType(Scaffold).first));
      services.readiness.runDoctor();
      await settle(tester);
      expect(find.text('Push notifications'), findsOneWidget);
      expect(services.readiness.needsSetup, isFalse);
    });

    testWidgets('no push checks, no card', (tester) async {
      await _pump(tester, project: project.path);
      await go(tester, 'Overview');
      expect(find.text('Push notifications'), findsNothing);
    });
  });
}
