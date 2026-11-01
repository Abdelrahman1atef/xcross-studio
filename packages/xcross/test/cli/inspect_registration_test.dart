// studio: registration of the fork's `xcross inspect` command (feature 001).
import 'package:studio_ext/shared/inspect/inspect_command.dart';
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
}
