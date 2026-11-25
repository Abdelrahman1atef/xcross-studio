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
  final lines = StreamController<String>.broadcast();
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
  FakeTools({
    required this.version,
    required this.apps,
    this.runnerStarts = const [true],
    this.failApps = false,
  });

  /// `apps list` cannot be answered (a phone in Smooth mode is hidden from
  /// Apple's service over USB).
  final bool failApps;

  final String version;
  final Map<String, Object?> apps;

  /// Per XCTest start: true = the touch helper comes up, false = it closes
  /// early (as right after a previous session); the last value repeats.
  final List<bool> runnerStarts;
  int _runnerAttempts = 0;
  final runs = <List<String>>[];
  final started = <FakeTouchProcess>[];

  @override
  Future<String> run(List<String> args, {required Duration timeout}) async {
    runs.add(args);
    if (failApps && args.take(2).join(' ') == 'apps list') {
      throw Exception('usbmux has no device matching udid');
    }
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
    if (args.contains('xcuitest')) {
      final i = _runnerAttempts++;
      final ok =
          runnerStarts[i < runnerStarts.length ? i : runnerStarts.length - 1];
      Timer.run(() {
        if (ok) {
          p.lines.add(
            'PC pymobiledevice3.x[1] INFO [IDE] didBeginExecutingTestPlan',
          );
        } else {
          p.lines.add(
            'PC pymobiledevice3.x[1] ERROR The DTX connection closed before '
            'the device opened the expected proxied service.',
          );
          p.exit.complete(1);
        }
      });
    }
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
      final link = await WdaScreenTouch(
        tools,
        retryDelay: Duration.zero,
      ).start('UDID1');
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
    await WdaScreenTouch(tools, retryDelay: Duration.zero).start('UDID2');
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
        WdaScreenTouch(tools, retryDelay: Duration.zero).start('UDID3'),
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
    'AC-048-T3b the phone cannot be asked (Smooth mode hides it): unreachable, not not_installed',
    () async {
      final tools = FakeTools(
        version: '16.7',
        apps: const {'a.xctrunner': _runner},
        failApps: true,
      );
      await expectLater(
        WdaScreenTouch(tools, retryDelay: Duration.zero).start('UDID3'),
        throwsA(
          isA<ScreenTouchUnavailable>().having(
            (e) => e.reason,
            'reason',
            'unreachable',
          ),
        ),
      );
      expect(tools.started, isEmpty);
      expect(
        tools.runs.where((r) => r.take(2).join(' ') == 'apps list'),
        hasLength(4),
        reason: 'two queries, twice',
      );
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

  test(
    'AC-048-T9 the touch helper closing early (just after a previous session) is started again',
    () async {
      final tools = FakeTools(
        version: '16.7.16',
        apps: {'a.xctrunner': _runner},
        runnerStarts: [false, true],
      );
      final link = await WdaScreenTouch(
        tools,
        retryDelay: Duration.zero,
      ).start('UDID1');
      final runners = tools.started.where((p) => p.args.contains('xcuitest'));
      expect(runners, hasLength(2));
      expect(runners.first.killed, isTrue);
      expect(tools.started.last.args.take(2), ['usbmux', 'forward']);
      expect(link.url, 'http://127.0.0.1:18100');
    },
  );

  test(
    'AC-048-T10 it keeps closing: touch is off with the reason, no forward left',
    () async {
      final tools = FakeTools(
        version: '16.7.16',
        apps: {'a.xctrunner': _runner},
        runnerStarts: [false],
      );
      await expectLater(
        WdaScreenTouch(tools, retryDelay: Duration.zero).start('UDID1'),
        throwsA(
          isA<ScreenTouchUnavailable>()
              .having((e) => e.reason, 'reason', 'error')
              .having((e) => e.message, 'message', contains('DTX connection')),
        ),
      );
      expect(tools.started, hasLength(3), reason: 'three tries, no forward');
      expect(tools.started.every((p) => p.killed), isTrue);
    },
  );
}
