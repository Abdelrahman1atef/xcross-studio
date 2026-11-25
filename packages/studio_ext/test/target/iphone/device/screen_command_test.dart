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
import 'package:studio_ext/target/iphone/device/screen_core_device.dart';
import 'package:studio_ext/target/iphone/device/screen_helper.dart';
import 'package:studio_ext/target/iphone/device/screen_touch.dart';
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

  final sent = <String>[];

  @override
  void send(String line) => sent.add(line);

  @override
  Future<void> stop({Duration grace = const Duration(seconds: 5)}) async {
    stopped = true;
    await finish();
  }
}

@internal
final class FakeTouchLink implements ScreenTouchLink {
  final endedWith = Completer<String>();
  bool closed = false;

  @override
  String get url => 'http://127.0.0.1:18100';

  @override
  Future<String> get ended => endedWith.future;

  @override
  Future<void> close() async => closed = true;
}

/// Apple's service cannot reach the phone for the first [failures] asks.
@internal
final class FlakyTouch implements ScreenTouch {
  FlakyTouch(this.failures);

  int failures;
  final link = FakeTouchLink();
  final started = <String>[];

  @override
  Future<ScreenTouchLink> start(String udid) async {
    started.add(udid);
    if (failures-- > 0) {
      throw const ScreenTouchUnavailable(
        'unreachable',
        WdaScreenTouch.unreachableMessage,
      );
    }
    return link;
  }
}

@internal
final class FakeTouch implements ScreenTouch {
  FakeTouch({this.unavailable});

  final ScreenTouchUnavailable? unavailable;
  final link = FakeTouchLink();
  final started = <String>[];

