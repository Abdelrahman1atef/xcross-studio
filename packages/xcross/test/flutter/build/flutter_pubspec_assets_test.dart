import 'dart:convert';
import 'dart:io';

import 'package:cli_kit/host/linux/linux_host.dart';
import 'package:cli_kit/host/windows/windows_host.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/diagnostics/xcross_diagnostics.dart';
import 'package:xcross/src/shared/flutter/errors.dart';
import 'package:xcross/src/shared/flutter/flutter_assets_compiler.dart';
import 'package:xcross/src/shared/flutter/project/pubspec_info_reader.dart';

void main() {
  late Directory tmp;
  late String project;
  late String assets;
  late PlatformHostInterface host;
  late List<(String, String, String)> warnings;

  void write(String path, [String content = 'x']) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// A package at `<tmp>/<name>` with [pubspec] as the rest of its pubspec.
  void package(String name, String pubspec) =>
      write(p.join(tmp.path, name, 'pubspec.yaml'), 'name: $name\n$pubspec');

  /// The project's pubspec, lock file and package config. [lock] maps a package
  /// to how pub reached it (`direct main`, `transitive`, `direct dev`).
  void project_({
    required String pubspec,
    Map<String, String> lock = const {},
  }) {
    write(p.join(project, 'pubspec.yaml'), 'name: demo\n$pubspec');
    if (lock.isNotEmpty) {
      write(
        p.join(project, 'pubspec.lock'),
        'packages:\n${[for (final MapEntry(:key, :value) in lock.entries) '  $key:\n    dependency: "$value"\n'].join()}',
      );
    }
    write(
      p.join(project, '.dart_tool', 'package_config.json'),
      jsonEncode({
        'configVersion': 2,
        'packages': [
          for (final name in lock.keys)
            {
              'name': name,
              'rootUri': Directory(p.join(tmp.path, name)).uri.toString(),
              'packageUri': 'lib/',
            },
        ],
      }),
    );
  }

  Future<Map<String, List<String>>> copy() {
    final paths = host.paths.context;
    return FlutterAssetsCompiler(
      fileSystem: host.fileSystem,
      paths: paths,
      projectRoot: project,
      flutterRoot: p.join(tmp.path, 'flutter'),
      warn: (code, {required subject, required message}) =>
          warnings.add((code.code, subject, message)),
    ).copyPubspecAssets(
      assets,
      PubspecInfoReader(host.fileSystem, paths).loadSync(project),
    );
  }

  /// Every file in `flutter_assets`, as forward-slash paths.
  List<String> onDisk() {
    final root = Directory(assets);
    if (!root.existsSync()) return const [];
    return [
      for (final file in root.listSync(recursive: true).whereType<File>())
        p.relative(file.path, from: assets).replaceAll(r'\', '/'),
    ]..sort();
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('xcross_pubspec_assets_');
    project = p.join(tmp.path, 'project');
    assets = p.join(tmp.path, 'flutter_assets');
    warnings = [];
    host = Platform.isWindows
        ? WindowsHost(currentDirectory: tmp.path, temporaryDirectory: tmp.path)
        : LinuxHost(currentDirectory: tmp.path, temporaryDirectory: tmp.path);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('file names', () {
    test('match what the Flutter bundle asks the engine for', () {
      // The right-hand side is PlatformAssetBundle.load's own expression.
      for (final (key, expected) in const [
        ('assets/lottie/Map Loading.json', 'Map%20Loading.json'),
        ('assets/#1.png', '%231.png'),
        ('assets/ü.json', '%C3%BC.json'),
        ('assets/100%.json', '100%25.json'),
        ('assets/plain_name-1.2.png', 'plain_name-1.2.png'),
      ]) {
        expect(
          FlutterAssetsCompiler.fileNameOf(key),
          '${p.url.dirname(key)}/$expected',
        );
        expect(
          FlutterAssetsCompiler.fileNameOf(key),
          Uri(path: Uri.encodeFull(key)).path,
        );
      }
    });

    test(
      'are encoded on disk while the manifest keeps the plain key',
      () async {
        for (final name in const ['Map Loading.json', 'plain.json']) {
          write(p.join(project, 'assets', 'lottie', name));
        }
        write(p.join(project, 'assets', 'one file.png'));
        project_(
          pubspec: '''
flutter:
  assets:
    - assets/lottie/
    - assets/one file.png
''',
        );

        final manifest = await copy();

        expect(onDisk(), [
          'assets/lottie/Map%20Loading.json',
          'assets/lottie/plain.json',
          'assets/one%20file.png',
        ]);
        expect(manifest, {
          'assets/lottie/Map Loading.json': ['assets/lottie/Map Loading.json'],
          'assets/lottie/plain.json': ['assets/lottie/plain.json'],
          'assets/one file.png': ['assets/one file.png'],
        });
      },
    );

    test('a folder entry does not reach into its subfolders', () async {
      write(p.join(project, 'assets', 'top.png'));
      write(p.join(project, 'assets', 'nested', 'deep.png'));
      project_(pubspec: 'flutter:\n  assets:\n    - assets/\n');

      await copy();

      expect(onDisk(), ['assets/top.png']);
    });
  });

  group('assets of dependencies', () {
    test('a direct and a transitive package land under packages/', () async {
      package('toast', '''
flutter:
  assets:
    - assets/
    - extra/one.js
''');
      write(p.join(tmp.path, 'toast', 'assets', 'toast it.css'));
      write(p.join(tmp.path, 'toast', 'extra', 'one.js'));
      package('recorder_web', 'flutter:\n  assets:\n    - assets/js/\n');
      write(p.join(tmp.path, 'recorder_web', 'assets', 'js', 'worklet.js'));
      project_(
        pubspec: 'dependencies:\n  toast: any\n',
        lock: const {'toast': 'direct main', 'recorder_web': 'transitive'},
      );

      final manifest = await copy();

      expect(onDisk(), [
        'packages/recorder_web/assets/js/worklet.js',
        'packages/toast/assets/toast%20it.css',
        'packages/toast/extra/one.js',
      ]);
      expect(manifest.keys, contains('packages/toast/assets/toast it.css'));
    });

    test('a dev dependency adds nothing', () async {
      package('lints_kit', 'flutter:\n  assets:\n    - assets/\n');
      write(p.join(tmp.path, 'lints_kit', 'assets', 'dev.png'));
      project_(pubspec: '', lock: const {'lints_kit': 'direct dev'});

      expect(await copy(), isEmpty);
      expect(onDisk(), isEmpty);
    });

    test('a missing asset in a package warns and the build goes on', () async {
      package('broken', '''
flutter:
  assets:
    - nothing/
    - nothing.png
''');
      project_(pubspec: '', lock: const {'broken': 'transitive'});

      expect(await copy(), isEmpty);
      expect(
        [for (final (code, subject, _) in warnings) (code, subject)],
        [
          (XcrossCodes.buildAssetInvalid.code, 'broken/nothing/'),
          (XcrossCodes.buildAssetInvalid.code, 'broken/nothing.png'),
        ],
      );
    });

    test('the app can name a file in a package, as Flutter allows', () async {
      package('art', '');
      write(p.join(tmp.path, 'art', 'lib', 'images', 'logo.png'));
      project_(
        pubspec: 'flutter:\n  assets:\n    - packages/art/images/logo.png\n',
        lock: const {'art': 'direct main'},
      );

      await copy();

      expect(onDisk(), ['packages/art/images/logo.png']);
    });
  });

  group('a missing asset of the app', () {
    test('stops the build for a file', () {
      project_(pubspec: 'flutter:\n  assets:\n    - gone.png\n');
      expect(copy, throwsA(isA<FlutterBuildError>()));
    });

    test('stops the build for a folder', () {
      project_(pubspec: 'flutter:\n  assets:\n    - gone/\n');
      expect(copy, throwsA(isA<FlutterBuildError>()));
    });
  });
}
