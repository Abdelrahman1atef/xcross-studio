// studio: 048 — `xcross screen` (live iPhone screen through the helper).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_kit/host/linux/linux_host.dart';
import 'package:cli_kit/host/windows/windows_host.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:studio_ext/target/iphone/device/screen_command.dart';
import 'package:studio_ext/target/iphone/device/screen_helper.dart';
import 'package:test/test.dart';

@internal
final class FakeScreenProcess implements ScreenHelperProcess {
  FakeScreenProcess({this.code = 0});

  final int code;
  final _lines = StreamController<String>();
  final _errors = StreamController<String>();
  final _exit = Completer<int>();
  bool stopped = false;

  void emit(Object line) =>
      _lines.add(line is String ? line : jsonEncode(line));

  Future<void> finish() async {
    // close() completes only once a listener sees the end: don't wait for it.
    unawaited(_lines.close());
    unawaited(_errors.close());
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Stream<String> get errors => _errors.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Future<void> stop({Duration grace = const Duration(seconds: 5)}) async {
    stopped = true;
    await finish();
  }
}

@internal
final class FakeScreenHelper implements ScreenHelper {
  FakeScreenHelper(this.process);

  final FakeScreenProcess? process;
  List<String>? startedWith;

  @override
  String? locate() => process == null ? null : 'xcross-screen';

