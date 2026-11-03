// studio: 022 — `xcross release gate` and `xcross release ci`.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_kit/composition/native_host.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/appstore/command_exit.dart';
import 'package:studio_ext/shared/release/release_check_command.dart';
import 'package:studio_ext/src/shared/release/ci_template.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late StringBuffer out;
  late List<List<String>> ran;

  setUp(() {
    root = Directory.systemTemp.createTempSync('release-gate-');
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: app\n');
    out = StringBuffer();
    ran = [];
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<void> run(List<String> args, {int analyze = 0, int test = 0}) =>
      (CommandRunner<void>('xcross', 't')..addCommand(
            ReleaseCommand(
              fileSystem: detectPlatformHost().fileSystem,
              paths: p.context,
              currentDirectory: () => root.path,
              write: out.write,
              flutter: (projectRoot) async => '/sdk/bin/flutter',
              runTool:
                  (executable, arguments, {required workingDirectory}) async {
                    ran.add([executable, ...arguments, workingDirectory]);
                    final failed = arguments.first == 'analyze'
                        ? analyze
                        : test;
                    return (
                      exitCode: failed,
                      output: failed == 0
                          ? 'No issues found!'
                          : List.generate(30, (i) => 'line $i').join('\n'),
                    );
                  },
            ),
          ))
          .run(['release', ...args]);

  group('AC-022-5 the quality gate', () {
    test('runs analyze and test in the project', () async {
      await run(['gate', '--json']);
      expect(ran, [
        ['/sdk/bin/flutter', 'analyze', root.path],
        ['/sdk/bin/flutter', 'test', root.path],
      ]);
      final json = jsonDecode(out.toString().trim()) as Map;
      expect(json['type'], 'release_gate');
      expect(
        (json['steps'] as List).every((s) => (s as Map)['passed'] == true),
        isTrue,
      );
    });

    test('a failing test fails the gate with the last lines', () async {
      await expectLater(
        run(['gate'], test: 1),
        throwsA(
          isA<CommandExit>().having(
            (e) => e.message,
            'message',
            contains('flutter test'),
          ),
        ),
      );
      expect(out.toString(), contains('✓ flutter analyze'));
      expect(out.toString(), contains('✗ flutter test'));
      expect(out.toString(), contains('line 29'));
      expect(out.toString(), isNot(contains('line 0\n')));
    });

    test('--skip-tests runs analyze only', () async {
      await run(['gate', '--skip-tests']);
      expect(ran.single[1], 'analyze');
    });
  });

  group('AC-022-6 the CI workflow', () {
    test('writes the template and refuses to overwrite', () async {
      await run(['ci']);
      final file = File(
        p.join(root.path, '.github', 'workflows', 'xcross-testflight.yml'),
      );
      expect(file.readAsStringSync(), CiTemplate.githubTestflight.trimLeft());
      expect(file.readAsStringSync(), contains('runs-on: ubuntu-latest'));
      expect(out.toString(), contains('XCODE_XIP_URL'));
      await expectLater(run(['ci']), throwsA(isA<CommandExit>()));
      await run(['ci', '--force']);
    });

    test('the template matches docs/ci/github-testflight.yml', () {
      final docs = File(
        p.join('..', '..', 'docs', 'ci', 'github-testflight.yml'),
      );
      if (!docs.existsSync()) return;
      expect(CiTemplate.githubTestflight.trimLeft(), docs.readAsStringSync());
    });
  });
}
