// studio: `xcross engine info`, the identity XCross Studio checks.
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:studio_ext/shared/engine/engine_info_command.dart';
import 'package:test/test.dart';

void main() {
  late StringBuffer out;
  late CommandRunner<void> runner;
  setUp(() {
    out = StringBuffer();
    runner = CommandRunner<void>('xcross', 'test')
      ..addCommand(EngineCommand(version: '2.0.9', write: out.write));
  });

  test('--json prints the one-line engine_info contract', () async {
    await runner.run(['engine', 'info', '--json']);
    final text = out.toString();
    expect(text, endsWith('\n'));
    expect(const LineSplitter().convert(text.trim()), hasLength(1));
    expect(jsonDecode(text), {
      'v': 1,
      'type': 'engine_info',
      'engine': 'xcross-studio',
      'protocol': EngineIdentity.protocol,
      'version': '2.0.9',
    });
    expect(EngineIdentity.protocol, greaterThanOrEqualTo(1));
  });

  test('without --json it prints readable text', () async {
    await runner.run(['engine', 'info']);
    expect(out.toString(), contains('Engine     xcross-studio'));
    expect(out.toString(), contains('Protocol   ${EngineIdentity.protocol}'));
    expect(out.toString(), contains('Version    2.0.9'));
  });

  test('extra arguments are a usage error', () {
    expect(
      runner.run(['engine', 'info', 'extra']),
      throwsA(isA<UsageException>()),
    );
  });
}
