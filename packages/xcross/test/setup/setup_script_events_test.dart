import 'dart:io';

import 'package:cli_kit/host/linux/linux_host.dart';
import 'package:cli_kit/host/windows/windows_host.dart';
import 'package:cli_kit/shared/logging/logging.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/host/shared/setup/posix_setup_script.dart';
import 'package:xcross/src/shared/errors/errors.dart';
import 'package:xcross/src/shared/setup/setup_script.dart';
import 'package:xcross/src/shared/setup/setup_script_events.dart';

import '../host_operations_fixtures.dart';

void main() {
  late RecordingEvents events;
  late SetupScriptEvents reporter;

  setUp(() {
    events = RecordingEvents();
    reporter = SetupScriptEvents(events);
  });

  group('SetupScriptEvents', () {
    test('turns markers into step events and tags output with the step', () {
      const skippedVs =
          '##xcross {"step":"vs","status":"skipped","label":"Visual Studio '
          '2022 Build Tools (already installed)"}';
      reporter
        ..line('==> preparing', stream: 'stdout')
        ..line(
          '##xcross {"step":"llvm","status":"start","label":"LLVM"}',
          stream: 'stdout',
        )
        ..line('Downloading LLVM-22.1.8-win64.exe', stream: 'stdout')
        ..line('WARNING: slow mirror', stream: 'stderr')
        ..line(
          '##xcross {"step":"llvm","status":"done","label":"LLVM"}',
          stream: 'stdout',
        )
        ..line(skippedVs, stream: 'stdout');

      expect(events.recorded.map((event) => event.type), [
        'log',
        'step',
        'log',
        'log',
        'step',
        'step',
      ]);
      expect(events.recorded[0].fields, {
        'level': 'info',
        'message': '==> preparing',
        'stream': 'stdout',
      });
      expect(events.recorded[1].fields, {
        'name': 'llvm',
        'status': 'start',
        'message': 'LLVM',
      });
      expect(events.recorded[2].fields, {
        'level': 'info',
        'message': 'Downloading LLVM-22.1.8-win64.exe',
        'stream': 'stdout',
        'step': 'llvm',
      });
      expect(events.recorded[3].fields['stream'], 'stderr');
      expect(events.recorded[4].fields, {
        'name': 'llvm',
        'status': 'done',
        'message': 'LLVM',
        'elapsedMs': isA<int>(),
      });
      expect(events.recorded[5].fields, {
        'name': 'vs',
        'status': 'skipped',
        'message': 'Visual Studio 2022 Build Tools (already installed)',
      });
      expect(reporter.failed, isEmpty);
    });

    test('keeps malformed markers and drops blank lines and ANSI', () {
      reporter
        ..line('##xcross not json', stream: 'stdout')
        ..line('##xcross {"step":"llvm","status":"maybe"}', stream: 'stdout')
        ..line('say ##xcross {"step":"x","status":"start"}', stream: 'stdout')
        ..line('   ', stream: 'stdout')
        ..line('\x1B[33mWARNING\x1B[0m: careful  ', stream: 'stderr');

      expect(events.recorded.map((event) => event.type), everyElement('log'));
      expect(events.recorded.map((event) => event.fields['message']), [
        '##xcross not json',
        '##xcross {"step":"llvm","status":"maybe"}',
        'say ##xcross {"step":"x","status":"start"}',
        'WARNING: careful',
      ]);
    });

    test('a step the script never ended is reported failed', () {
      reporter
        ..line(
          '##xcross {"step":"python","status":"start","label":"Python 3.13"}',
          stream: 'stdout',
        )
        ..line(
          '##xcross {"step":"swift","status":"failed","label":"Swift"}',
          stream: 'stdout',
        )
        ..finish();

      final steps = [
        for (final event in events.recorded)
          if (event.type == 'step')
            '${event.fields['name']}:${event.fields['status']}',
      ];
      expect(steps, ['python:start', 'swift:failed', 'python:failed']);
      expect(reporter.failed, ['swift', 'python']);
    });

    test('runs a real script with its output captured', () async {
      final temporary = Directory.systemTemp.createTempSync('xcross-events-');
      addTearDown(() => temporary.deleteSync(recursive: true));
      final script = File(p.join(temporary.path, 'script.dart'))
        ..writeAsStringSync('''
import 'dart:io';
void main() {
  print('##xcross {"step":"llvm","status":"start","label":"LLVM"}');
  print('installing');
  stderr.writeln('a warning');
  print('##xcross {"step":"llvm","status":"failed","label":"LLVM"}');
  exitCode = 3;
}
''');
      final runner = fixtureRunner(nativeHost(), log: fixtureLog());

      await expectLater(
        SetupScriptEvents.run(
          runner,
          events,
          Platform.resolvedExecutable,
          [script.path],
          const {},
        ),
        throwsA(
          isA<XcrossError>().having(
            (error) => error.message,
            'message',
            contains('Setup could not install llvm (exit code 3)'),
          ),
        ),
      );
      final seen = [
        for (final (:type, :fields) in events.recorded)
          [
            type,
            fields['name'] ?? fields['message'],
            ?fields['status'],
          ].join(':'),
      ];
      expect(seen, containsAll(['step:llvm:start', 'step:llvm:failed']));
      expect(seen, containsAll(['log:installing', 'log:a warning']));
    });
  });

  group('SetupScriptManager', () {
    late Directory temporary;
    late File script;

    setUp(() {
      temporary = Directory.systemTemp.createTempSync('xcross-setup-events-');
      script = File(p.join(temporary.path, 'setup.ps1'))
        ..writeAsStringSync('# setup');
    });
    tearDown(() => temporary.deleteSync(recursive: true));

    Future<Map<String, String>> environmentFor(Log log) async {
      final host = nativeHost();
      Map<String, String>? environment;
      await SetupScriptManager(
        createHttpClient: () => throw StateError('unexpected HTTP'),
        source: script.path,
        host: host,
        runner: fixtureRunner(host, log: log),
        policy: PosixSetupScript(host),
        execute: (_, _, env) async => environment = env,
      ).run(approve: (_) => true, assumeYes: true);
      return environment!;
    }

    test('asks the script for step markers in NDJSON mode', () async {
      expect(
        await environmentFor(Log(output: FixtureLogOutput(), events: events)),
        {'XCROSS_SETUP_ASSUME_YES': '1', 'XCROSS_SETUP_EVENTS': '1'},
      );
    });

    test('leaves terminal runs without markers', () async {
      expect(await environmentFor(fixtureLog()), {
        'XCROSS_SETUP_ASSUME_YES': '1',
      });
    });
  });
}

/// A host of the platform the tests run on, with the real environment.
@internal
PlatformHostInterface nativeHost() => Platform.isWindows
    ? WindowsHost(
        environment: Platform.environment,
        currentDirectory: Directory.current.path,
      )
    : LinuxHost(
        environment: Platform.environment,
        currentDirectory: Directory.current.path,
      );

@internal
final class RecordingEvents implements LogEvents {
  final recorded = <({String type, Map<String, Object?> fields})>[];

  @override
  void event(String type, Map<String, Object?> fields) =>
      recorded.add((type: type, fields: fields));

  @override
  void message(LogEventLevel level, String message) =>
      recorded.add((type: level.name, fields: {'message': message}));

  @override
  void stepStarted(String label) =>
      recorded.add((type: 'stepStarted', fields: {'name': label}));

  @override
  void stepOutput(String label, String line) =>
      recorded.add((type: 'stepOutput', fields: {'message': line}));

  @override
  void stepFinished(
    String label, {
    required bool ok,
    required String message,
    required Duration elapsed,
  }) => recorded.add((type: 'stepFinished', fields: {'name': label}));
}
