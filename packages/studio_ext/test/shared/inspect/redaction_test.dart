import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:studio_ext/shared/inspect/inspect_command.dart';
import 'package:test/test.dart';

import '../../support/fixture_builder.dart';
import '../../support/test_file_system.dart';

/// SC-004 / FR-004: no output mode may contain device UDIDs, API keys,
/// certificate bytes, team or App ID names, or absolute paths.
void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('redaction_'));
  tearDown(() => temp.deleteSync(recursive: true));

  final certificate = plantedCertificate;
  final forbidden = <String>[
    ...plantedUdids,
    plantedApiKey,
    plantedTeamName,
    plantedAppIdName,
    utf8.decode(certificate),
    base64.encode(certificate),
    [for (final b in certificate) b.toRadixString(16).padLeft(2, '0')].join(),
    utf8.decode(plantedCmsPayload),
    base64.encode(plantedCmsPayload),
  ];

  test('SC-004 no UDID, key or certificate bytes in any output', () async {
    for (final MapEntry(key: name, value: write) in goldenFixtures.entries) {
      final path = write(temp);
      for (final mode in [
        <String>[],
        ['--json'],
        ['--json', '--normalize'],
      ]) {
        final output = <String>[];
        await (CommandRunner<void>('xcross', 'test')..addCommand(
              InspectCommand(
                fileSystem: const IoFileSystem(),
                write: output.add,
              ),
            ))
            .run(['inspect', path, ...mode]);
        final text = output.join();
        for (final secret in forbidden) {
          expect(
            text,
            isNot(contains(secret)),
            reason: '$name ${mode.join(' ')} leaked "$secret"',
          );
        }
        expect(
          text,
          isNot(contains(temp.path)),
          reason: '$name ${mode.join(' ')} contains an absolute path',
        );
        expect(
          text,
          isNot(contains(temp.path.replaceAll(r'\', '/'))),
          reason: '$name ${mode.join(' ')} contains an absolute path',
        );
      }
    }
  });
}
