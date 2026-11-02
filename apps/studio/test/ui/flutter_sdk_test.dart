// Feature 014: a Flutter with an iOS compiler for this computer, fixed with
// one click instead of a raw gen_snapshot error.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcross_studio/app/app.dart';
import 'package:xcross_studio/app/services.dart';
import 'package:xcross_studio/design_system/design_system.dart';
import 'package:xcross_studio/features/common/flutter_sdk_fix.dart';
import 'package:xcross_studio/src/cli/xcross_commands.dart';
import 'package:xcross_studio/src/cli/xcross_events.dart';
import 'package:xcross_studio/src/host/host_platform.dart';
import 'package:xcross_studio/src/state/job.dart';
import 'package:xcross_studio/src/state/log_session.dart';
import 'package:xcross_studio/src/state/readiness.dart';
import 'package:xcross_studio/src/state/settings.dart';

import '../support/fake_launcher.dart';
import 'app_test.dart' show settle, go;

/// The CLI's coded error, as `XCROSS_EVENTS=ndjson` reports it.
final _buildError = jsonEncode({
  'v': 1,
  'type': 'error',
  'code': 'build.gen_snapshot_unavailable',
  'message':
      'No prebuilt iOS AOT compiler (gen_snapshot) is available for Flutter '
      '3.47.8 (engine cf636b1d).\nFlutter publishes this compiler for macOS '
      'only; xcross downloads Linux and Windows builds from '
      'https://github.com/arxdeus/xcross_gen_snapshot/releases.\nNewest '
      'Flutter with a published compiler for windows-x64: 3.47.6.',
  'hint':
      'Run `xcross flutter sdk auto` to install Flutter 3.47.6 just for iOS '
      'builds (your own Flutter is not changed).',
});

String _check(String name, String status, String message) => jsonEncode({
  'v': 1,
  'type': 'check',
  'section': 'Flutter project',
  'name': name,
  'status': status,
  'message': message,
  'path': null,
});

const _missingMessage =
    'Flutter 3.47.8 has no published iOS release compiler for this computer; '
    'newest with one: 3.47.6. Fix: `xcross flutter sdk auto` (your own '
    'Flutter is not changed).';

String _sdks({required bool managed, String compiler = 'available'}) =>
    jsonEncode({
      'v': 1,
      'type': 'flutter_sdks',
      'platform': 'windows-x64',
      'active': {
        'root': managed ? r'C:\x\flutter-sdks\3.47.6' : r'D:\flutter',
        'version': managed ? '3.47.6' : '3.47.8',
        'managed': managed,
        'compiler': compiler,
        'detail': null,
      },
      'managed': managed
          ? [
              {'version': '3.47.6', 'path': r'C:\x', 'state': 'ready'},
            ]
          : [],
      'available': ['3.47.6', '3.47.5'],
      'catalogStale': false,
      'catalogError': null,
      'suggested': compiler == 'missing' ? '3.47.6' : null,
    });

