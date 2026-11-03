// studio: 022 — `xcross release gate` and `xcross release ci`.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_kit/composition/native_host.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/appstore/command_exit.dart';
import 'package:studio_ext/shared/release/release_check_command.dart';
import 'package:studio_ext/src/shared/release/analyzer_output.dart';
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

  Future<void> run(
    List<String> args, {
    int analyze = 0,
    int test = 0,
    String? analyzeOutput,
  }) =>
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
                      output:
                          arguments.first == 'analyze' && analyzeOutput != null
                          ? analyzeOutput
                          : failed == 0
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
        ['/sdk/bin/flutter', 'analyze', '--no-fatal-infos', root.path],
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

    // What a project with one deprecated parameter printed: `pub get` first,
    // then the issue (its message has ` - ` in it).
    const oneInfo = r'''
Resolving dependencies...
Downloading packages...
  web 1.1.1 (1.1.2 available)
  yaml 3.1.3 (3.1.4 available)
Got dependencies!
164 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Analyzing app...

   info - 'encryptedSharedPreferences' is deprecated. Remove this parameter - it will be ignored - lib\core\cache\secure_storage.dart:7:30 - deprecated_member_use

1 issue found. (ran in 3.1s)
''';

    test('an info does not fail the gate; the issue is listed, '
        'the pub output is not', () async {
      await run(['gate', '--json'], analyzeOutput: oneInfo);
      final json = jsonDecode(out.toString().trim()) as Map;
      final analyze = (json['steps'] as List).first as Map;
      expect(analyze['passed'], isTrue);
      expect(analyze['infos'], 1);
      expect(analyze['errors'], 0);
      final issue = (analyze['issues'] as List).single as Map;
      expect(issue['severity'], 'info');
      expect(issue['code'], 'deprecated_member_use');
      expect(issue['file'], r'lib\core\cache\secure_storage.dart');
      expect(issue['line'], 7);
      expect(issue['column'], 30);
      expect(
        issue['message'],
        endsWith('Remove this parameter - it will be ignored'),
      );
      final tail = (analyze['tail'] as List).join('\n');
      expect(tail, isNot(contains('available')));
      expect(tail, isNot(contains('Got dependencies')));
      expect(tail, isNot(contains('pub outdated')));
      expect(tail, contains('1 issue found'));
    });

    test('text output lists the info and says how to make it fail', () async {
      await run(['gate', '--skip-tests'], analyzeOutput: oneInfo);
      expect(out.toString(), contains('✓ flutter analyze (1 info)'));
      expect(out.toString(), contains('deprecated_member_use'));
      expect(out.toString(), contains('--fatal-infos'));
    });

    test('--fatal-infos asks flutter analyze to fail on infos', () async {
      await expectLater(
        run(
          ['gate', '--fatal-infos', '--skip-tests'],
          analyze: 1,
          analyzeOutput: oneInfo,
        ),
        throwsA(isA<CommandExit>()),
      );
      expect(ran.single.sublist(1, 3), ['analyze', '--fatal-infos']);
      expect(out.toString(), contains('✗ flutter analyze (1 info)'));
    });

    test('older bullet output, dart analyze order and errors are read', () {
      final issues = AnalyzerOutput.issues([
        "  error • Undefined name 'x' • lib/main.dart:3:9 • undefined_identifier",
        'warning - Unused import - lib/a.dart:1:8 - unused_import',
        r'  error - lib\b.dart:89:39 - Expected to find ";". - expected_token',
        'Analyzing app...',
      ]);
      expect(issues.map((i) => i.severity), ['error', 'warning', 'error']);
      expect(issues.first.location, 'lib/main.dart:3:9');
      expect(issues[1].code, 'unused_import');
      expect(issues.last.location, r'lib\b.dart:89:39');
      expect(issues.last.message, 'Expected to find ";".');
      expect(issues.last.code, 'expected_token');
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
