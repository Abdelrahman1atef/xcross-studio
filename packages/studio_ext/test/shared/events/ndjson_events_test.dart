// studio: 012 — XCROSS_EVENTS=ndjson events and their contract.
import 'dart:convert';

import 'package:cli_kit/shared/logging/logging.dart';
import 'package:cli_kit/shared/progress/progress.dart';
import 'package:studio_ext/shared/events/ndjson_events.dart';
import 'package:test/test.dart';

import '../../support/json_schema_lite.dart';

void main() {
  final schema = JsonSchemaLite.buildEventsContract();
  late List<int> bytes;
  late NdjsonEvents events;
  late Log log;

  setUp(() {
    bytes = [];
    events = NdjsonEvents(bytes.addAll);
    log = Log(output: events.logOutput, events: events);
  });

  List<String> lines() => const LineSplitter().convert(utf8.decode(bytes));
  List<Map<String, Object?>> decoded() => [
    for (final line in lines())
      (jsonDecode(line) as Map).cast<String, Object?>(),
  ];

  test('AC-012-2 only XCROSS_EVENTS=ndjson enables events', () {
    expect(NdjsonEvents.fromEnvironment({}, bytes.addAll), isNull);
    expect(
      NdjsonEvents.fromEnvironment({'XCROSS_EVENTS': 'text'}, bytes.addAll),
      isNull,
    );
    expect(
      NdjsonEvents.fromEnvironment({'XCROSS_EVENTS': ' NDJSON '}, bytes.addAll),
      isNotNull,
    );
  });

  test('AC-012-2 every event kind matches the contract, ASCII only', () async {
    log
      ..logInfo('Version', '1.0.7 (7) from pubspec.yaml')
      ..logWarn(
        '[build.asset_catalog_skipped] Assets.xcassets was not compiled.\n'
        '  hint: Install AssetKit.',
      )
      ..logWarn('Could not read the device OS version.')
      ..logError(
        'error: [device.not_found] No iPhone is connected by USB.\n'
        'hint: Connect it and tap Trust.',
      );
    final step = log.beginStep('Compiling Runner')..log('swiftc …\n');
    step.done();
    await expectLater(
      log.logStep<void>('Signing', () async => throw StateError('x')),
      throwsStateError,
    );
    final bar = ProgressBar('Downloading engine', log: log, total: 4);
    for (var i = 0; i <= 4; i++) {
      bar.update(i);
    }
    bar.finish();
    log.output.stdout('raw tool line ✓');
    log.output.write('partial ');
    log.output.write('line\r\n');
    events
      ..event('artifact', {'kind': 'ipa', 'path': '/work/app/build/x.ipa'})
      ..event('device', {
        'name': 'iPhone',
        'osVersion': '16.7.16',
        'legacy': true,
        'connection': 'usb',
      })
      ..event('check', {
        'section': 'Device service',
        'name': 'usbmuxd',
        'status': 'success',
        'message': 'Found',
        'path': null,
      })
      ..event('done', {'exitCode': 0});

    for (final line in lines()) {
      expect(line.codeUnits.every((u) => u < 0x7f), isTrue, reason: line);
      expect(schema.validate(jsonDecode(line)), isEmpty, reason: line);
    }
    final all = decoded();
    expect(
      {for (final e in all) e['type']},
      {
        'log',
        'warning',
        'error',
        'step',
        'progress',
        'artifact',
        'device',
        'check',
        'done',
      },
    );

    final coded = all.firstWhere((e) => e['type'] == 'warning');
    expect(coded, {
      'v': 1,
      'type': 'warning',
      'code': 'build.asset_catalog_skipped',
      'message': 'Assets.xcassets was not compiled.',
      'hint': 'Install AssetKit.',
    });
    expect(all.where((e) => e['type'] == 'warning').last['code'], isNull);
    expect(all.firstWhere((e) => e['type'] == 'error'), {
      'v': 1,
      'type': 'error',
      'code': 'device.not_found',
      'message': 'No iPhone is connected by USB.',
      'hint': 'Connect it and tap Trust.',
    });
    expect(
      [
        for (final e in all)
          if (e['type'] == 'step') '${e['name']}:${e['status']}',
      ],
      [
        'Compiling Runner:start',
        'Compiling Runner:done',
        'Signing:start',
        'Signing:failed',
      ],
    );
    expect(
      all.firstWhere((e) => e['step'] == 'Compiling Runner')['message'],
      'swiftc …',
    );
    expect(
      [
        for (final e in all)
          if (e['type'] == 'progress') e['fraction'],
      ],
      [0.0, 0.25, 0.5, 0.75, 1.0, 1.0],
    );
    final raw = [
      for (final e in all)
        if (e['stream'] == 'stdout') e['message'],
    ];
    expect(raw, ['raw tool line ✓', 'partial line']);
  });

  test('AC-012-2 coded text parsing', () {
    expect(
      NdjsonEvents.parseCoded('[install.no_app] x.ipa has 0 app bundles.'),
      (code: 'install.no_app', message: 'x.ipa has 0 app bundles.', hint: null),
    );
    expect(NdjsonEvents.parseCoded('Doctor found 1 failure.'), (
      code: null,
      message: 'Doctor found 1 failure.',
      hint: null,
    ));
    expect(NdjsonEvents.parseCoded('warning: [a.b] m\n  hint: one\n  two'), (
      code: 'a.b',
      message: 'm',
      hint: 'one\ntwo',
    ));
    expect(NdjsonEvents.stripAnsi('\x1B[32m✓\x1B[0m ok'), '✓ ok');
  });
}
