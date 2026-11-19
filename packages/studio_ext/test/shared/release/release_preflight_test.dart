// studio: 018 — `xcross release preflight` and the checks before a build.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/release/release_check_command.dart';
import 'package:studio_ext/shared/release/release_preflight.dart';
import 'package:test/test.dart';

import '../../support/fixture_builder.dart';
import '../../support/test_file_system.dart';

/// Minimal PNG: signature, IHDR, IEND ([colorType] 2 = RGB, 6 = RGBA).
Uint8List _png({int size = 1024, int colorType = 2}) {
  final ihdr = ByteData(13)
    ..setUint32(0, size)
    ..setUint32(4, size)
    ..setUint8(8, 8)
    ..setUint8(9, colorType);
  return Uint8List.fromList([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
    0, 0, 0, 13, ...ascii.encode('IHDR'),
    ...ihdr.buffer.asUint8List(), 0, 0, 0, 0, //
    0, 0, 0, 0, ...ascii.encode('IEND'), 0, 0, 0, 0,
  ]);
}

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('preflight'));
  tearDown(() => temp.deleteSync(recursive: true));

  void write(String path, List<int> bytes) {
    final file = File(p.join(temp.path, path));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
  }

  /// A project that passes everything unless the arguments say otherwise.
  void project({
    Uint8List? icon,
    Map<String, Object> info = const {},
    bool privacyManifest = true,
    String? encryption = 'false',
    List<String> plugins = const [],
  }) {
    final dependencies = plugins.map((name) => '  $name: any\n').join();
    final xcross = encryption == null
        ? ''
        : 'xcross:\n  uses_non_exempt_encryption: $encryption\n';
    write(
      'pubspec.yaml',
      utf8.encode(
        'name: app\n'
        'dependencies:\n  flutter:\n    sdk: flutter\n'
        '$dependencies$xcross',
      ),
    );
    write(
      'ios/Runner/Info.plist',
      xmlPlist({'CFBundleIdentifier': 'com.example.app', ...info}),
    );
    if (privacyManifest) {
      write('ios/Runner/PrivacyInfo.xcprivacy', utf8.encode('<plist/>'));
    }
    write(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json',
      utf8.encode(
        jsonEncode({
          'images': [
            {
              'filename': 'Icon-1024.png',
              'idiom': 'universal',
              'platform': 'ios',
              'size': '1024x1024',
            },
          ],
        }),
      ),
    );
    write(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-1024.png',
      icon ?? _png(),
    );
  }

  PreflightResult run() => preflightProject(
    fileSystem: const IoFileSystem(),
    paths: p.context,
    projectRoot: temp.path,
  );

  List<String> codes(PreflightResult result, {bool errors = true}) => [
    for (final f in result.findings)
      if (f.isError == errors) f.code,
  ];

  test('AC-018-20 a clean project has no findings', () {
    project();
    final result = run();
    expect(result.findings, isEmpty);
    expect(result.errors, 0);
  });

  test('AC-018-20 an App Store icon with an alpha channel is an error before '
      'the build (ITMS-90717), also when every pixel is opaque', () {
    project(icon: _png(colorType: 6));
    final result = run();
    expect(codes(result), ['release.marketing_icon']);
    expect(
      result.findings.single.message,
      allOf(contains('Icon-1024.png'), contains('alpha channel')),
    );
    expect(result.findings.single.hint, contains('ITMS-90717'));
  });

  test('AC-018-20 a wrong icon size and a missing icon set are errors', () {
    project(icon: _png(size: 512));
    expect(
      run().findings.single.message,
      allOf(contains('512'), contains('1024')),
    );
    Directory(
      p.join(temp.path, 'ios/Runner/Assets.xcassets'),
    ).deleteSync(recursive: true);
    expect(codes(run()), ['release.marketing_icon']);
    expect(run().findings.single.message, contains('no app icon set'));
  });

  test('AC-018-21 a plugin that needs a purpose string without one is an '
      'error; with it, none', () {
    project(plugins: ['image_picker']);
    expect(codes(run()), contains('release.permission_missing'));
    project(
      plugins: ['image_picker'],
      info: {
        'NSPhotoLibraryUsageDescription': 'To pick the photo you attach.',
        'NSCameraUsageDescription': 'To take the photo you attach.',
      },
    );
    expect(codes(run()), isEmpty);
  });

  test('AC-018-22 warnings: privacy manifest, export compliance, a '
      'background mode no plugin explains', () {
    project(
      privacyManifest: false,
      encryption: null,
      info: {
        'UIBackgroundModes': ['fetch'],
      },
    );
    final result = run();
    expect(result.errors, 0);
    expect(
      codes(result, errors: false),
      unorderedEquals([
        'release.privacy_manifest_missing',
        'release.encryption_unset',
        'release.background_mode',
      ]),
    );
    expect(result.warnings, 3);
  });

  test('AC-018-22 the export compliance answer is read from pubspec.yaml or '
      'Info.plist', () {
    project(encryption: null, info: {'ITSAppUsesNonExemptEncryption': false});
    expect(codes(run(), errors: false), isEmpty);
    project(encryption: 'true');
    expect(codes(run(), errors: false), isEmpty);
  });

  group('xcross release preflight', () {
    Future<(String, Object?)> runCommand(List<String> args) async {
      final out = StringBuffer();
      final runner = CommandRunner<void>('xcross', 'test')
        ..addCommand(
          ReleaseCommand(
            fileSystem: const IoFileSystem(),
            paths: p.context,
            currentDirectory: () => temp.path,
            write: out.write,
          ),
        );
      Object? error;
      try {
        await runner.run(['release', 'preflight', ...args]);
      } on CliError catch (e) {
        error = e;
      }
      return (out.toString(), error);
    }

    test('AC-018-23 prints findings and fails on errors', () async {
      project(icon: _png(colorType: 6));
      final (text, error) = await runCommand([]);
      expect(text, contains('error [release.marketing_icon]'));
      expect(text, contains('1 error'));
      expect(error.toString(), contains('release.preflight_failed'));
    });

    test('AC-018-23 a clean project passes; --json is one object', () async {
      project();
      final (text, error) = await runCommand([]);
      expect(text, contains('No problems found.'));
      expect(error, isNull);
      final (json, _) = await runCommand(['--json']);
      final decoded = jsonDecode(json) as Map<String, Object?>;
      expect(decoded['errors'], 0);
      expect((decoded['configuration']! as Map)['stage'], 'preflight');
    });

    test(
      'AC-018-23 a folder that is no Flutter project is a coded error',
      () async {
        final (_, error) = await runCommand([]);
        expect(error.toString(), contains('release.no_project'));
      },
    );
  });
}
