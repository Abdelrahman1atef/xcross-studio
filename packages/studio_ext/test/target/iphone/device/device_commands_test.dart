import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/src/target/iphone/device/crash_reports.dart';
import 'package:studio_ext/src/target/iphone/device/crash_tools.dart';
import 'package:studio_ext/src/target/iphone/device/device_codes.dart';
import 'package:studio_ext/target/iphone/device/app_command.dart';
import 'package:studio_ext/target/iphone/device/crashes_command.dart';
import 'package:studio_ext/target/iphone/device/logs_command.dart';
import 'package:test/test.dart';

import '../../../support/fake_device_backend.dart';
import '../../../support/json_schema_lite.dart';
import '../../../support/test_file_system.dart';

void main() {
  late Directory temp;
  late List<int> out;
  late StreamController<void> interrupts;
  final schema = JsonSchemaLite.devicelogContract();

  setUp(() {
    temp = Directory.systemTemp.createTempSync('xcross_device_cmds_');
    out = [];
    interrupts = StreamController<void>.broadcast();
  });
  tearDown(() async {
    await interrupts.close();
    temp.deleteSync(recursive: true);
  });

  String text() => utf8.decode(out);

  const appId = 'com.example.app';
  final apps = {
    appId: appEntry(
      executable: 'Runner',
      entitlements: {
        'aps-environment': 'development',
        'application-identifier': 'TEAMID1234.$appId',
      },
    ),
  };

  CommandRunner<void> runner(
    FakeDeviceBackend backend, {
    Duration pushCheckpoint = const Duration(seconds: 30),
  }) => CommandRunner<void>('xcross', 'test')
    ..addCommand(
      LogsCommand(
        backend: backend,
        fileSystem: const IoFileSystem(),
        writeBytes: out.addAll,
        interrupts: () => interrupts.stream,
        pushCheckpoint: pushCheckpoint,
      ),
    )
    ..addCommand(AppCommand(backend: backend, writeBytes: out.addAll))
    ..addCommand(
      CrashesCommand(
        backend: backend,
        fileSystem: const IoFileSystem(),
        paths: p.context,
        cacheRoot: temp.path,
        writeBytes: out.addAll,
      ),
    );

  group('xcross logs', () {
    test('AC-010-1 AC-010-3 app lines stream, across a relaunch', () async {
      final backend = FakeDeviceBackend(
        apps: apps,
        lines: [
          syslogLine(process: 'SpringBoard', message: 'noise'),
          syslogLine(process: 'Runner', message: 'first launch', pid: 10),
          'not json',
          syslogLine(process: 'Runner', message: 'after relaunch', pid: 11),
        ],
      );
      await runner(backend).run(['logs', '--app', appId]);
      final shown = text();
      expect(shown, startsWith('Waiting for Runner logs'));
      expect(shown, contains('Runner[10] N first launch'));
      expect(shown, contains('Runner[11] N after relaunch'));
      expect(shown, isNot(contains('noise')));
      expect(backend.calls, ['ensure:-', 'apps', 'syslog']);
    });

    test('AC-010-4 filters and --save write the same lines', () async {
      final save = '${temp.path}/out.log';
      await runner(
        FakeDeviceBackend(
          lines: [
            syslogLine(process: 'apsd', message: 'Token ok', level: 'ERROR'),
            syslogLine(process: 'apsd', message: 'token low', level: 'INFO'),
            syslogLine(process: 'x', message: 'token', level: 'ERROR'),
          ],
        ),
      ).run([
        'logs',
        '--process',
        'apsd',
        '--level',
        'error',
        '--grep',
        'TOKEN',
        '--save',
        save,
      ]);
      expect(text(), contains('Token ok'));
      expect(text(), isNot(contains('token low')));
      expect(File(save).readAsStringSync(), text());
    });

    test('an interrupt or --duration stops a live stream cleanly', () async {
      final backend = FakeDeviceBackend(
        keepOpen: true,
        lines: [syslogLine(process: 'apsd', message: 'hello')],
      );
      final run = runner(backend).run(['logs']);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      interrupts.add(null);
      await run;
      expect(backend.session!.stopped, isTrue);
      expect(text(), contains('hello'));

      out.clear();
      final timed = FakeDeviceBackend(keepOpen: true);
      await runner(timed).run(['logs', '--duration', '1']);
      expect(timed.session!.stopped, isTrue);
    });

    test('AC-010-8 push diagnosis at the checkpoint and at the end', () async {
      final backend = FakeDeviceBackend(
        apps: apps,
        keepOpen: true,
        lines: [
          syslogLine(process: 'Runner', message: 'APNS device token received'),
        ],
      );
      final run = runner(
        backend,
        pushCheckpoint: const Duration(milliseconds: 50),
      ).run(['logs', '--app', appId, '--preset', 'push']);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      interrupts.add(null);
      await run;
      final shown = text();
      expect(
        RegExp('Push diagnosis for $appId').allMatches(shown),
        hasLength(2),
      );
      expect(shown, contains('verdict: registered_no_delivery'));
      expect(shown, contains('★ '));
    });

    test('AC-010-10 --json emits schema-valid NDJSON events', () async {
      await runner(
        FakeDeviceBackend(
          apps: apps,
          lines: [syslogLine(process: 'Runner', message: 'push token م')],
        ),
      ).run(['logs', '--app', appId, '--preset', 'push', '--json']);
      final events = const LineSplitter().convert(text());
      expect(events.map((e) => (jsonDecode(e) as Map)['type']), [
        'notice',
        'devicelog',
        'diagnosis',
      ]);
      for (final event in events) {
        expect(event.codeUnits.every((u) => u <= 0x7e), isTrue);
        expect(schema.validate(jsonDecode(event)), isEmpty, reason: event);
      }
    });

    test('SC-004 default output masks the device id and tokens', () async {
      await runner(
        FakeDeviceBackend(
          lines: [
            syslogLine(
              process: 'apsd',
              message: 'device 00008020-001A2B3C4D5E6F70 token ${'ab' * 32}',
            ),
          ],
        ),
      ).run(['logs']);
      expect(text(), isNot(contains('00008020')));
      expect(text(), isNot(contains('abab')));
      out.clear();
      await runner(
        FakeDeviceBackend(
          lines: [syslogLine(process: 'apsd', message: 'token ${'ab' * 32}')],
        ),
      ).run(['logs', '--show-sensitive']);
      expect(text(), contains('ab' * 32));
    });

    test('usage and coded errors', () async {
      await expectLater(
        runner(FakeDeviceBackend()).run(['logs', '--preset', 'push']),
        throwsA(isA<UsageException>()),
      );
      await expectLater(
        runner(FakeDeviceBackend()).run(['logs', '--app', 'missing.app']),
        throwsA(
          isA<CliError>().having(
            (e) => e.message,
            'message',
            startsWith('[app.not_installed]'),
          ),
        ),
      );
      await expectLater(
        runner(
          FakeDeviceBackend(
            ensureError: DeviceFailure(DeviceCodes.notTrusted, 'locked'),
          ),
        ).run(['logs']),
        throwsA(
          isA<CliError>().having(
            (e) => e.message,
            'message',
            startsWith('[device.not_trusted]'),
          ),
        ),
      );
    });
  });

  group('xcross app info', () {
    test('AC-010-6 human and JSON output', () async {
      await runner(FakeDeviceBackend(apps: apps)).run(['app', 'info', appId]);
      expect(text(), contains('signer: development · team TEAMID1234'));
      expect(text(), contains('✔ push entitlement'));
      expect(text(), contains('✖ associated domains'));
      expect(text(), isNot(contains('Planted Person')));
      out.clear();
      await runner(
        FakeDeviceBackend(apps: apps),
      ).run(['app', 'info', appId, '--json']);
      final json = jsonDecode(text()) as Map;
      expect(json['push'], 'development');
      expect(schema.validate(json), isEmpty);
    });
  });

  group('xcross crashes', () {
    const ips =
        '{"app_name":"Runner"}\n'
        '{"exception":{"type":"EXC_BAD_ACCESS","signal":"SIGSEGV"},'
        '"faultingThread":0,"usedImages":[{"name":"Runner"}],'
        '"threads":[{"frames":[{"imageIndex":0,"imageOffset":64}]}]}';
    FakeDeviceBackend backend() => FakeDeviceBackend(
      apps: apps,
      crashes: [
        '/Retired',
        '/Runner-2026-10-01-101500.ips',
        '/Other-2026-11-01-080000.ips',
        '/Runner-2026-11-01-090000.ips',
      ],
      crashFiles: {
        'Runner-2026-11-01-090000.ips': ips,
        'Runner-2026-10-01-101500.ips': ips,
      },
    );

    test('AC-010-9 retired reports stay listed, once each', () async {
      await runner(
        FakeDeviceBackend(
          apps: apps,
          crashes: [
            '/Retired',
            '/Runner-2026-11-01-090000.ips',
            '/Retired/Runner-2026-11-01-090000.ips',
            '/Retired/Runner-2026-09-01-070000.ips',
          ],
          crashFiles: {
            'Runner-2026-11-01-090000.ips': ips,
            'Runner-2026-09-01-070000.ips': ips,
          },
        ),
      ).run(['crashes', 'list', '--app', appId]);
      final lines = const LineSplitter().convert(text());
      expect(lines, hasLength(2));
      expect(lines.last, contains('Runner-2026-09-01-070000.ips'));
    });

    test('AC-010-9 list newest first with exception types', () async {
      await runner(backend()).run(['crashes', 'list', '--app', appId]);
      final lines = const LineSplitter().convert(text());
      expect(lines, hasLength(2));
      expect(
        lines.first,
        startsWith('2026-11-01 09:00:00  Runner  EXC_BAD_ACCESS'),
      );
      out.clear();
      await runner(backend()).run(['crashes', 'list', '--json']);
      for (final line in const LineSplitter().convert(text())) {
        expect(schema.validate(jsonDecode(line)), isEmpty, reason: line);
      }
    });

    test('AC-010-9 a retired report is pulled from /Retired', () async {
      final dir = '${temp.path}/retired';
      await runner(
        FakeDeviceBackend(
          apps: apps,
          crashes: ['/Retired', '/Retired/Runner-2026-11-01-090000.ips'],
          crashFiles: {'Runner-2026-11-01-090000.ips': ips},
        ),
      ).run(['crashes', 'pull', '--latest', '--out', dir]);
      final saved = File('$dir/Retired/Runner-2026-11-01-090000.ips');
      expect(saved.existsSync(), isTrue);
      expect(
        text(),
        contains(p.join('Retired', 'Runner-2026-11-01-090000.ips')),
      );
      expect(text(), contains('exception: EXC_BAD_ACCESS (SIGSEGV)'));
    });

    test('AC-010-9 --app also takes the process name of an app that is '
        'no longer installed', () async {
      await runner(backend()).run(['crashes', 'list', '--app', 'Runner']);
      expect(const LineSplitter().convert(text()), hasLength(2));
      await expectLater(
        runner(backend()).run(['crashes', 'list', '--app', 'Nothing']),
        throwsA(
          isA<CliError>().having(
            (e) => e.message,
            'message',
            startsWith('[app.not_installed]'),
          ),
        ),
      );
    });

    test('AC-010-9 the saved path is shown without the long-path prefix', () {
      const summary = CrashReportSummary(
        exceptionType: null,
        signal: null,
        frames: [],
      );
      expect(
        const PulledCrash(r'\\?\C:\r\Runner.ips', summary).shownPath,
        r'C:\r\Runner.ips',
      );
      expect(
        const PulledCrash(r'\\?\UNC\srv\share\a.ips', summary).shownPath,
        r'\\srv\share\a.ips',
      );
      expect(const PulledCrash('/tmp/a.ips', summary).shownPath, '/tmp/a.ips');
    });

    test('AC-010-9 a report that cannot be copied is an error', () async {
      await expectLater(
        runner(
          FakeDeviceBackend(
            apps: apps,
            crashes: ['/Runner-2026-11-01-090000.ips'],
          ),
        ).run(['crashes', 'pull', '--latest', '--out', '${temp.path}/x']),
        throwsA(
          isA<CliError>().having(
            (e) => e.message,
            'message',
            contains('could not be copied'),
          ),
        ),
      );
      expect(text(), isNot(contains('Saved')));
    });

    test('AC-010-9 pull --latest saves and summarises', () async {
      final dir = '${temp.path}/reports';
      await runner(
        backend(),
      ).run(['crashes', 'pull', '--latest', '--app', appId, '--out', dir]);
      expect(File('$dir/Runner-2026-11-01-090000.ips').existsSync(), isTrue);
      expect(text(), contains('exception: EXC_BAD_ACCESS (SIGSEGV)'));
      expect(text(), contains('Runner  +64'));
      await expectLater(
        runner(
          backend(),
        ).run(['crashes', 'pull', 'Nope-2026-01-01-000000.ips']),
        throwsA(
          isA<CliError>().having(
            (e) => e.message,
            'message',
            startsWith('[crash.not_found]'),
          ),
        ),
      );
    });
  });

  test('SC-003 20000 lines filtered and formatted under 10 s', () async {
    final lines = [
      for (var i = 0; i < 20000; i++)
        syslogLine(
          process: i.isEven ? 'Runner' : 'bluetoothd',
          message: 'line $i token ${'ab' * 32}',
          pid: i,
        ),
    ];
    final stopwatch = Stopwatch()..start();
    await runner(
      FakeDeviceBackend(apps: apps, lines: lines),
    ).run(['logs', '--app', appId]);
    stopwatch.stop();
    expect(
      const LineSplitter().convert(text()).where((l) => l.contains('Runner[')),
      hasLength(10000),
    );
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
  });
}
