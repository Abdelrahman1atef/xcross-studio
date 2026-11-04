// studio: 025 — a tool that went silent after an error.
import 'dart:async';

import 'package:cli_kit/shared/process/error_stall_watchdog.dart';
import 'package:test/test.dart';

void main() {
  const limit = Duration(milliseconds: 40);
  const longer = Duration(milliseconds: 120);

  Future<void> wait(Duration duration) => Future<void>.delayed(duration);

  test('silence without an error is not a stall: builds can be quiet', () async {
    var stalled = 0;
    final watchdog = ErrorStallWatchdog(limit: limit, onStall: () => stalled++)
      ..saw('Compiling one thing');
    await wait(longer);
    expect(stalled, 0);
    expect(watchdog.stalled, isFalse);
    watchdog.stop();
  });

  test('silence after an error is', () async {
    var stalled = 0;
    final watchdog = ErrorStallWatchdog(limit: limit, onStall: () => stalled++)
      ..saw('a.m:1:1: error: nope');
    await wait(longer);
    expect(stalled, 1);
    expect(watchdog.stalled, isTrue);
  });

  test('output after an error means the tool is still working', () async {
    var stalled = 0;
    final watchdog = ErrorStallWatchdog(limit: limit, onStall: () => stalled++)
      ..saw('a.m:1:1: error: nope');
    for (var i = 0; i < 4; i++) {
      await wait(const Duration(milliseconds: 15));
      watchdog.saw('[$i/9] Compiling');
    }
    expect(stalled, 0);
    watchdog.stop();
    await wait(longer);
    expect(stalled, 0);
  });
}
