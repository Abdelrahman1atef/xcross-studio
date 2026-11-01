// studio: 005 — `xcross install <ipa|app>` input handling.
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:test/test.dart';
import 'package:xcross/src/composition/cli/install_command.dart';
import 'package:xcross/src/shared/errors/errors.dart';

void main() {
  late Directory temp;
  late List<Map<String, Object?>> installs;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('xcross-install-test-');
    installs = [];
  });
  tearDown(() => temp.deleteSync(recursive: true));

  CommandRunner<void> runner() =>
      CommandRunner<void>('xcross', 'test')..addCommand(
        InstallCommand(
          fileSystem: const NativeInstallFileSystem(),
          paths: p.context,
          temporaryRoot: temp.path,
          installOnDevice:
              ({
                required appPath,
                required bundleId,
                required udid,
                required ddiDirectory,
                required launch,
              }) async {
                installs.add({
                  'app': p.basename(appPath),
                  'bundleId': bundleId,
                  'udid': udid,
                  'ddi': ddiDirectory,
                  'launch': launch,
                  'executable': File(p.join(appPath, 'Runner')).existsSync(),
                });
              },
        ),
      );

  Uint8List binaryInfo(String id) => Uint8List.sublistView(
    PropertyListSerialization.dataWithPropertyList({'CFBundleIdentifier': id}),
  );

  String writeIpa(Map<String, List<int>> entries) {
    final archive = Archive();
    for (final MapEntry(:key, :value) in entries.entries) {
      archive.add(ArchiveFile.bytes(key, value));
    }
    final file = File(p.join(temp.path, 'in.ipa'))
      ..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
    return file.path;
  }

  Matcher coded(String code) => throwsA(
    isA<XcrossError>().having(
      (e) => e.message,
      'message',
      startsWith('[$code]'),
    ),
  );

  test(
    'AC-005-5 an IPA is extracted and handed to the device install',
    () async {
      final ipa = writeIpa({
        'Payload/Runner.app/Info.plist': binaryInfo('com.example.ipa'),
        'Payload/Runner.app/Runner': [0xcf, 0xfa, 0xed, 0xfe],
        'Payload/Runner.app/../../evil': [1],
      });
      await runner().run([
        'install',
        ipa,
        '--udid',
        'U1',
        '--ddi',
        '/ddi',
        '--no-launch',
      ]);
      expect(installs.single, {
        'app': 'Runner.app',
        'bundleId': 'com.example.ipa',
        'udid': 'U1',
        'ddi': '/ddi',
        'launch': false,
        'executable': true,
      });
      expect(File(p.join(temp.path, 'evil')).existsSync(), isFalse);
      expect(
        temp.listSync().where(
          (e) => p.basename(e.path).startsWith('xcross-install-'),
        ),
        isEmpty,
        reason: 'work folder removed',
      );
    },
  );

  test('AC-005-5 a .app is copied, never modified in place', () async {
    final app = Directory(p.join(temp.path, 'My.app'))..createSync();
    File(p.join(app.path, 'Info.plist')).writeAsStringSync(
      PropertyListSerialization.stringWithPropertyList({
        'CFBundleIdentifier': 'com.example.app',
      }),
    );
    await runner().run(['install', app.path]);
    expect(installs.single['bundleId'], 'com.example.app');
    expect(installs.single['launch'], isTrue);
    expect(app.listSync(), hasLength(1));
  });

  test('AC-005-6 unsupported input and IPAs without one app', () async {
    await expectLater(
      runner().run(['install', p.join(temp.path, 'missing.ipa')]),
      coded('install.unsupported_input'),
    );
    await expectLater(
      runner().run([
        'install',
        writeIpa({
          'Payload/readme.txt': [1],
        }),
      ]),
      coded('install.no_app'),
    );
    await expectLater(
      runner().run(['install']),
      throwsA(isA<UsageException>()),
    );
    expect(installs, isEmpty);
  });
}

/// dart:io-backed host file system for this test.
@internal
final class NativeInstallFileSystem implements HostFileSystemInterface {
  const NativeInstallFileSystem();

  @override
  File file(String path) => File(path);
  @override
  Directory directory(String path) => Directory(path);
  @override
  Link link(String path) => Link(path);
  @override
  void makeExecutable(String path) {}
  @override
  void setPermissions(String path, int mode) {}
  @override
  Future<void> createArchiveLink(String destination, String target) =>
      Link(destination).create(target);
}
