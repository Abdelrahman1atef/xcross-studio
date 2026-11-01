// studio: 011 — `xcross sign <ipa|app>`: re-sign and write an IPA.
import 'dart:io';
import 'dart:typed_data';

import 'package:apple_developer_kit/shared/errors/errors.dart';
import 'package:archive/archive.dart';
import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:studio_ext/shared/inspect/signed_bundle_check.dart';
import 'package:test/test.dart';
import 'package:xcross/src/composition/cli/sign_command.dart';
import 'package:xcross/src/shared/errors/errors.dart';

const _passing = SignedBundleCheck(
  bundleId: 'com.example.app',
  teamId: 'TEAMID1234',
  profileKind: 'development',
  profileExpires: '2026-11-08T10:00:00Z',
  deviceCount: 2,
  provisionsAllDevices: false,
  entitlementKeys: ['application-identifier', 'get-task-allow'],
  problems: [],
);

void main() {
  late Directory temp;
  late List<Map<String, Object?>> signs;
  late StringBuffer out;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('xcross-sign-test-');
    signs = [];
    out = StringBuffer();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  CommandRunner<void> runner({
    List<String> connected = const [],
    Exception? signError,
    VerifySignedIpa? verify = _verifyPassing,
  }) => CommandRunner<void>('xcross', 'test')
    ..addCommand(
      SignCommand(
        fileSystem: const NativeSignFileSystem(),
        paths: p.context,
        temporaryRoot: temp.path,
        write: out.write,
        connectedDevices: () async => connected,
        verify: verify,
        signApp:
            ({
              required appPath,
              required bundleId,
              required deviceUdids,
            }) async {
              signs.add({
                'app': p.basename(appPath),
                'bundleId': bundleId,
                'udids': deviceUdids,
                'plist': File(p.join(appPath, 'Info.plist')).readAsStringSync(),
              });
              if (signError != null) throw signError;
              // What the signer leaves behind.
              File(p.join(appPath, '_CodeSignature', 'CodeResources'))
                ..createSync(recursive: true)
                ..writeAsStringSync('<plist/>');
              File(
                p.join(appPath, 'embedded.mobileprovision'),
              ).writeAsBytesSync([1, 2, 3]);
              return 'XCR-ABC.$bundleId';
            },
      ),
    );

  Uint8List binaryPlist(Map<String, Object> plist) => Uint8List.sublistView(
    PropertyListSerialization.dataWithPropertyList(plist),
  );

  String writeIpa(Map<String, List<int>> entries, {String name = 'in.ipa'}) {
    final archive = Archive();
    for (final MapEntry(:key, :value) in entries.entries) {
      archive.add(ArchiveFile.bytes(key, value));
    }
    final file = File(p.join(temp.path, name))
      ..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
    return file.path;
  }

  String sampleIpa({List<int>? info}) => writeIpa({
    'Payload/Runner.app/Info.plist':
        info ?? binaryPlist({'CFBundleIdentifier': 'com.example.app'}),
    'Payload/Runner.app/Runner': [0xcf, 0xfa, 0xed, 0xfe, 0, 0],
    'Payload/Runner.app/PlugIns/Share.appex/Info.plist': binaryPlist({
      'CFBundleIdentifier': 'com.example.app.Share',
    }),
  });

  Matcher coded(String code) => throwsA(
    isA<XcrossError>().having(
      (e) => e.message,
      'message',
      startsWith('[$code]'),
    ),
  );

  test(
    'AC-011-1 an IPA is signed into <input>-signed.ipa; the input is untouched',
    () async {
      final ipa = sampleIpa();
      final before = File(ipa).readAsBytesSync();
      await runner().run(['sign', ipa, '--no-usb']);

      expect(signs.single['app'], 'Runner.app');
      expect(signs.single['bundleId'], 'com.example.app');
      expect(
        signs.single['plist'],
        contains('<?xml'),
        reason: 'binary Info.plist rewritten as XML for the signer',
      );
      expect(File(ipa).readAsBytesSync(), before);

      final signed = p.join(temp.path, 'in-signed.ipa');
      final names = [
        for (final f
            in ZipDecoder().decodeBytes(File(signed).readAsBytesSync()).files)
          f.name,
      ];
      expect(names, contains('Payload/Runner.app/Runner'));
      expect(names, contains('Payload/Runner.app/embedded.mobileprovision'));
      expect(
        names,
        contains('Payload/Runner.app/_CodeSignature/CodeResources'),
      );
      expect(
        temp.listSync().where(
          (e) => p.basename(e.path).startsWith('xcross-sign-'),
        ),
        isEmpty,
        reason: 'work folder removed',
      );
      final text = out.toString();
      expect(text, contains('✔ Signed: $signed'));
      expect(text, contains('(signed as XCR-ABC.com.example.app)'));
      expect(text, contains('development · expires 2026-11-08 · 2 devices'));
      expect(text, contains('xcross install --no-resign'));
      expect(text, contains('No device given'));
    },
  );

  test('AC-011-2 --udid and connected devices are registered once', () async {
    await runner(connected: ['00008020-AAAA', '00008030-BBBB']).run([
      'sign',
      sampleIpa(),
      '--udid',
      '00008020-aaaa',
      '--udid',
      '00008110-CCCC',
      '-o',
      p.join(temp.path, 'out', 'App.ipa'),
    ]);
    expect(signs.single['udids'], [
      '00008020-aaaa',
      '00008110-CCCC',
      '00008030-BBBB',
    ]);
    expect(out.toString(), contains('Including 3 devices'));
    expect(File(p.join(temp.path, 'out', 'App.ipa')).existsSync(), isTrue);

    signs.clear();
    await runner(
      connected: ['00008020-AAAA'],
    ).run(['sign', sampleIpa(), '--no-usb', '-o', p.join(temp.path, 'b.ipa')]);
    expect(signs.single['udids'], isEmpty);
  });

  test('AC-011-2 a team without devices is sign.no_device', () async {
    await expectLater(
      runner(
        signError: const AppleError(
          'No iOS devices are registered on this team. Plug in a device and '
          'retry.',
        ),
      ).run(['sign', sampleIpa(), '--no-usb']),
      coded('sign.no_device'),
    );
    expect(File(p.join(temp.path, 'in-signed.ipa')).existsSync(), isFalse);
  });

  test('AC-011-5 --bundle-id renames the app and its extensions', () async {
    await runner().run([
      'sign',
      sampleIpa(),
      '--no-usb',
      '--bundle-id',
      'com.mine.app',
    ]);
    expect(signs.single['bundleId'], 'com.mine.app');
    final archive = ZipDecoder().decodeBytes(
      File(p.join(temp.path, 'in-signed.ipa')).readAsBytesSync(),
    );
    String plistOf(String name) => String.fromCharCodes(
      archive.files.singleWhere((f) => f.name == name).content,
    );
    expect(
      plistOf('Payload/Runner.app/PlugIns/Share.appex/Info.plist'),
      contains('com.mine.app.Share'),
    );
  });

  test(
    'AC-011-4 the inspector rejects an unsigned result (sign.verify_failed)',
    () async {
      // The real check: the fake signer leaves Runner unsigned.
      await expectLater(
        runner(verify: null).run(['sign', sampleIpa(), '--no-usb']),
        coded('sign.verify_failed'),
      );
      expect(File(p.join(temp.path, 'in-signed.ipa')).existsSync(), isFalse);
    },
  );

  test('AC-011-7 output and input errors', () async {
    final ipa = sampleIpa();
    await expectLater(
      runner().run(['sign', ipa, '-o', ipa]),
      coded('sign.output_invalid'),
    );
    await expectLater(
      runner().run(['sign', ipa, '-o', p.join(temp.path, 'x.zip')]),
      coded('sign.output_invalid'),
    );
    await expectLater(
      runner().run(['sign', p.join(temp.path, 'missing.ipa')]),
      coded('install.unsupported_input'),
    );
    await expectLater(runner().run(['sign']), throwsA(isA<UsageException>()));
    expect(signs, isEmpty);
  });

  test('AC-011-8 an App Store encrypted app gets a coded warning', () async {
    await runner().run([
      'sign',
      writeIpa({
        'Payload/Runner.app/Info.plist': binaryPlist({
          'CFBundleIdentifier': 'com.example.app',
        }),
        'Payload/Runner.app/Runner': [0xcf, 0xfa, 0xed, 0xfe],
        'Payload/Runner.app/SC_Info/Runner.sinf': [1],
      }),
      '--no-usb',
    ]);
    expect(out.toString(), contains('[sign.encrypted_app]'));
  });
}

SignedBundleCheck _verifyPassing(String _) => _passing;

/// dart:io-backed host file system for this test.
@internal
final class NativeSignFileSystem implements HostFileSystemInterface {
  const NativeSignFileSystem();

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