Future<FakeLauncher> _pump(
  WidgetTester tester, {
  required String project,
  List<String> doctor = const [],
  bool managed = false,
  String compiler = 'available',
}) async {
  await tester.binding.setSurfaceSize(const Size(1600, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final launcher = FakeLauncher(
    onStart: (process, arguments) async {
      final command = arguments.join(' ');
      if (command == 'flutter doctor') doctor.forEach(process.out);
      if (command.startsWith('flutter build')) {
        process
          ..out(_buildError)
          ..out('{"v":1,"type":"done","exitCode":1}');
        await process.exit(1);
        return;
      }
      if (command == 'flutter sdk auto --yes') {
        process
          ..out(
            '{"v":1,"type":"step","name":"Downloading Flutter 3.47.6",'
            '"status":"start"}',
          )
          ..out(
            '{"v":1,"type":"step","name":"Downloading Flutter 3.47.6",'
            '"status":"done","elapsedMs":1200}',
          )
          ..out('{"v":1,"type":"done","exitCode":0}');
      }
      if (command == 'flutter sdk list --json') {
        process.out(_sdks(managed: managed, compiler: compiler));
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

List<String> _commands(FakeLauncher launcher) => [
  for (final start in launcher.starts) start.arguments.join(' '),
];

void main() {
  late Directory project;
  setUp(() {
    project = Directory.systemTemp.createTempSync('studio-014-');
    File('${project.path}/pubspec.yaml').writeAsStringSync('name: demo\n');
    Directory('${project.path}/ios').createSync();
  });
  tearDown(() => project.deleteSync(recursive: true));

  group('AC-014-7 the problem in plain words', () {
    test('versions are read from the build error and the doctor check', () {
      final fromBuild = GenSnapshotProblem.fromText(
        'error: [build.gen_snapshot_unavailable] No prebuilt iOS AOT compiler '
        '(gen_snapshot) is available for Flutter 3.47.8 (engine cf636b1d).\n'
        'Newest Flutter with a published compiler for windows-x64: 3.47.6.',
      );
      expect(fromBuild.current, '3.47.8');
      expect(fromBuild.suggested, '3.47.6');
      expect(fromBuild.explanation, contains('is newer than the iOS compiler'));
      expect(fromBuild.explanation, contains('need Flutter 3.47.6'));
      expect(fromBuild.explanation, contains('about 1 GB'));
      expect(fromBuild.explanation, contains('not changed'));
      final fromDoctor = GenSnapshotProblem.fromCheck(
        DoctorCheckResult.fromJson(
          jsonDecode(
            _check('AOT compiler (release)', 'failure', _missingMessage),
          ) as Map<String, Object?>,
        ),
      )!;
      expect(fromDoctor.current, '3.47.8');
      expect(fromDoctor.suggested, '3.47.6');
    });

    test('only the release compiler check counts for readiness', () {
      DoctorCheckResult check(String name) => DoctorCheckResult.fromJson(
        jsonDecode(_check(name, 'failure', _missingMessage))
            as Map<String, Object?>,
      );
      expect(
        ReadinessController.areaOf(check('AOT compiler (release)')),
        ReadinessArea.iosCompiler,
      );
      expect(ReadinessController.areaOf(check('AOT compiler (profile)')), null);
    });
  });

  testWidgets(
    'AC-014-8 a failed release build offers the one-click fix, then builds '
    'again',
    (tester) async {
      final launcher = await _pump(tester, project: project.path);
      await go(tester, 'Build & Run');
      await tester.tap(find.widgetWithText(XButton, 'Build IPA'));
      await settle(tester);
      expect(find.byType(FlutterSdkFixCard), findsOneWidget);
      expect(
        find.textContaining(
          'This Flutter cannot build iPhone release apps here yet',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Your Flutter (3.47.8)'), findsOneWidget);
      // The generic card for the same code is not shown twice.
      expect(find.text('Code: build.gen_snapshot_unavailable'), findsOneWidget);

      await tester.tap(
        find.widgetWithText(XButton, 'Set up Flutter 3.47.6 for iPhone builds'),
      );
      await settle(tester);
      expect(_commands(launcher), contains('flutter sdk auto --yes'));
      expect(
        find.text('Flutter 3.47.6 is set up for iPhone builds'),
        findsOneWidget,
      );

      final builds = _commands(launcher)
          .where((c) => c.startsWith('flutter build'))
          .length;
      await tester.tap(find.widgetWithText(XButton, 'Build again'));
      await settle(tester);
      expect(
        _commands(launcher).where((c) => c.startsWith('flutter build')).length,
        builds + 1,
      );
    },
  );

  testWidgets('AC-014-8 "Show details" reveals the CLI text', (tester) async {
    await _pump(tester, project: project.path);
    await go(tester, 'Build & Run');
    await tester.tap(find.widgetWithText(XButton, 'Build IPA'));
    await settle(tester);
    final before = find
        .textContaining('xcross_gen_snapshot/releases')
        .evaluate()
        .length;
    await tester.tap(find.text('Show details'));
    await settle(tester, 2);
    expect(
      find.textContaining('xcross_gen_snapshot/releases').evaluate().length,
      before + 1,
    );
    expect(find.text('Hide details'), findsOneWidget);
  });

  testWidgets('AC-014-9 Overview shows the fix when the doctor reports it', (
    tester,
  ) async {
    await _pump(
      tester,
      project: project.path,
      doctor: [_check('AOT compiler (release)', 'failure', _missingMessage)],
    );
    expect(find.byType(FlutterSdkFixCard), findsOneWidget);
    expect(find.text('iOS release compiler'), findsOneWidget);
  });

  testWidgets(
    'AC-014-10 Settings shows the managed Flutter and switches back',
    (tester) async {
      final launcher = await _pump(
        tester,
        project: project.path,
        managed: true,
      );
      await go(tester, 'Settings');
      await settle(tester);
      expect(
        find.textContaining('iOS builds use Flutter 3.47.6'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Installed by XCross Studio for iPhone builds'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(XButton, 'Use my own Flutter'));
      await settle(tester);
      expect(_commands(launcher), contains('flutter sdk reset'));
    },
  );

  testWidgets(
    'AC-014-10 Settings offers the fix when the compiler is missing',
    (tester) async {
      await _pump(tester, project: project.path, compiler: 'missing');
      await go(tester, 'Settings');
      await settle(tester);
      expect(
        find.textContaining('No iOS release compiler for this Flutter'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(XButton, 'Set up Flutter 3.47.6 for iPhone builds'),
        findsOneWidget,
      );
    },
  );

  test('AC-014-11 command builders', () {
    expect(XcrossCommands.flutterSdkAuto(), [
      'flutter',
      'sdk',
      'auto',
      '--yes',
    ]);
    expect(XcrossCommands.flutterSdkList(), [
      'flutter',
      'sdk',
      'list',
      '--json',
    ]);
    expect(XcrossCommands.flutterSdkReset(), ['flutter', 'sdk', 'reset']);
    final status = XcrossEvent.tryParse(
      _sdks(managed: false, compiler: 'missing'),
    );
    expect(status, isA<FlutterSdkStatus>());
    status as FlutterSdkStatus;
    expect(status.suggested, '3.47.6');
    expect(status.activeManaged, isFalse);
    expect(status.available, ['3.47.6', '3.47.5']);
  });
}
