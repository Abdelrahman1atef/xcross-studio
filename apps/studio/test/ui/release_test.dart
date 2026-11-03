// Feature 022: the Release and Archives destinations.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcross_studio/app/app.dart';
import 'package:xcross_studio/app/services.dart';
import 'package:xcross_studio/design_system/design_system.dart';
import 'package:xcross_studio/features/release/archives_page.dart';
import 'package:xcross_studio/src/cli/xcross_commands.dart';
import 'package:xcross_studio/src/host/host_platform.dart';
import 'package:xcross_studio/src/state/job.dart';
import 'package:xcross_studio/src/state/log_session.dart';
import 'package:xcross_studio/src/state/settings.dart';

import '../support/fake_launcher.dart';
import 'app_test.dart' show settle, go;

final _check = jsonEncode({
  'v': 1,
  'type': 'release_check',
  'input': 'Runner.ipa',
  'configuration': {'bundleId': 'com.example.app', 'version': '1.0.0'},
  'issues': [
    {
      'code': 'release.encryption_unset',
      'severity': 'warning',
      'message': 'ITSAppUsesNonExemptEncryption is not set.',
      'hint': 'Set uses_non_exempt_encryption.',
    },
    {
      'code': 'release.marketing_icon',
      'severity': 'error',
      'message': 'The App Store icon has an alpha channel.',
      'hint': 'Export it without alpha.',
    },
  ],
  'errors': 1,
  'warnings': 1,
});

final _gate = jsonEncode({
  'v': 1,
  'type': 'release_gate',
  'steps': [
    {'name': 'flutter analyze', 'passed': true, 'exitCode': 0, 'tail': []},
    {'name': 'flutter test', 'passed': true, 'exitCode': 0, 'tail': []},
  ],
});

String _publish(String event, Map<String, Object?> fields) =>
    jsonEncode({'v': 1, 'type': 'publish', 'event': event, ...fields});

final _testflight = jsonEncode({
  'v': 1,
  'type': 'testflight_status',
  'builds': [
    {
      'version': '1.0.0',
      'buildNumber': '8',
      'processingState': 'VALID',
      'internalBuildState': 'READY_FOR_BETA_TESTING',
      'externalBuildState': 'READY_FOR_BETA_SUBMISSION',
    },
  ],
});

