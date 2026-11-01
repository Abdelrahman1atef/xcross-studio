// studio: registration of the fork's `xcross inspect` command (feature 001).
import 'package:studio_ext/shared/inspect/inspect_command.dart';
import 'package:studio_ext/target/iphone/device/app_command.dart';
import 'package:studio_ext/target/iphone/device/crashes_command.dart';
import 'package:studio_ext/target/iphone/device/logs_command.dart';
import 'package:test/test.dart';
import 'package:xcross/src/composition/cli/runner.dart';

import 'runtime_fixture.dart';

void main() {
  final runner = XcrossCli.buildRunner(
    testApplication(),
    configTerminal: TestTerminal(),
  );

  test('the top-level runner registers inspect', () {
    expect(runner.commands['inspect'], isA<InspectCommand>());
  });

  test('inspect --json owns stdout; the plain summary does not', () {
    expect(
      XcrossCli.ownsMachineStdout(['inspect', 'app.ipa', '--json'], runner),
      isTrue,
    );
    expect(
      XcrossCli.ownsMachineStdout(['inspect', 'app.ipa'], runner),
      isFalse,
    );
  });

  // studio: 010
  test('the device commands are registered and their --json owns stdout', () {
    expect(runner.commands['logs'], isA<LogsCommand>());
    expect(runner.commands['app'], isA<AppCommand>());
    expect(runner.commands['crashes'], isA<CrashesCommand>());
    for (final args in [
      ['logs', '--json'],
      ['app', 'info', 'a.b', '--json'],
      ['crashes', 'list', '--json'],
    ]) {
      expect(
        XcrossCli.ownsMachineStdout(args, runner),
        isTrue,
        reason: '$args',
      );
    }
    expect(XcrossCli.ownsMachineStdout(['logs'], runner), isFalse);
    expect(
      XcrossCli.ownsMachineStdout(['crashes', 'pull', '--latest'], runner),
      isFalse,
    );
  });
}
