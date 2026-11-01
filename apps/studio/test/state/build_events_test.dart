// studio: 012 — the GUI consumes XCROSS_EVENTS=ndjson build events.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:xcross_studio/src/cli/output_line.dart';
import 'package:xcross_studio/src/cli/xcross_commands.dart';
import 'package:xcross_studio/src/cli/xcross_events.dart';
import 'package:xcross_studio/src/host/host_platform.dart';
import 'package:xcross_studio/src/state/job.dart';
import 'package:xcross_studio/src/state/log_session.dart';
import 'package:xcross_studio/src/state/settings.dart';
import 'package:xcross_studio/src/ui/project_page.dart';
import 'package:xcross_studio/src/ui/services.dart';
import 'package:xcross_studio/src/ui/widgets.dart';

import '../support/fake_launcher.dart';

/// A scripted `xcross flutter build --release --ipa` in event mode.
const buildEvents = [
  '{"v":1,"type":"log","level":"info","message":"Version      1.0.7 (7)"}',
  '{"v":1,"type":"step","name":"Resolving dependencies","status":"start"}',
  '{"v":1,"type":"step","name":"Resolving dependencies","status":"done",'
      '"message":null,"elapsedMs":1200}',
  '{"v":1,"type":"progress","label":"Downloading engine","fraction":0.5,'
      '"current":5,"total":10,"unit":"bytes"}',
  '{"v":1,"type":"warning","code":"build.asset_catalog_skipped",'
      '"message":"Assets.xcassets was not compiled.","hint":"Install AssetKit."}',
  '{"v":1,"type":"step","name":"Compiling Runner","status":"start"}',
  '{"v":1,"type":"log","level":"trace","message":"swiftc -c main.swift",'
      '"step":"Compiling Runner"}',
  '{"v":1,"type":"step","name":"Compiling Runner","status":"done",'
      '"message":null,"elapsedMs":3400}',
  '{"v":1,"type":"artifact","kind":"app","path":"/w/build/xcross-ios/Runner.app"}',
  '{"v":1,"type":"artifact","kind":"ipa","path":"/w/build/xcross-ios/demo.ipa"}',
  '{"v":1,"type":"done","exitCode":0}',
];

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Job structuredJob(FakeLauncher launcher, {bool structured = true}) => Job(
  title: 'Build',
  command: XcrossCommands.build(mode: BuildMode.release),
  invocation: const XcrossInvocation.binary(),
  launcher: launcher,
  structured: structured,
);