  @override
  Future<ScreenHelperProcess?> start(List<String> args) async {
    startedWith = args;
    return process;
  }
}

void main() {
  late List<int> out;
  late List<String> err;

  setUp(() {
    out = [];
    err = [];
  });

  List<Map<String, Object?>> events() => [
    for (final line in const LineSplitter().convert(utf8.decode(out)))
      (jsonDecode(line) as Map).cast<String, Object?>(),
  ];

  CommandRunner<void> runner(
    ScreenHelper helper, {
    Future<void> Function()? untilStopped,
  }) => CommandRunner<void>('xcross', 'test')
    ..addCommand(
      ScreenCommand(
        helper: helper,
        writeBytes: out.addAll,
        writeError: err.add,
        untilStopped: untilStopped ?? () => Completer<void>().future,
      ),
    );

  test(
    'AC-048-E1 stream starts the helper for the iPhone and passes its events through',
    () async {
      final process = FakeScreenProcess();
      final helper = FakeScreenHelper(process);
      final run = runner(
        helper,
      ).run(['screen', 'stream', '--udid', 'ABC123', '--json']);
      await Future<void>.delayed(Duration.zero);
      expect(helper.startedWith, ['stream', '--serial', 'ABC123']);
      process
        ..emit({
          'type': 'screen_format',
          'codec': 'h264',
          'width': 1126,
          'height': 2436,
        })
        ..emit({
          'type': 'screen_ready',
          'url': 'http://127.0.0.1:5/t/stream.h264',
          'codec': 'h264',
          'width': 1126,
          'height': 2436,
          'method': 'quicktime',
          'touch': false,
        })
        ..emit('not json: must not reach stdout')
        ..emit({'type': 'screen_end', 'reason': 'stopped', 'message': ''});
      await process.finish();
      await run;
      final e = events();
      expect(e.map((x) => x['type']), [
        'screen_format',
        'screen_ready',
        'screen_end',
      ]);
      expect(e.every((x) => x['v'] == 1), isTrue);
      expect(e[1]['url'], 'http://127.0.0.1:5/t/stream.h264');
    },
  );

  test('AC-048-E2 a missing helper reports helper_missing and fails', () async {
    await expectLater(
      runner(
        FakeScreenHelper(null),
      ).run(['screen', 'stream', '--udid', 'X', '--json']),
      throwsA(
        isA<CliError>().having(
          (e) => e.message,
          'message',
          contains('screen.helper_missing'),
        ),
      ),
    );
    expect(events().single, containsPair('reason', 'helper_missing'));
  });

  test('AC-048-E3 stopping xcross stops the helper', () async {
    final process = FakeScreenProcess();
    final stopped = Completer<void>();
    final run = runner(
      FakeScreenHelper(process),
      untilStopped: () => stopped.future,
    ).run(['screen', 'stream', '--udid', 'X', '--json']);
    await Future<void>.delayed(Duration.zero);
    stopped.complete();
    await run;
    expect(process.stopped, isTrue);
  });

  test(
    'AC-048-E4 a failing helper fails the command with its end reason',
    () async {
      final process = FakeScreenProcess(code: 1);
      final run = runner(
        FakeScreenHelper(process),
      ).run(['screen', 'stream', '--udid', 'X', '--json']);
      await Future<void>.delayed(Duration.zero);
      process.emit({
        'type': 'screen_end',
        'reason': 'driver_needed',
        'message': 'libusb0.dll is not installed',
      });
      await process.finish();
      await expectLater(
        run,
        throwsA(
          isA<CliError>().having(
            (e) => e.message,
            'message',
            contains('screen.driver_needed'),
          ),
        ),
      );
    },
  );

  test('AC-048-E5 text mode prints readable lines', () async {
    final process = FakeScreenProcess();
    final run = runner(
      FakeScreenHelper(process),
    ).run(['screen', 'stream', '--udid', 'X']);
    await Future<void>.delayed(Duration.zero);
    process
      ..emit({
        'type': 'screen_ready',
        'url': 'http://127.0.0.1:5/t/stream.h264',
        'codec': 'h264',
        'width': 1126,
        'height': 2436,
        'method': 'quicktime',
      })
      ..emit({'type': 'screen_stats', 'fps': 59.8, 'mbps': 10.7});
    await process.finish();
    await run;
    final text = utf8.decode(out);
    expect(text, contains('Screen ready: http://127.0.0.1:5/t/stream.h264'));
    expect(text, contains('Live: 59.8 fps, 10.7 Mbps'));
  });

  test('AC-048-E6 helper log lines go to stderr, never stdout', () async {
    final process = FakeScreenProcess();
    final run = runner(
      FakeScreenHelper(process),
    ).run(['screen', 'stream', '--udid', 'X', '--json']);
    await Future<void>.delayed(Duration.zero);
    process._errors.add('[INFO] usb direct: H.264 1126x2436');
    await process.finish();
    await run;
    expect(out, isEmpty);
    expect(err, ['[INFO] usb direct: H.264 1126x2436']);
  });

  test('AC-048-E7 devices passes the helper list through', () async {
    final process = FakeScreenProcess();
    final run = runner(
      FakeScreenHelper(process),
    ).run(['screen', 'devices', '--json']);
    await Future<void>.delayed(Duration.zero);
    process.emit({
      'type': 'devices',
      'driver': 'libusb0',
      'devices': [
        {'serial': 'ABC', 'configurations': 5, 'captureReady': true},
      ],
    });
    await process.finish();
    await run;
    expect(events().single['devices'], [
      {'serial': 'ABC', 'configurations': 5, 'captureReady': true},
    ]);
  });

  test(
    'AC-048-E8 the real helper is found next to xcross or by XCROSS_SCREEN_HELPER',
    () {
      final temp = Directory.systemTemp.createTempSync('xcross-screen-');
      addTearDown(() => temp.deleteSync(recursive: true));
      PlatformHostInterface host(Map<String, String> env) => Platform.isWindows
          ? WindowsHost(environment: env)
          : LinuxHost(environment: env);
      final ctx = host(const {}).paths.context;
      final bin = Directory(ctx.join(temp.path, 'bin'))..createSync();
      final xcross = ctx.join(bin.path, 'xcross');

      expect(
        HostScreenHelper(
          host: host(const {}),
          xcrossExecutable: xcross,
        ).locate(),
        isNull,
        reason: 'no helper anywhere',
      );

      final name = host(const {}).paths.executableName('xcross-screen');
      final beside = File(ctx.join(bin.path, name))..writeAsStringSync('');
      expect(
        HostScreenHelper(
          host: host(const {}),
          xcrossExecutable: xcross,
        ).locate(),
        beside.path,
      );

      expect(
        HostScreenHelper(
          host: host({'XCROSS_SCREEN_HELPER': '${temp.path}/missing'}),
          xcrossExecutable: xcross,
        ).locate(),
        isNull,
        reason: 'an override that does not exist is not silently replaced',
      );
    },
  );
}
