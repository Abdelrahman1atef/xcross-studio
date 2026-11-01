import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:crypto/crypto.dart';
import 'package:studio_ext/shared/inspect/inspect_command.dart';
import 'package:test/test.dart';

import '../../support/fixture_builder.dart';
import '../../support/test_file_system.dart';

void main() {
  late Directory temp;
  late List<String> written;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('inspect_command_');
    written = [];
  });
  tearDown(() => temp.deleteSync(recursive: true));

  CommandRunner<void> runner() => CommandRunner<void>('xcross', 'test')
    ..addCommand(
      InspectCommand(fileSystem: const IoFileSystem(), write: written.add),
    );

  Matcher cliErrorStartingWith(String prefix) => throwsA(
    isA<CliError>().having((e) => e.message, 'message', startsWith(prefix)),
  );

  test('--json writes exactly one JSON document', () async {
    final path = unsignedV209().writeIpa(temp, 'app.ipa');
    await runner().run(['inspect', path, '--json']);
    expect(written, hasLength(1));
    final document = jsonDecode(written.single) as Map<String, Object?>;
    expect(document['schemaVersion'], 1);
    expect(document['normalized'], isFalse);
    expect(written.single.endsWith('}\n'), isTrue);
  });

  test('default output is the human summary', () async {
    final path = unsignedV209().writeIpa(temp, 'app.ipa');
    await runner().run(['inspect', path]);
    expect(written.single, startsWith('app.ipa  com.example.fixture'));
  });

  test('fatal error writes the error document and throws CliError', () async {
    await expectLater(
      runner().run(['inspect', '${temp.path}/missing.ipa', '--json']),
      cliErrorStartingWith('[inspect.input_not_found] missing.ipa'),
    );
    final document = jsonDecode(written.single) as Map<String, Object?>;
    expect(document.keys, ['schemaVersion', 'error']);
    expect((document['error']! as Map)['code'], 'inspect.input_not_found');
  });

  test('without --json a fatal error writes nothing to stdout', () async {
    await expectLater(
      runner().run(['inspect', '${temp.path}/missing.ipa']),
      throwsA(isA<CliError>()),
    );
    expect(written, isEmpty);
  });

  test('archive-level edge cases surface as fatal codes', () async {
    final cases = {
      'inspect.no_app': encodeZip({'Payload/x.txt': Uint8List(1)}),
      'inspect.multiple_apps': encodeZip({
        'Payload/A.app/Info.plist': Uint8List(1),
        'Payload/B.app/Info.plist': Uint8List(1),
      }),
      'inspect.corrupt_archive': Uint8List.fromList(utf8.encode('not a zip')),
    };
    for (final MapEntry(key: code, value: bytes) in cases.entries) {
      final file = File('${temp.path}/$code.ipa')..writeAsBytesSync(bytes);
      written.clear();
      await expectLater(
        runner().run(['inspect', file.path, '--json']),
        cliErrorStartingWith('[$code]'),
      );
      expect(written.single, contains('"code": "$code"'));
    }
  });

  test('a truncated Mach-O is an issue, not a failure', () async {
    final path = unsignedV209(
      runner: machO().sublist(0, 20),
    ).writeIpa(temp, 'truncated.ipa');
    await runner().run(['inspect', path, '--json']);
    expect(written.single, contains('"code": "inspect.macho_invalid"'));
  });

  test('usage errors: missing path, two paths', () async {
    await expectLater(
      runner().run(['inspect']),
      throwsA(isA<UsageException>()),
    );
    await expectLater(
      runner().run(['inspect', 'a.ipa', 'b.ipa']),
      throwsA(isA<UsageException>()),
    );
  });

  test('--normalize requires --json; with it, normalized is true', () async {
    final path = profileAppex().writeIpa(temp, 'app.ipa');
    await expectLater(
      runner().run(['inspect', path, '--normalize']),
      throwsA(isA<UsageException>()),
    );
    await runner().run(['inspect', path, '--json', '--normalize']);
    final document = jsonDecode(written.single) as Map<String, Object?>;
    expect(document['normalized'], isTrue);
    expect((document['input']! as Map)['sha256'], isNull);
  });

  test('FR-006 input is not modified', () async {
    final path = profileAppex().writeIpa(temp, 'app.ipa');
    final file = File(path);
    final before = sha256.convert(file.readAsBytesSync());
    final modified = file.lastModifiedSync();
    await runner().run(['inspect', path, '--json']);
    await runner().run(['inspect', path]);
    expect(sha256.convert(file.readAsBytesSync()), before);
    expect(file.lastModifiedSync(), modified);
    expect(temp.listSync().map((e) => e.path), [path]);
  });

  test('description and invocation are set', () {
    final command = runner().commands['inspect']!;
    expect(command.description, contains('.ipa'));
    expect(command.invocation, contains('xcross inspect <ipa|app>'));
  });
}
