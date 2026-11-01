// studio: 012 — Log reports to a LogEvents observer instead of its output.
import 'package:cli_kit/shared/logging/logging.dart';
import 'package:cli_kit/shared/progress/progress.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart';

import 'support/log_output.dart';

/// Records what [Log] hands to its observer.
@internal
final class RecordingLogEvents implements LogEvents {
  final calls = <String>[];
  final events = <Map<String, Object?>>[];

  @override
  void message(LogEventLevel level, String message) =>
      calls.add('${level.name}:$message');

  @override
  void stepStarted(String label) => calls.add('start:$label');

  @override
  void stepOutput(String label, String line) =>
      calls.add('output:$label:$line');

  @override
  void stepFinished(
    String label, {
    required bool ok,
    required String message,
    required Duration elapsed,
  }) => calls.add('${ok ? 'done' : 'failed'}:$label:$message');

  @override
  void event(String type, Map<String, Object?> fields) =>
      events.add({'type': type, ...fields});
}

void main() {
  late RecordingLogOutput output;
  late RecordingLogEvents events;
  late Log log;

  setUp(() {
    output = RecordingLogOutput(supportsAnsi: true);
    events = RecordingLogEvents();
    log = Log(output: output, events: events);
  });

  test('AC-012-1 messages go to the observer, not the output', () {
    log
      ..logStatus('status')
      ..logInfo('Device', 'Phone')
      ..logWarn('[build.x] careful\n  hint: fix it')
      ..logError('broken')
      ..logTrace('hidden unless verbose');
    expect(events.calls, [
      'info:status',
      allOf(startsWith('info:'), contains('Device'), contains('Phone')),
      'warn:[build.x] careful\n  hint: fix it',
      'error:broken',
    ]);
    expect(output.lines, isEmpty);
    expect(output.errors, isEmpty);
    expect(output.writes, isEmpty);

    log
      ..setVerbose()
      ..logTrace('detail');
    expect(events.calls.last, 'trace:detail');
  });

  test('AC-012-1 steps report start, output lines and the result', () async {
    final step = log.beginStep('Compiling')..log('line 1\nline 2\npart');
    step.done();
    log.beginStep('Linking').fail('Linking failed');
    await expectLater(
      log.logStep<void>('Signing', () async => throw StateError('no')),
      throwsStateError,
    );
    expect(events.calls, [
      'start:Compiling',
      'output:Compiling:line 1',
      'output:Compiling:line 2',
      'done:Compiling:Compiling',
      'start:Linking',
      'failed:Linking:Linking failed',
      'start:Signing',
      'failed:Signing:Signing',
    ]);
    expect(output.writes, isEmpty, reason: 'no spinner frames');
  });

  test('AC-012-1 progress bars emit fractions, at most one per percent', () {
    final bar = ProgressBar('Downloading engine', log: log, total: 200);
    for (var i = 0; i <= 200; i++) {
      bar.update(i);
    }
    bar.finish();
    final progress = [
      for (final e in events.events)
        if (e['type'] == 'progress') e,
    ];
    expect(progress.first, {
      'type': 'progress',
      'label': 'Downloading engine',
      'fraction': 0.0,
      'current': 0,
      'total': 200,
      'unit': 'bytes',
    });
    expect(progress.length, 102, reason: '0..100 % plus the final 1.0');
    expect(progress.last['fraction'], 1.0);
    expect(output.writes, isEmpty);
  });

  test('without an observer the human output is unchanged', () {
    final plain = RecordingLogOutput();
    Log(output: plain)
      ..logStatus('status')
      ..logWarn('careful');
    expect(plain.lines, ['status']);
    expect(plain.errors, [' careful']);
  });
}
