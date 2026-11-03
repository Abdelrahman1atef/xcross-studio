// studio: 018 — `flutter build --export-method app-store` checks the App
// Store Connect key before it compiles: a missing or individual key used to
// stop the build only after minutes of compiling (AC-018-4).
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/composition/cli/runner.dart';

import '../../cli/runtime_fixture.dart';
import '../../log_fixture.dart';

void main() {
  late Directory root;
  late Directory previous;

  setUp(() {
    root = Directory.systemTemp.createTempSync('app-store-preflight-');
    previous = Directory.current;
    // An empty folder: had the build started, it would fail on the missing
    // project instead of on the key.
    Directory.current = Directory(p.join(root.path, 'app'))..createSync();
  });
  tearDown(() {
    Directory.current = previous;
    root.deleteSync(recursive: true);
  });

  test('no saved team key stops the build before it compiles', () async {
    final application = testApplication(
      environment: {
        'HOME': root.path,
        'XDG_CONFIG_HOME': p.join(root.path, 'config'),
        'XCROSS_NO_UPDATE_CHECK': '1',
      },
    );
    final code = await XcrossCli.run(
      ['flutter', 'build', '--release', '--export-method', 'app-store'],
      application,
      configTerminal: TestTerminal(),
    );
    final messages = (application.runtime.log.output as TestLogOutput).messages
        .join('\n');
    expect(code, isNot(0));
    expect(messages, contains('Admin or App Manager'));
    expect(messages, isNot(contains('pubspec')));
    expect(messages, isNot(contains('Resolving dependencies')));
  });
}
