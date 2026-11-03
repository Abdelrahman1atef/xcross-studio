// studio: 022 — `xcross project version`: change the version and build number
// from the Release page (specs/022-studio-release-flow, AC-022-9).
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_kit/composition/native_host.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/flutter/project/pubspec_version.dart';
import 'package:xcross/src/target/iphone/cli/basic/project_command.dart';

void main() {
  late Directory root;
  late StringBuffer out;

  setUp(() {
    root = Directory.systemTemp.createTempSync('project-version-');
    out = StringBuffer();
  });
  tearDown(() => root.deleteSync(recursive: true));

  void pubspec(String text) =>
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(text);
  String read() => File(p.join(root.path, 'pubspec.yaml')).readAsStringSync();

  Future<void> run(List<String> args) =>
      (CommandRunner<void>('xcross', 'test')..addCommand(
            ProjectCommand(
              fileSystem: detectPlatformHost().fileSystem,
              paths: p.context,
              projectRoot: () => root.path,
              environment: const {},
              write: out.write,
            ),
          ))
          .run(['project', 'version', ...args]);

  Map<String, Object?> json() =>
      jsonDecode(out.toString().trim()) as Map<String, Object?>;

  group('PubspecVersion', () {
    test('parse', () {
      expect(PubspecVersion.parse('1.2.3+7')?.text, '1.2.3+7');
      expect(PubspecVersion.parse('2.0')?.build, isNull);
      expect(PubspecVersion.parse('1.2.3.4'), isNull);
      expect(PubspecVersion.parse('1.x'), isNull);
      expect(PubspecVersion.parse('1.0.0+b'), isNull);
    });

    test('bump: a new version raises the build number too', () {
      const v = PubspecVersion('1.4.9', 41);
      expect(v.bump(VersionPart.build).text, '1.4.9+42');
      expect(v.bump(VersionPart.patch).text, '1.4.10+42');
      expect(v.bump(VersionPart.minor).text, '1.5.0+42');
      expect(v.bump(VersionPart.major).text, '2.0.0+42');
      expect(
        const PubspecVersion('2', null).bump(VersionPart.patch).text,
        '2.0.1+1',
      );
    });

    test('write keeps quotes, comments, CRLF and every other line', () {
      const source =
          "name: app\r\nversion: '1.0.0+1' # store\r\n"
          'environment:\r\n  sdk: ^3.0.0\r\n';
      expect(
        PubspecVersion.write(source, const PubspecVersion('1.1.0', 2)),
        "name: app\r\nversion: '1.1.0+2' # store\r\n"
        'environment:\r\n  sdk: ^3.0.0\r\n',
      );
      // A nested `version:` (a dependency's) is not the app's.
      expect(
        PubspecVersion.read(
          'name: app\ndependencies:\n  foo:\n    version: 9.9.9\n',
        ),
        isNull,
      );
      expect(
        PubspecVersion.write(
          'name: app\nflutter:\n',
          const PubspecVersion('1.0.0', 1),
        ),
        'name: app\nversion: 1.0.0+1\nflutter:\n',
      );
    });
  });

  test('AC-022-9 shows the version without changing anything', () async {
    pubspec('name: app\nversion: 1.0.7+7\n');
    await run(['--json']);
    expect(json(), {
      'v': 1,
      'type': 'project_version',
      'version': '1.0.7',
      'build': 7,
      'previous': null,
      'changed': false,
      'pubspec': p.join(root.path, 'pubspec.yaml'),
    });
    expect(read(), 'name: app\nversion: 1.0.7+7\n');
  });

  test('AC-022-9 sets the version and the build number', () async {
    pubspec('name: app\nversion: 1.0.7+7 # release\nflutter:\n');
    await run(['1.1.0', '--build', '12']);
    expect(read(), 'name: app\nversion: 1.1.0+12 # release\nflutter:\n');
    expect(out.toString(), contains('Saved in pubspec.yaml (was 1.0.7+7)'));

    out.clear();
    await run(['--build', '13', '--json']);
    expect(read(), contains('version: 1.1.0+13'));
    expect(json()['previous'], '1.1.0+12');
    expect(json()['changed'], isTrue);
  });

  test('AC-022-9 bumps', () async {
    pubspec('name: app\nversion: 1.0.7+7\n');
    await run(['--bump', 'build']);
    expect(read(), contains('version: 1.0.7+8'));
    await run(['--bump', 'patch']);
    expect(read(), contains('version: 1.0.8+9'));
    await run(['--bump', 'minor']);
    expect(read(), contains('version: 1.1.0+10'));
  });

  test('AC-022-9 bad input is a usage error and changes nothing', () async {
    pubspec('name: app\nversion: 1.0.7+7\n');
    for (final args in [
      ['1.2.3.4'],
      ['--build', '0'],
      ['--build', 'x'],
      ['1.2.3', '--bump', 'patch'],
    ]) {
      await expectLater(
        run(args),
        throwsA(isA<UsageException>()),
        reason: '$args',
      );
    }
    expect(read(), 'name: app\nversion: 1.0.7+7\n');
  });
}
