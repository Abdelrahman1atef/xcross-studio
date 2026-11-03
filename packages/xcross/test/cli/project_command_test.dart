// studio: 016 — `xcross project bundle-id` (specs/016-push-firebase-maps).
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_kit/composition/native_host.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/errors/errors.dart';
import 'package:xcross/src/target/iphone/cli/basic/project_command.dart';

void main() {
  late Directory root;
  late StringBuffer out;

  setUp(() {
    root = Directory.systemTemp.createTempSync('project-command-');
    out = StringBuffer();
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
      'name: app\n# keep me\ndependencies:\n  flutter:\n    sdk: flutter\n',
    );
    final project = Directory(p.join(root.path, 'ios', 'Runner.xcodeproj'))
      ..createSync(recursive: true);
    File(p.join(project.path, 'project.pbxproj')).writeAsStringSync(
      '// !\$*UTF8*\$!\n{ objects = { };\n'
      '  PRODUCT_BUNDLE_IDENTIFIER = com.example.app;\n}\n',
    );
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<void> run(
    List<String> args, {
    Map<String, String> environment = const {},
  }) =>
      (CommandRunner<void>('xcross', 'test')..addCommand(
            ProjectCommand(
              fileSystem: detectPlatformHost().fileSystem,
              paths: p.context,
              projectRoot: () => root.path,
              environment: environment,
              write: out.write,
            ),
          ))
          .run(['project', 'bundle-id', ...args]);

  String pubspec() =>
      File(p.join(root.path, 'pubspec.yaml')).readAsStringSync();

  test('AC-016-2 shows the bundle ID and the real-ID default', () async {
    await run([]);
    expect(
      out.toString(),
      allOf(
        contains('Bundle ID      com.example.app'),
        contains('Saved choice   not saved'),
        contains('Next build     the real App ID com.example.app (default'),
      ),
    );
  });

  test('AC-016-2 saves a choice and keeps the rest of pubspec.yaml', () async {
    await run(['prefixed']);
    expect(pubspec(), contains('# keep me'));
    expect(pubspec(), contains('xcross:\n  bundle_id: prefixed'));
    expect(out.toString(), contains('Saved bundle_id: prefixed'));
    expect(out.toString(), contains('the prefixed App ID XCR-<identity>.'));

    out.clear();
    await run(['original', '--json']);
    expect(pubspec(), contains('bundle_id: original'));
    expect(jsonDecode(out.toString()), {
      'v': 1,
      'type': 'bundle_id',
      'bundleId': 'com.example.app',
      'saved': 'original',
      'override': null,
      'settingsPath': p.join(root.path, 'pubspec.yaml'),
      'next': 'original',
    });
  });

  test('AC-016-2 reports the XCROSS_BUNDLE_ID override', () async {
    await run(['--json'], environment: {'XCROSS_BUNDLE_ID': 'prefixed'});
    final json = jsonDecode(out.toString()) as Map<String, Object?>;
    expect(json['override'], 'prefixed');
    expect(json['saved'], isNull);
    expect(json['next'], 'prefixed');
  });

  test('AC-016-2 refuses an unknown value with a usage error', () {
    expect(run(['maybe']), throwsA(isA<UsageException>()));
    expect(pubspec(), isNot(contains('bundle_id')));
  });

  test('AC-016-2 outside a project is an error', () {
    final empty = Directory.systemTemp.createTempSync('no-project-');
    addTearDown(() => empty.deleteSync(recursive: true));
    final runner = CommandRunner<void>('xcross', 'test')
      ..addCommand(
        ProjectCommand(
          fileSystem: detectPlatformHost().fileSystem,
          paths: p.context,
          projectRoot: () => empty.path,
          environment: const {},
          write: out.write,
        ),
      );
    expect(runner.run(['project', 'bundle-id']), throwsA(isA<XcrossError>()));
  });
}
