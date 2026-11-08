// Feature 032: the Project > Plugins tab prepares a fresh iOS project through
// `xcross ios prepare` and shows what a build would leave out.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcross_studio/app/app.dart';
import 'package:xcross_studio/app/services.dart';
import 'package:xcross_studio/design_system/design_system.dart';
import 'package:xcross_studio/src/cli/xcross_commands.dart';
import 'package:xcross_studio/src/cli/xcross_events.dart';
import 'package:xcross_studio/src/host/host_platform.dart';
import 'package:xcross_studio/src/state/job.dart';
import 'package:xcross_studio/src/state/log_session.dart';
import 'package:xcross_studio/src/state/settings.dart';

import '../support/fake_launcher.dart';
import 'app_test.dart' show go, settle;

String _json(Map<String, Object?> event) => jsonEncode({'v': 1, ...event});

Map<String, Object?> _report({required bool leaveOut, bool ready = true}) => {
  'type': 'ios_prepare',
  'ready': ready,
  'steps': [
    {
      'id': 'project',
      'title': 'iOS project',
      'state': 'ok',
      'detail': 'ios/ has a Runner project.',
      'hint': null,
    },
    {
      'id': 'plugins',
      'title': 'Plugins',
      'state': leaveOut ? 'warning' : 'ok',
      'detail': leaveOut
          ? '2 plugins, the native code of vendored is left out.'
          : '2 plugins.',
      'hint': null,
    },
  ],
  'plugins': [
    {
      'name': 'modern',
      'version': '1.0.0',
      'kind': 'swiftpm',
      'state': 'ready',
      'detail': 'swiftpm',
    },
    {
      'name': 'vendored',
      'version': '1.0.0',
      'kind': 'podspec_only',
      'state': leaveOut ? 'left_out' : 'drafted',
      'detail': leaveOut ? 'podspec only, no Swift package for: SomeVendorSDK' : 'podspec only: drafted xcross_overrides/vendored/1.0.0/Package.swift',
    },
  ],
  'leftOut': [if (leaveOut) 'vendored'],
  'bundleId': 'com.example.fresh',
  'deploymentTarget': '13.0',
  'permissionMacros': <String, String>{},
};

void main() {
  late Directory project;
  setUp(() {
    project = Directory.systemTemp.createTempSync('studio-032-');
    File('${project.path}/pubspec.yaml').writeAsStringSync('name: demo\n');
    Directory('${project.path}/ios').createSync();
  });
  tearDown(() => project.deleteSync(recursive: true));

  Future<FakeLauncher> pump(
    WidgetTester tester, {
    required Map<String, Object?>? reply,
    int exitCode = 0,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1600, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final launcher = FakeLauncher(
      onStart: (process, arguments) async {
        if (arguments.first == 'plugin') {
          process.out(_json({'type': 'plugin_status', 'plugins': <Object?>[]}));
        }
        if (arguments.first == 'ios' && reply != null) {
          process.out(_json(reply));
        }
        await process.exit(arguments.first == 'ios' ? exitCode : 0);
      },
    );
    final jobs = JobCenter(
      launcher: launcher,
      invocation: () => const XcrossInvocation.binary(),
    );
    await tester.pumpWidget(
      StudioApp(
        services: StudioServices(
          host: HostPlatform.current(),
          launcher: launcher,
          settings: Settings()
            ..wizardDismissed = true
            ..projectPath = project.path,
          jobs: jobs,
          logs: LogSession(jobs, notifyEvery: Duration.zero),
        ),
      ),
    );
    await settle(tester);
    await go(tester, 'Project');
    await tester.tap(find.text('Plugins'));
    await settle(tester, 5);
    return launcher;
  }

  List<List<String>> prepares(FakeLauncher launcher) => [
    for (final start in launcher.starts)
      if (start.arguments.first == 'ios') start.arguments,
  ];

  testWidgets('AC-032-8 the button runs ios prepare on the open project', (
    tester,
  ) async {
    final launcher = await pump(tester, reply: _report(leaveOut: false));
    expect(find.text('Get this project ready for iOS'), findsOneWidget);
    expect(prepares(launcher), isEmpty, reason: 'nothing runs by itself');
    await tester.tap(find.widgetWithText(XButton, 'Prepare iOS project'));
    await settle(tester, 8);
    expect(prepares(launcher), [
      ['ios', 'prepare', '--json', '--project', project.path],
    ]);
    expect(find.textContaining('ios/ has a Runner project.'), findsOneWidget);
    expect(find.textContaining('A build leaves out'), findsNothing);
  });

  testWidgets('AC-032-9 a plugin a build would leave out is named', (
    tester,
  ) async {
    await pump(tester, reply: _report(leaveOut: true));
    await tester.tap(find.widgetWithText(XButton, 'Prepare iOS project'));
    await settle(tester, 8);
    expect(
      find.text('A build leaves out the native code of vendored'),
      findsOneWidget,
    );
    expect(
      find.textContaining('no Swift package for: SomeVendorSDK'),
      findsOneWidget,
    );
  });

  testWidgets('AC-032-10 a project that cannot be prepared says so', (
    tester,
  ) async {
    await pump(tester, reply: null, exitCode: 1);
    await tester.tap(find.widgetWithText(XButton, 'Prepare iOS project'));
    await settle(tester, 8);
    expect(find.text('Could not prepare the project'), findsOneWidget);
  });

  test('AC-032-11 the report is read from the CLI line', () {
    final event = XcrossEvent.tryParse(_json(_report(leaveOut: true)));
    expect(event, isA<IosPrepareReport>());
    final report = event! as IosPrepareReport;
    expect(report.ready, isTrue);
    expect(report.leftOut.single.name, 'vendored');
    expect(report.bundleId, 'com.example.fresh');
    expect(XcrossCommands.iosPrepare(project: 'p', pub: false), [
      'ios',
      'prepare',
      '--json',
      '--project',
      'p',
      '--no-pub',
    ]);
  });
}
