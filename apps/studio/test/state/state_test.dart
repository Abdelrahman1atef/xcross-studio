import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:xcross_studio/src/cli/output_line.dart';
import 'package:xcross_studio/src/cli/xcross_commands.dart';
import 'package:xcross_studio/src/cli/xcross_events.dart';
import 'package:xcross_studio/src/state/job.dart';
import 'package:xcross_studio/src/state/log_session.dart';
import 'package:xcross_studio/src/state/settings.dart';

import '../support/fake_launcher.dart';

String logLine(
  String message, {
  String process = 'Runner',
  String level = 'notice',
}) =>
    '{"v":1,"type":"devicelog","time":"2026-11-01T10:00:00.5",'
    '"process":"$process","pid":7,"subsystem":null,"category":null,'
    '"level":"$level","message":"$message","highlight":null}';

void main() {
  group('AC-008-5 jobs', () {
    test('streams lines, routes events, reports success', () async {
      final events = <XcrossEvent>[];
      final launcher = FakeLauncher(
        onStart: (process, _) async {
          process
            ..out('Building…')
            ..out('{"v":1,"type":"notice","message":"waiting"}')
            ..err('warning: [build.storyboard_skipped] Main')
            ..out('✔ done');
          await process.exit(0);
        },
      );
      final job = Job(
        title: 'Build',
        command: XcrossCommands.build(mode: BuildMode.release),
        invocation: const XcrossInvocation('xcross', ['--prefix']),
        launcher: launcher,
        workingDirectory: '/project',
        onEvent: events.add,
      );
      await job.start();
      expect(job.status, JobStatus.succeeded);
      expect(job.exitCode, 0);
      final start = launcher.starts.single;
      expect(start.executable, 'xcross');
      expect(start.arguments.take(3), ['--prefix', 'flutter', 'build']);
      expect(start.workingDirectory, '/project');
      expect(start.environment['XCROSS_OUTPUT_ENCODING'], 'utf-8');
      expect(job.lines.first.kind, LineKind.command);
      expect([
        for (final l in job.lines) l.text,
      ], containsAll(['Building…', '✔ done']));
      expect(job.lines.map((l) => l.text), isNot(contains(contains('notice'))));
      expect(events.single, isA<Notice>());
      expect(job.issues.single.code, 'build.storyboard_skipped');
    });

    test('a non-zero exit fails; a start error explains the fix', () async {
      final failing = Job(
        title: 'Run',
        command: const ['flutter', 'run'],
        invocation: const XcrossInvocation.binary(),
        launcher: FakeLauncher(
          onStart: (process, _) async {
            process.err('error: [device.not_found] No iPhone.');
            await process.exit(1);
          },
        ),
      );
      await failing.start();
      expect(failing.status, JobStatus.failed);
      expect(failing.issues.single.code, 'device.not_found');

      final missing = Job(
        title: 'Doctor',
        command: const ['doctor'],
        invocation: const XcrossInvocation.binary('nope'),
        launcher: FakeLauncher(startError: const ProcessException('nope', [])),
      );
      await missing.start();
      expect(missing.status, JobStatus.failed);
      expect(missing.lines.last.kind, LineKind.hint);
    });

    test('cancel kills the process tree; input goes to stdin', () async {
      final launcher = FakeLauncher();
      final job = Job(
        title: 'Auth',
        command: XcrossCommands.authAppleId('me@example.com', password: 'pw'),
        invocation: const XcrossInvocation.binary(),
        launcher: launcher,
      );
      final running = job.start();
      await Future<void>.delayed(Duration.zero);
      job.send('123456');
      expect(launcher.processes.single.stdinLines, ['123456']);
      expect(job.lines.first.text, isNot(contains('pw')));
      await job.cancel();
      await running;
      expect(launcher.killed, [4242]);
      expect(job.status, JobStatus.cancelled);
    });

    test('JobCenter.collect returns the events', () async {
      final center = JobCenter(
        launcher: FakeLauncher(
          onStart: (process, _) async {
            process.out(
              '{"v":1,"type":"device","udid":"U1","name":"P",'
              '"osVersion":"17.4","connection":"usb"}',
            );
            await process.exit(0);
          },
        ),
        invocation: () => const XcrossInvocation.binary(),
      );
      final (job, events) = await center.collect(
        'Devices',
        XcrossCommands.devices(),
      );
      expect(job.status, JobStatus.succeeded);
      expect((events.single as ConnectedDevice).legacy, isFalse);
      expect(center.jobs, hasLength(1));
      center.clearFinished();
      expect(center.jobs, isEmpty);
    });
  });

  group('AC-008-6 device log session', () {
    test('filters, pause/resume, capacity and save text', () async {
      late FakeProcess process;
      final launcher = FakeLauncher(onStart: (p, _) => process = p);
      final logs = LogSession(
        JobCenter(
          launcher: launcher,
          invocation: () => const XcrossInvocation.binary(),
        ),
        capacity: 3,
        notifyEvery: Duration.zero,
      );
      logs.start(app: 'com.example.app', preset: LogPreset.flutter);
      await Future<void>.delayed(Duration.zero);
      expect(launcher.starts.single.arguments, [
        'logs',
        '--json',
        '--app',
        'com.example.app',
        '--preset',
        'flutter',
      ]);
      process
        ..out(logLine('hello'))
        ..out(logLine('kernel says hi', process: 'kernel', level: 'debug'))
        ..out(logLine('bad thing', level: 'error'));
      await Future<void>.delayed(Duration.zero);
      expect(logs.received, 3);

      logs.setFilters(level: LogLevel.notice);
      expect([for (final l in logs.visible) l.message], ['hello', 'bad thing']);
      logs.setFilters(text: 'BAD');
      expect([for (final l in logs.visible) l.message], ['bad thing']);
      logs.setFilters(text: '', process: 'kern', level: LogLevel.debug);
      expect([for (final l in logs.visible) l.message], ['kernel says hi']);
      logs.setFilters(process: '');

      logs.togglePause();
      process.out(logLine('while paused'));
      await Future<void>.delayed(Duration.zero);
      expect(
        logs.visible.map((l) => l.message),
        isNot(contains('while paused')),
      );
      logs.togglePause();
      expect(logs.visible.last.message, 'while paused');
      expect(logs.received, 3, reason: 'capacity drops the oldest');
      expect(logs.visibleText(), contains('Runner[7] N while paused'));

      process.out(
        '{"v":1,"type":"diagnosis","bundleId":"com.example.app",'
        '"entitlement":"development","appSeen":true,"registrationSeen":true,'
        '"deliverySeen":false,"permissionDenied":false,'
        '"verdict":"registered_no_delivery","hint":"Send a push."}',
      );
      await Future<void>.delayed(Duration.zero);
      expect(logs.diagnosis?.verdict, 'registered_no_delivery');

      await logs.stop();
      await logs.job!.done;
      expect(logs.running, isFalse);
      logs.dispose();
    });
  });

  test('settings persist to a JSON file', () async {
    final dir = Directory.systemTemp.createTempSync('studio_settings_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final settings = await Settings.load(dir.path);
    await settings.update((s) {
      s.projectPath = '/work/app';
      s.invocation = XcrossInvocation.fromSource('/repo', context: p.posix);
      s.acceptedNotice = true;
    });
    final again = await Settings.load(dir.path);
    expect(again.projectPath, '/work/app');
    expect(again.invocation.executable, 'dart');
    expect(again.acceptedNotice, isTrue);
  });
}