Future<FakeLauncher> _pump(WidgetTester tester, String project) async {
  await tester.binding.setSurfaceSize(const Size(1600, 6000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final launcher = FakeLauncher(
    onStart: (process, arguments) async {
      final command = arguments.join(' ');
      if (command == XcrossCommands.releaseCheck().join(' ')) {
        process.out(_check);
      }
      if (command == XcrossCommands.releaseGate().join(' ')) process.out(_gate);
      if (command == XcrossCommands.publish().join(' ')) {
        process
          ..out(
            _publish('progress', {
              'part': 1,
              'parts': 2,
              'bytes': 50,
              'total': 100,
            }),
          )
          ..out(_publish('state', {'upload': 'PROCESSING'}))
          ..out(_publish('state', {'processing': 'VALID'}))
          ..out(_publish('published', {'processingState': 'VALID'}));
      }
      if (command == XcrossCommands.testflightStatus().join(' ')) {
        process.out(_testflight);
      }
      if (command.contains('--watch')) return;
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
    project = Directory.systemTemp.createTempSync('studio-022-');
    File('${project.path}/pubspec.yaml')
        .writeAsStringSync('name: demo\nversion: 1.0.0+7\n');
    Directory('${project.path}/ios').createSync();
  });
  tearDown(() => project.deleteSync(recursive: true));

  List<String> commands(FakeLauncher launcher) => [
    for (final start in launcher.starts) start.arguments.join(' '),
  ];

  testWidgets('AC-022-1 ten steps in the order of US-IOS-001', (tester) async {
    await _pump(tester, project.path);
    await go(tester, 'Release');
    for (final title in [
      '1. Readiness',
      '2. Version and build',
      '3. Signing',
      '4. Quality gate',
      '5. Archive and IPA',
      '6. Release check',
      '7. Upload and processing',
      '8. TestFlight',
      '9. App Store submission',
      '10. Release record and CI',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
  });

  testWidgets('AC-022-2 / AC-022-5 gate, build, check and upload run xcross', (
    tester,
  ) async {
    final launcher = await _pump(tester, project.path);
    await go(tester, 'Release');

    await tester.tap(find.widgetWithText(XButton, 'Run the gate'));
    await settle(tester);
    expect(find.text('flutter analyze'), findsOneWidget);

    await tester.tap(find.widgetWithText(XButton, 'Build for the App Store'));
    await settle(tester);
    expect(
      commands(launcher),
      contains(XcrossCommands.appStoreBuild(autoBuildNumber: true).join(' ')),
    );

    await tester.tap(find.widgetWithText(XButton, 'Check the IPA'));
    await settle(tester);
    expect(find.textContaining('[release.marketing_icon]'), findsOneWidget);
    expect(find.textContaining('1 errors, 1 warnings'), findsOneWidget);

    await tester.tap(find.widgetWithText(XButton, 'Upload'));
    await settle(tester);
    expect(find.textContaining('PROCESSING → VALID'), findsOneWidget);
    expect(find.text('Part 1 of 2'), findsOneWidget);
    // The release commands run in the project folder.
    expect(
      launcher.starts
          .where(
            (s) => const {'release', 'publish'}.contains(s.arguments.first),
          )
          .every((s) => s.workingDirectory == project.path),
      isTrue,
    );
  });

  testWidgets('AC-022-3 TestFlight builds, and submit asks first', (
    tester,
  ) async {
    final launcher = await _pump(tester, project.path);
    await go(tester, 'Release');
    await tester.tap(find.widgetWithText(XButton, 'Refresh').first);
    await settle(tester);
    expect(find.textContaining('1.0.0 (8)  VALID'), findsOneWidget);

    await tester.tap(find.widgetWithText(XButton, 'Submit for review'));
    await settle(tester);
    expect(find.text('Submit this version for App Review?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
    await settle(tester);
    expect(
      commands(launcher),
      isNot(contains(XcrossCommands.appStoreSubmit(dryRun: false).join(' '))),
    );
  });

  testWidgets('AC-022-4 the release record is shown', (tester) async {
    Directory('${project.path}/build/xcross-ios').createSync(recursive: true);
    File('${project.path}/build/xcross-ios/release.json').writeAsStringSync(
      jsonEncode({
        'app': 'Demo',
        'version': '1.0.0',
        'build': '8',
        'upload': {'state': 'COMPLETE'},
        'build_record': {'processingState': 'VALID'},
        'git': {'commit': 'abc123'},
      }),
    );
    await _pump(tester, project.path);
    await go(tester, 'Release');
    expect(
      find.textContaining(
        'Demo 1.0.0 (8) · upload COMPLETE · processing VALID',
      ),
      findsOneWidget,
    );
  });

  testWidgets('AC-022-7 Archives lists the archives xcross wrote', (
    tester,
  ) async {
    final archive = Directory(
      '${project.path}/build/xcross-ios/archive/Runner.xcarchive',
    )..createSync(recursive: true);
    File('${archive.path}/Info.plist').writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>ApplicationProperties</key><dict>
<key>CFBundleIdentifier</key><string>com.example.app</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>8</string>
<key>SigningIdentity</key><string>Apple Distribution: Example (TEAM)</string>
<key>Team</key><string>TEAM</string>
</dict>
<key>CreationDate</key><date>2026-11-03T10:00:00Z</date>
</dict></plist>
''');
    final entries = ArchiveEntry.list(project.path);
    expect(entries.single.build, '8');
    expect(entries.single.team, 'TEAM');

    await _pump(tester, project.path);
    await go(tester, 'Archives');
    expect(find.text('1.0.0 (8)'), findsOneWidget);
    expect(
      find.textContaining('Apple Distribution: Example (TEAM)'),
      findsOneWidget,
    );
  });
}
