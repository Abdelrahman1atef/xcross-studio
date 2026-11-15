// studio: privacy — `xcross privacy init` and the project.pbxproj edit it
// makes.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_kit/composition/native_host.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/permissions/permissions_command.dart';
import 'package:studio_ext/shared/privacy/privacy_command.dart';
import 'package:studio_ext/src/shared/privacy/pbxproj_resources.dart';
import 'package:test/test.dart';

/// Flutter's own iOS app template (3.47), rendered without Swift Package
/// Manager and team.
final _template = File(
  p.join('test', 'shared', 'privacy', 'fixtures', 'flutter_template.pbxproj'),
).readAsStringSync();

void main() {
  group('addRunnerResource', () {
    test('adds the file to the Runner group and the Runner target only', () {
      final result = addRunnerResource(_template, 'PrivacyInfo.xcprivacy');
      expect(result.state, PbxResourceState.added);
      final text = result.text;

      final reference = RegExp(
        r'\t\t([0-9A-F]{24}) /\* PrivacyInfo\.xcprivacy \*/ = \{isa = '
        r'PBXFileReference; lastKnownFileType = text\.xml; path = '
        r'PrivacyInfo\.xcprivacy; sourceTree = "<group>"; \};\n'
        r'/\* End PBXFileReference section \*/',
      ).firstMatch(text);
      expect(reference, isNotNull);
      final referenceId = reference!.group(1)!;
      final buildFile = RegExp(
        r'\t\t([0-9A-F]{24}) /\* PrivacyInfo\.xcprivacy in Resources \*/ '
        r'= \{isa = PBXBuildFile; fileRef = '
        '$referenceId '
        r'/\* PrivacyInfo\.xcprivacy \*/; \};\n'
        r'/\* End PBXBuildFile section \*/',
      ).firstMatch(text);
      expect(buildFile, isNotNull);
      final buildFileId = buildFile!.group(1)!;

      // The Runner group lists the file; the Runner target's resources copy
      // it; RunnerTests' resources do not.
      final runnerGroup = _object(text, '97C146F01CF9000F007C117D');
      expect(
        runnerGroup,
        contains('\t\t\t\t$referenceId /* PrivacyInfo.xcprivacy */,\n'),
      );
      expect(
        _object(text, '97C146EC1CF9000F007C117D'),
        contains(
          '\t\t\t\t$buildFileId /* PrivacyInfo.xcprivacy in Resources */,\n'
          '\t\t\t);',
        ),
      );
      expect(
        _object(text, '331C807F294A63A400263BE5'),
        isNot(contains('Privacy')),
      );

      // Nothing else changed: removing the four new lines gives the original.
      final original = text
          .split('\n')
          .where((line) => !line.contains('PrivacyInfo.xcprivacy'))
          .join('\n');
      expect(original, _template);
    });

    test('a second run finds it listed and changes nothing', () {
      final once = addRunnerResource(_template, 'PrivacyInfo.xcprivacy').text;
      final twice = addRunnerResource(once, 'PrivacyInfo.xcprivacy');
      expect(twice.state, PbxResourceState.listed);
      expect(twice.text, once);
    });

    test('keeps Windows line endings', () {
      final crlf = _template.replaceAll('\n', '\r\n');
      final text = addRunnerResource(crlf, 'PrivacyInfo.xcprivacy').text;
      expect(text.replaceAll('\r\n', ''), isNot(contains('\n')));
      expect('PrivacyInfo.xcprivacy'.allMatches(text), hasLength(6));
    });

    test('a reference already in the Runner group is reused', () {
      const id = 'ABCDEF0123456789ABCDEF01';
      final withReference = _template
          .replaceFirst(
            '/* End PBXFileReference section */',
            '\t\t$id /* PrivacyInfo.xcprivacy */ = {isa = PBXFileReference; '
                'lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; '
                'sourceTree = "<group>"; };\n'
                '/* End PBXFileReference section */',
          )
          .replaceFirst(
            '97C147021CF9000F007C117D /* Info.plist */,',
            '97C147021CF9000F007C117D /* Info.plist */,\n'
                '\t\t\t\t$id /* PrivacyInfo.xcprivacy */,',
          );
      final text = addRunnerResource(
        withReference,
        'PrivacyInfo.xcprivacy',
      ).text;
      expect(
        RegExp(r'isa = PBXFileReference;[^\n]*PrivacyInfo').allMatches(text),
        hasLength(1),
      );
      expect(text, contains('fileRef = $id /* PrivacyInfo.xcprivacy */;'));
    });

    test('Xcode 16 folder sync needs no change', () {
      const synced =
          '// !\$*UTF8*\$!\n{\n\tobjects = {\n'
          '\t\tAA /* Runner */ = {isa = PBXFileSystemSynchronizedRootGroup; '
          'path = Runner; sourceTree = "<group>"; };\n'
          '\t\tBB /* Runner */ = {\n\t\t\tisa = PBXNativeTarget;\n'
          '\t\t\tbuildPhases = (\n\t\t\t);\n'
          '\t\t\tfileSystemSynchronizedGroups = (\n'
          '\t\t\t\tAA /* Runner */,\n\t\t\t);\n'
          '\t\t\tname = Runner;\n'
          '\t\t\tproductType = "com.apple.product-type.application";\n'
          '\t\t};\n\t};\n\trootObject = CC;\n}\n';
      final result = addRunnerResource(synced, 'PrivacyInfo.xcprivacy');
      expect(result.state, PbxResourceState.synchronized);
      expect(result.text, synced);
    });

    test('a project without an app target is refused', () {
      expect(
        () => addRunnerResource(
          '{ objects = { }; rootObject = A; }',
          'PrivacyInfo.xcprivacy',
        ),
        throwsA(isA<PbxEditException>()),
      );
    });
  });

  group('xcross privacy init', () {
    late Directory project;
    late StringBuffer out;

    setUp(() {
      project = Directory.systemTemp.createTempSync('privacy-');
      _write(project, 'ios/Runner/Info.plist', '<plist><dict/></plist>');
      _write(project, 'ios/Runner.xcodeproj/project.pbxproj', _template);
      out = StringBuffer();
    });
    tearDown(() => project.deleteSync(recursive: true));

    Future<void> run(List<String> args) =>
        (CommandRunner<void>('xcross', 'test')..addCommand(
              PrivacyCommand(
                PermissionsContext(
                  fileSystem: detectPlatformHost().fileSystem,
                  paths: p.context,
                  currentDirectory: () => Directory.current.path,
                  write: out.write,
                  now: () => DateTime(2026, 11, 15, 12),
                ),
              ),
            ))
            .run(['privacy', 'init', ...args, '--project', project.path]);

    String read(String relative) => File(
      p.joinAll([project.path, ...relative.split('/')]),
    ).readAsStringSync();

    test(
      'writes the manifest, adds it to the target, keeps a backup',
      () async {
        await run(['--json']);
        final event = jsonDecode(out.toString()) as Map<String, Object?>;
        expect(event, {
          'v': 1,
          'type': 'privacy_init',
          'project': project.path,
          'manifest': 'ios/Runner/PrivacyInfo.xcprivacy',
          'created': true,
          'xcode': 'added',
          'backup':
              '.xcross/privacy-backups/20261115-120000/ios/Runner.xcodeproj/'
              'project.pbxproj',
        });
        expect(
          read('ios/Runner/PrivacyInfo.xcprivacy'),
          PrivacyInitCommand.starter,
        );
        expect(
          read('ios/Runner.xcodeproj/project.pbxproj'),
          contains('PrivacyInfo.xcprivacy in Resources'),
        );
        expect(read(event['backup']! as String), _template);
      },
    );

    test(
      'keeps a manifest the developer wrote and runs again safely',
      () async {
        _write(project, 'ios/Runner/PrivacyInfo.xcprivacy', 'mine');
        await run([]);
        expect(out.toString(), contains('already there'));
        expect(read('ios/Runner/PrivacyInfo.xcprivacy'), 'mine');
        final edited = read('ios/Runner.xcodeproj/project.pbxproj');

        out.clear();
        await run(['--json']);
        final event = jsonDecode(out.toString()) as Map<String, Object?>;
        expect(event['created'], isFalse);
        expect(event['xcode'], 'listed');
        expect(event['backup'], isNull);
        expect(read('ios/Runner.xcodeproj/project.pbxproj'), edited);
      },
    );

    test(
      'a project it cannot change gets a coded error and no manifest',
      () async {
        _write(
          project,
          'ios/Runner.xcodeproj/project.pbxproj',
          '{ objects = { }; rootObject = A; }',
        );
        await expectLater(
          run([]),
          throwsA(
            isA<CliError>().having(
              (e) => '$e',
              'message',
              contains('[privacy.xcode_project_unsupported]'),
            ),
          ),
        );
        expect(
          File(
            p.join(project.path, 'ios', 'Runner', 'PrivacyInfo.xcprivacy'),
          ).existsSync(),
          isFalse,
        );
      },
    );

    test('a folder without an iOS app is refused', () async {
      File(p.join(project.path, 'ios', 'Runner', 'Info.plist')).deleteSync();
      await expectLater(
        run([]),
        throwsA(
          isA<CliError>().having(
            (e) => '$e',
            'message',
            contains('[privacy.no_ios]'),
          ),
        ),
      );
    });
  });
}

void _write(Directory root, String relative, String text) =>
    File(p.joinAll([root.path, ...relative.split('/')]))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);

/// The text of object [id] in [text], from its line to its `};`.
String _object(String text, String id) {
  // The definition (`\t\t<id> /* name */ = {`), not a list entry.
  final start = text.indexOf(RegExp('\n\t\t$id /\\*[^*]*\\*/ = \\{')) + 1;
  return text.substring(start, text.indexOf('\n\t\t};', start) + 5);
}