void main() {
  group('AC-012-6 event parsing', () {
    test('every build event type parses', () {
      expect(
        XcrossEvent.tryParse(buildEvents[1]),
        isA<BuildStep>().having((s) => s.status, 'status', 'start'),
      );
      expect(
        XcrossEvent.tryParse(buildEvents[3]),
        isA<BuildProgress>().having((s) => s.fraction, 'fraction', 0.5),
      );
      expect(
        XcrossEvent.tryParse(buildEvents[4]),
        isA<BuildIssue>()
            .having((i) => i.code, 'code', 'build.asset_catalog_skipped')
            .having((i) => i.isError, 'isError', isFalse),
      );
      expect(
        XcrossEvent.tryParse(buildEvents[9]),
        isA<BuildArtifact>().having((a) => a.kind, 'kind', 'ipa'),
      );
      expect(XcrossEvent.tryParse(buildEvents.last), isA<BuildDone>());
      expect(
        XcrossEvent.tryParse(
          '{"v":1,"type":"check","section":"S","name":"usbmuxd",'
          '"status":"failure","message":"Not running","path":null}',
        ),
        isA<DoctorCheckResult>().having((c) => c.status, 'status', 'failure'),
      );
      expect(
        XcrossEvent.tryParse(
          '{"v":1,"type":"error","code":null,"message":"m","hint":null}',
        ),
        isA<BuildIssue>().having((i) => i.isError, 'isError', isTrue),
      );
    });

    test('an event after partial tool text on the same line is kept', () {
      final (:text, :event) = XcrossEvent.split(
        'Choose a device: {"v":1,"type":"done","exitCode":1}',
      );
      expect(text, 'Choose a device: ');
      expect((event! as BuildDone).exitCode, 1);
      final plain = XcrossEvent.split('plain {"not":"an event"}');
      expect(plain.event, isNull);
      expect(plain.text, 'plain {"not":"an event"}');
    });
  });

  group('AC-012-7 structured jobs', () {
    test(
      'events become steps, progress, issues, artifacts and lines',
      () async {
        final launcher = FakeLauncher(
          onStart: (process, _) async {
            buildEvents.forEach(process.out);
            process.out('raw tool output');
            await process.exit(0);
          },
        );
        final job = structuredJob(launcher);
        await job.start();
        expect(launcher.starts.single.environment['XCROSS_EVENTS'], 'ndjson');
        expect(job.status, JobStatus.succeeded);
        expect(job.reportedExitCode, 0);
        expect(
          [for (final s in job.steps) '${s.name}:${s.status}'],
          ['Resolving dependencies:done', 'Compiling Runner:done'],
        );
        expect(job.currentStep, isNull);
        expect(job.progress?.fraction, 0.5);
        expect(job.artifact('ipa'), '/w/build/xcross-ios/demo.ipa');
        expect(job.artifact('app'), '/w/build/xcross-ios/Runner.app');
        expect(job.issues.single.code, 'build.asset_catalog_skipped');
        final texts = [for (final l in job.lines) l.text];
        expect(
          texts,
          containsAll([
            'Version      1.0.7 (7)',
            'Resolving dependencies…',
            '✔ Resolving dependencies  1.2s',
            'warning: [build.asset_catalog_skipped] Assets.xcassets was not '
                'compiled.',
            'hint: Install AssetKit.',
            'swiftc -c main.swift',
            'raw tool output',
          ]),
        );
        expect(
          job.lines.firstWhere((l) => l.text == 'swiftc -c main.swift').kind,
          LineKind.stderr,
          reason: 'step output is dimmed',
        );
        expect(texts.where((t) => t.startsWith('{')), isEmpty);
      },
    );

    test(
      'a failed step and an error event; old CLIs fall back to text',
      () async {
        final failing = structuredJob(
          FakeLauncher(
            onStart: (process, _) async {
              process
                ..out('{"v":1,"type":"step","name":"Signing","status":"start"}')
                ..out(
                  '{"v":1,"type":"step","name":"Signing","status":"failed",'
                  '"message":null,"elapsedMs":10}',
                )
                ..out(
                  '{"v":1,"type":"error","code":"device.not_found",'
                  '"message":"No iPhone.","hint":"Connect it."}',
                )
                ..out('{"v":1,"type":"done","exitCode":1}');
              await process.exit(1);
            },
          ),
        );
        await failing.start();
        expect(failing.status, JobStatus.failed);
        expect(failing.steps.single.status, 'failed');
        expect(failing.issues.single.code, 'device.not_found');
        expect(failing.lines.map((l) => l.text), contains('✖ Signing'));

        final launcher = FakeLauncher(
          onStart: (process, _) async {
            process
              ..out('Building…')
              ..err('warning: [build.storyboard_skipped] Main');
            await process.exit(0);
          },
        );
        final old = structuredJob(launcher);
        await old.start();
        expect(old.steps, isEmpty);
        expect(old.issues.single.code, 'build.storyboard_skipped');

        final plain = structuredJob(FakeLauncher(), structured: false);
        unawaited(plain.start());
        await Future<void>.delayed(Duration.zero);
        final env = (plain.launcher as FakeLauncher).starts.single.environment;
        expect(env.containsKey('XCROSS_EVENTS'), isFalse);
        await plain.cancel();
      },
    );
  });

  group('AC-012-8 views', () {
    testWidgets('the output view shows steps, download progress and issues', (
      tester,
    ) async {
      final launcher = FakeLauncher(
        onStart: (process, _) async {
          buildEvents.take(6).forEach(process.out);
        },
      );
      final job = structuredJob(launcher);
      unawaited(job.start());
      await settle(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: JobOutputView(job: job, height: 200)),
        ),
      );
      await tester.pump();
      expect(find.byType(StepsPanel), findsOneWidget);
      expect(find.text('Downloading engine  50%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Resolving dependencies  1.2s'), findsOneWidget);
      expect(find.textContaining('Compiling Runner'), findsWidgets);
      expect(find.byType(IssueList), findsOneWidget);
      expect(find.textContaining('Install AssetKit.'), findsWidgets);
      await job.cancel();
      await settle(tester);
    });

    testWidgets('the doctor report lists the checks', (tester) async {
      final job = structuredJob(
        FakeLauncher(
          onStart: (process, _) async {
            process
              ..out(
                '{"v":1,"type":"check","section":"Device service",'
                '"name":"usbmuxd","status":"success","message":"Found",'
                '"path":null}',
              )
              ..out(
                '{"v":1,"type":"check","section":"Deployment",'
                '"name":"Authentication","status":"failure",'
                '"message":"No credentials found.","path":null}',
              );
            await process.exit(1);
          },
        ),
      );
      unawaited(job.start());
      await settle(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: DoctorReport(job: job)),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Device service'), findsOneWidget);
      expect(find.text('Deployment'), findsOneWidget);
      expect(find.textContaining('No credentials found.'), findsWidgets);
      expect(find.byIcon(Icons.cancel), findsWidgets);
    });

    testWidgets('"Install" uses the IPA named by the artifact event', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final project = await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('studio_project_');
        await File(p.join(dir.path, 'pubspec.yaml'))
            .writeAsString('name: demo\nversion: 1.0.0+1\n');
        await Directory(p.join(dir.path, 'ios')).create();
        return dir;
      });
      addTearDown(() => project!.deleteSync(recursive: true));
      final launcher = FakeLauncher(
        onStart: (process, arguments) async {
          if (arguments.take(2).join(' ') == 'flutter build') {
            buildEvents.forEach(process.out);
          }
          await process.exit(0);
        },
      );
      final settings = Settings()..projectPath = project!.path;
      final jobs = JobCenter(
        launcher: launcher,
        invocation: () => const XcrossInvocation.binary(),
      );
      String? installed;
      await tester.pumpWidget(
        MaterialApp(
          home: Services(
            host: HostPlatform.current(),
            launcher: launcher,
            settings: settings,
            jobs: jobs,
            logs: LogSession(jobs),
            child: Scaffold(
              body: ProjectPage(onInstall: (ipa) => installed = ipa),
            ),
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Build'));
      await settle(tester);
      expect(launcher.starts.last.environment['XCROSS_EVENTS'], 'ndjson');
      final install = find.textContaining('Install demo.ipa');
      expect(install, findsOneWidget);
      await tester.tap(install);
      expect(installed, '/w/build/xcross-ios/demo.ipa');
    });
  });
}