  @override
  Future<ScreenTouchLink> start(String udid) async {
    started.add(udid);
    if (unavailable case final u?) throw u;
    return link;
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
    ScreenTouch? touch,
    CoreDeviceScreen? coreDevice,
  }) => CommandRunner<void>('xcross', 'test')
    ..addCommand(
      ScreenCommand(
        helper: helper,
        writeBytes: out.addAll,
        writeError: err.add,
        untilStopped: untilStopped ?? () => Completer<void>().future,
        touch: touch,
        coreDevice: coreDevice,
        touchRetryDelay: Duration.zero,
      ),
    );

  const ready = {
    'type': 'screen_ready',
    'url': 'http://127.0.0.1:5/t/stream.h264',
    'codec': 'h264',
    'width': 1126,
    'height': 2436,
    'method': 'quicktime',
    'touch': false,
  };

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
      'type': 'screen_devices',
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

  test('AC-048-E9 driver status passes the helper report through', () async {
    final process = FakeScreenProcess();
    final helper = FakeScreenHelper(process);
    final run = runner(helper).run(['screen', 'driver', 'status', '--json']);
    await Future<void>.delayed(Duration.zero);
    expect(helper.startedWith, ['driver', 'status']);
    process.emit({
      'type': 'screen_driver',
      'devices': [
        {
          'serial': 'ABC',
          'instance': r'USB\VID_05AC&PID_12A8\ABC',
          'name': 'iPhone',
          'state': 'smooth',
        },
      ],
    });
    await process.finish();
    await run;
    expect(events().single['devices'], hasLength(1));
  });

  test(
    'AC-048-E10 driver enable needs --udid and runs the helper for that iPhone',
    () async {
      await expectLater(
        runner(
          FakeScreenHelper(FakeScreenProcess()),
        ).run(['screen', 'driver', 'enable']),
        throwsA(isA<UsageException>()),
      );
      final process = FakeScreenProcess();
      final helper = FakeScreenHelper(process);
      final run = runner(
        helper,
      ).run(['screen', 'driver', 'enable', '--udid', 'ABC', '--json']);
      await Future<void>.delayed(Duration.zero);
      expect(helper.startedWith, ['driver', 'enable', '--serial', 'ABC']);
      process.emit({
        'type': 'screen_driver_change',
        'action': 'enable',
        'serial': 'ABC',
        'ok': true,
        'message': 'Done',
        'replug': false,
      });
      await process.finish();
      await run;
      expect(events().single, containsPair('ok', true));
    },
  );

  test(
    'AC-048-E11 a declined or failed switch fails with its message (AC-048-23)',
    () async {
      final process = FakeScreenProcess(code: 1);
      final run = runner(
        FakeScreenHelper(process),
      ).run(['screen', 'driver', 'restore', '--udid', 'ABC', '--json']);
      await Future<void>.delayed(Duration.zero);
      process.emit({
        'type': 'screen_driver_change',
        'action': 'restore',
        'serial': 'ABC',
        'ok': false,
        'message': 'Windows permission was not given. Nothing was changed.',
      });
      await process.finish();
      await expectLater(
        run,
        throwsA(
          isA<CliError>().having(
            (e) => e.message,
            'message',
            contains('Windows permission was not given'),
          ),
        ),
      );
    },
  );

  test(
    'AC-048-E12 once the picture is up, touch starts and the helper gets its address',
    () async {
      final process = FakeScreenProcess();
      final touch = FakeTouch();
      final run = runner(
        FakeScreenHelper(process),
        touch: touch,
      ).run(['screen', 'stream', '--udid', 'ABC123', '--json']);
      await Future<void>.delayed(Duration.zero);
      expect(touch.started, isEmpty, reason: 'not before the picture');
      process.emit(ready);
      await Future<void>.delayed(Duration.zero);
      expect(touch.started, ['ABC123']);
      expect(process.sent, ['wda http://127.0.0.1:18100']);
      process
        ..emit({'type': 'screen_touch', 'available': true})
        ..emit({'type': 'screen_end', 'reason': 'stopped', 'message': ''});
      await process.finish();
      await run;
      expect(events().map((e) => e['type']), [
        'screen_ready',
        'screen_touch',
        'screen_touch',
        'screen_end',
      ]);
      expect(events()[1]['state'], 'starting');
      expect(events()[2]['available'], true);
      expect(touch.link.closed, isTrue, reason: 'touch ends with the screen');
    },
  );

  test(
    'AC-048-E13 no touch helper on the iPhone: the picture goes on, Studio is told why',
    () async {
      final process = FakeScreenProcess();
      final touch = FakeTouch(
        unavailable: const ScreenTouchUnavailable(
          'not_installed',
          WdaScreenTouch.notInstalledMessage,
        ),
      );
      final run = runner(
        FakeScreenHelper(process),
        touch: touch,
      ).run(['screen', 'stream', '--udid', 'ABC123', '--json']);
      await Future<void>.delayed(Duration.zero);
      process.emit(ready);
      await Future<void>.delayed(Duration.zero);
      process.emit({'type': 'screen_end', 'reason': 'stopped', 'message': ''});
      await process.finish();
      await run;
      final off = events().lastWhere((e) => e['type'] == 'screen_touch');
      expect(off['available'], false);
      expect(off['reason'], 'not_installed');
      expect(process.sent, isEmpty);
    },
  );

  test(
    'AC-048-E23 the Apple service cannot reach the phone yet: touch is asked for again by itself',
    () async {
      final process = FakeScreenProcess();
      final touch = FlakyTouch(2);
      final run = runner(
        FakeScreenHelper(process),
        touch: touch,
      ).run(['screen', 'stream', '--udid', 'ABC123', '--json']);
      await Future<void>.delayed(Duration.zero);
      process.emit(ready);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(touch.started, ['ABC123', 'ABC123', 'ABC123']);
      expect(process.sent, ['wda http://127.0.0.1:18100']);
      final touchEvents = events().where((e) => e['type'] == 'screen_touch');
      expect(
        [for (final e in touchEvents) e['reason'] ?? e['state']],
        ['starting', 'unreachable', 'starting', 'unreachable', 'starting'],
      );
      process.emit({'type': 'screen_end', 'reason': 'stopped', 'message': ''});
      await process.finish();
      await run;
    },
  );

  test(
    'AC-048-E14 --no-touch and a picture with its own touch skip touch',
    () async {
      for (final (args, event) in [
        (['--no-touch'], ready),
        (const <String>[], {...ready, 'touch': true}),
      ]) {
        final process = FakeScreenProcess();
        final touch = FakeTouch();
        final run = runner(
          FakeScreenHelper(process),
          touch: touch,
        ).run(['screen', 'stream', '--udid', 'ABC123', '--json', ...args]);
        await Future<void>.delayed(Duration.zero);
        process.emit(event);
        await Future<void>.delayed(Duration.zero);
        process.emit({
          'type': 'screen_end',
          'reason': 'stopped',
          'message': '',
        });
        await process.finish();
        await run;
        expect(touch.started, isEmpty);
      }
    },
  );

  test(
    'AC-048-E15 the touch helper stopping on the phone is reported',
    () async {
      final process = FakeScreenProcess();
      final touch = FakeTouch();
      final run = runner(
        FakeScreenHelper(process),
        touch: touch,
      ).run(['screen', 'stream', '--udid', 'ABC123', '--json']);
      await Future<void>.delayed(Duration.zero);
      process.emit(ready);
      await Future<void>.delayed(Duration.zero);
      touch.link.endedWith.complete('Device is locked');
      await Future<void>.delayed(Duration.zero);
      process.emit({'type': 'screen_end', 'reason': 'stopped', 'message': ''});
      await process.finish();
      await run;
      final off = events().lastWhere((e) => e['type'] == 'screen_touch');
      expect(off['available'], false);
      expect(off['message'], contains('Device is locked'));
    },
  );

  test(
    "AC-048-E16 iOS 27+: Apple's screen service is used (no helper, live touch) and stops with xcross",
    () async {
      final core = FakeCoreDevice(27);
      final helper = FakeScreenHelper(FakeScreenProcess());
      final stopped = Completer<void>();
      final run = runner(
        helper,
        untilStopped: () => stopped.future,
        coreDevice: core,
      ).run(['screen', 'stream', '--udid', 'NEW27', '--json']);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(core.startedFor, 'NEW27');
      expect(helper.startedWith, isNull);
      stopped.complete();
      await run;
      expect(core.session.stopped, isTrue);
      final e = events();
      expect(e.map((x) => x['type']), [
        'screen_preparing',
        'screen_ready',
        'screen_end',
      ]);
      expect(e[1], containsPair('method', 'coredevice'));
      expect(e[1], containsPair('touch', true));
      expect(e[1], containsPair('viewer', 'http://127.0.0.1:7/'));
      expect(e[2], containsPair('reason', 'stopped'));
    },
  );

  test('AC-048-E17 older iPhones keep the USB picture', () async {
    final core = FakeCoreDevice(16);
    final process = FakeScreenProcess();
    final helper = FakeScreenHelper(process);
    final run = runner(
      helper,
      coreDevice: core,
    ).run(['screen', 'stream', '--udid', 'OLD16', '--json']);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(core.startedFor, isNull);
    expect(helper.startedWith, ['stream', '--serial', 'OLD16']);
    await process.finish();
    await run;
  });
}

final class FakeCoreDevice implements CoreDeviceScreen {
  FakeCoreDevice(this.major);

  final int major;
  String? startedFor;
  final session = FakeCoreSession();

  @override
  Future<int> iosMajor(String udid) async => major;

  @override
  Future<CoreDeviceScreenSession> start(String udid) async {
    startedFor = udid;
    return session;
  }
}

final class FakeCoreSession implements CoreDeviceScreenSession {
  final _exit = Completer<int>();
  bool stopped = false;

  @override
  Uri get viewer => Uri.parse('http://127.0.0.1:7/');

  @override
  Stream<String> get output => const Stream.empty();

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Future<void> stop() async {
    stopped = true;
    if (!_exit.isCompleted) _exit.complete(0);
  }
}
