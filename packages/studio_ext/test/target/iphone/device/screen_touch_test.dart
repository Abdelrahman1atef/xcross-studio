// studio: 048 — touch through WebDriverAgent (specs: 048-iphone-screen).
import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:studio_ext/src/target/iphone/device/screen_touch_link.dart';
import 'package:studio_ext/target/iphone/device/screen_touch.dart';
import 'package:test/test.dart';

@internal
final class FakeTouchProcess implements TouchProcess {
  FakeTouchProcess(this.args);

  final List<String> args;
  final lines = StreamController<String>();
  final exit = Completer<int>();
  bool killed = false;

  @override
  Stream<String> get output => lines.stream;

  @override
  Future<int> get exitCode => exit.future;

  @override
  Future<void> kill() async {
    killed = true;
    unawaited(lines.close());
    if (!exit.isCompleted) exit.complete(-1);
  }
}

@internal
final class FakeTools implements ScreenTouchTools {
  FakeTools({required this.version, required this.apps});

  final String version;
  final Map<String, Object?> apps;
  final runs = <List<String>>[];
  final started = <FakeTouchProcess>[];

  @override
  Future<String> run(List<String> args, {required Duration timeout}) async {
    runs.add(args);
    return switch (args.take(2).join(' ')) {
      'lockdown info' => jsonEncode({'ProductVersion': version}),
      'apps list' => jsonEncode(apps),
      _ => '',
    };
  }

  @override
  Future<TouchProcess> start(List<String> args) async {
    final p = FakeTouchProcess(args);
    started.add(p);
    return p;
  }

  @override
  Future<int> freePort() async => 18100;
}

const _runner = {'CFBundleExecutable': WdaScreenTouch.runnerExecutable};

void main() {
  test(
    'AC-048-T1 iOS 16: finds the runner by its executable, mounts, starts XCTest and the forward',
    () async {
      final tools = FakeTools(
        version: '16.7.16',
        apps: {
          'com.example.app': {'CFBundleExecutable': 'Runner'},
          'com.other.wda.xctrunner': _runner,
          'com.team.xcross.touch.xctrunner': _runner,
        },
      );
      final link = await WdaScreenTouch(tools).start('UDID1');
      expect(link.url, 'http://127.0.0.1:18100');
      expect(tools.runs.map((r) => r.take(2).join(' ')), [
        'lockdown info',
        'apps list',
        'mounter auto-mount',
      ]);
      expect(tools.runs.last, ['mounter', 'auto-mount', '--udid', 'UDID1']);
      expect(tools.started.map((p) => p.args), [
        [
          'developer',
          'dvt',
          'xcuitest',
          '--udid',
          'UDID1',
          'com.team.xcross.touch.xctrunner',
        ],
        ['usbmux', 'forward', '--serial', 'UDID1', '18100', '8100'],
      ]);
      await link.close();
      expect(tools.started.every((p) => p.killed), isTrue);
    },
  );

  test('AC-048-T2 iOS 17 and later go through the tunnel', () async {
    final tools = FakeTools(version: '17.5', apps: {'a.xctrunner': _runner});
    await WdaScreenTouch(tools).start('UDID2');
    expect(tools.started.first.args, [
      'developer',
      'dvt',
      'xcuitest',
      '--tunnel',
      'UDID2',
      'a.xctrunner',
    ]);
  });

  test(
    'AC-048-T3 no runner on the phone: not_installed, nothing started',
    () async {
      final tools = FakeTools(
        version: '16.7',
        apps: {
          'com.example.app': {'CFBundleExecutable': 'Runner'},
        },
      );
      await expectLater(
        WdaScreenTouch(tools).start('UDID3'),
        throwsA(
          isA<ScreenTouchUnavailable>().having(
            (e) => e.reason,
            'reason',
            'not_installed',
          ),
        ),
      );
      expect(tools.started, isEmpty);
    },
  );

  test(
    'AC-048-T4 the link ends when XCTest ends, with its last error line',
    () async {
      final runner = FakeTouchProcess(const []);
      final forward = FakeTouchProcess(const []);
      final link = WdaTouchLink(
        url: 'http://127.0.0.1:1',
        runner: runner,
        forward: forward,
      );
      runner.lines
        ..add('2026-11-23 16:25:17 PC pymobiledevice3.x[1] INFO starting')
        ..add(
          '2026-11-23 16:25:18 PC pymobiledevice3.x[1] ERROR Device is locked',
        );
      await Future<void>.delayed(Duration.zero);
      runner.exit.complete(1);
      expect(await link.ended, 'Device is locked');
    },
  );
}
