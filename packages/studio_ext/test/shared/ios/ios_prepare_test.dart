// Feature 032: `xcross ios prepare` makes a fresh Flutter iOS project ready to
// build without a Mac, and says what a build would leave out.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/ios/ios_prepare.dart';
import 'package:test/test.dart';

import '../../support/test_file_system.dart';

const _pbxproj = '''
PRODUCT_BUNDLE_IDENTIFIER = com.example.fresh;
PRODUCT_BUNDLE_IDENTIFIER = com.example.fresh.RunnerTests;
IPHONEOS_DEPLOYMENT_TARGET = 13.0;
''';

const _infoPlist = '''
<plist><dict>
<key>NSCameraUsageDescription</key><string>Scan</string>
</dict></plist>
''';

void main() {
  late Directory temp;
  late List<String> out;
  late List<String> pubGets;
  final entries = <Map<String, String>>[];

  setUp(() {
    temp = Directory.systemTemp.createTempSync('xcross_ios_prepare_');
    out = [];
    pubGets = [];
    entries.clear();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  /// A project as `flutter create` leaves it: an ios/ Runner project, and
  /// nothing CocoaPods writes (no Podfile.lock, Pods/, workspace).
  void freshProject({bool ios = true}) {
    if (!ios) return;
    File(p.join(temp.path, 'ios', 'Runner.xcodeproj', 'project.pbxproj'))
      ..createSync(recursive: true)
      ..writeAsStringSync(_pbxproj);
    File(p.join(temp.path, 'ios', 'Runner', 'Info.plist'))
      ..createSync(recursive: true)
      ..writeAsStringSync(_infoPlist);
  }

  void writeMetadata() =>
      File(
        p.join(temp.path, '.flutter-plugins-dependencies'),
      ).writeAsStringSync(
        jsonEncode({
          'plugins': {'ios': entries},
        }),
      );

  void addPlugin(String name, {String? podspec, bool swiftPackage = false}) {
    final root = p.join(temp.path, 'pub', name);
    File(p.join(root, 'pubspec.yaml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('name: $name\nversion: 1.0.0\n');
    if (podspec != null) {
      File(p.join(root, 'ios', '$name.podspec'))
        ..createSync(recursive: true)
        ..writeAsStringSync(podspec);
    }
    if (swiftPackage) {
      File(p.join(root, 'ios', name, 'Package.swift'))
        ..createSync(recursive: true)
        ..writeAsStringSync('// shipped');
    }
    entries.add({'name': name, 'path': root});
  }

  IosPrepare prepare({
    PubGet? pubGet,
    Map<String, String> environment = const {},
  }) => IosPrepare(
    fileSystem: const IoFileSystem(),
    paths: p.context,
    pubGet: pubGet,
    environment: environment,
  );

  Future<void> command(List<String> arguments, {bool pubOk = true}) =>
      (CommandRunner<void>('xcross', 'test')..addCommand(
            IosCommand(
              fileSystem: const IoFileSystem(),
              paths: p.context,
              currentDirectory: () => temp.path,
              write: out.add,
              environment: const {},
              pubGet: (project) async {
                pubGets.add(project);
                if (pubOk) writeMetadata();
                return pubOk;
              },
            ),
          ))
          .run(['ios', 'prepare', ...arguments]);

  const podspecKnown = "Pod::Spec.new do |s|\n  s.dependency 'Flutter'\nend\n";
  const podspecUnknown =
      "Pod::Spec.new do |s|\n  s.dependency 'Flutter'\n"
      "  s.dependency 'SomeVendorSDK', '~> 1.0'\nend\n";

  test(
    'AC-032-1 a fresh app with no Podfile, Pods or workspace is ready',
    () async {
      freshProject();
      writeMetadata();
      final report = await prepare().run(temp.path);
      expect(report.ready, isTrue);
      expect(report.steps.map((s) => (s.id, s.state)), [
        ('project', PrepareState.ok),
        ('dependencies', PrepareState.ok),
        ('plugins', PrepareState.ok),
        ('settings', PrepareState.ok),
      ]);
      // Read from the project file; the tests target is not the app.
      expect(report.bundleId, 'com.example.fresh');
      expect(report.deploymentTarget, '13.0');
      // The Info.plist purpose string is what switches the permission on.
      expect(report.permissionMacros, {'PERMISSION_CAMERA': '1'});
      // Nothing a Mac writes was created.
      for (final name in ['Podfile', 'Podfile.lock', 'Pods']) {
        expect(
          FileSystemEntity.typeSync(p.join(temp.path, 'ios', name)),
          FileSystemEntityType.notFound,
        );
      }
    },
  );

  test('AC-032-2 no ios folder fails and says how to create it', () async {
    freshProject(ios: false);
    writeMetadata();
    final report = await prepare().run(temp.path);
    expect(report.ready, isFalse);
    expect(report.steps.single.id, 'project');
    expect(report.steps.single.hint, 'Run: flutter create --platforms=ios .');
    await expectLater(
      command([]),
      throwsA(
        isA<CliError>().having(
          (e) => '$e',
          'message',
          contains('flutter create --platforms=ios'),
        ),
      ),
    );
  });

  test(
    'AC-032-3 flutter pub get runs first; a missing plugin list is a blocker',
    () async {
      freshProject();
      var ran = 0;
      final missing = await prepare(
        pubGet: (_) async {
          ran++;
          return true; // succeeded but wrote nothing
        },
      ).run(temp.path);
      expect(ran, 1);
      expect(missing.ready, isFalse);
      expect(
        missing.steps.last.detail,
        contains('did not produce .flutter-plugins-dependencies'),
      );

      // A failed pub get with a plugin list from before is a warning only.
      writeMetadata();
      final stale = await prepare(pubGet: (_) async => false).run(temp.path);
      expect(stale.ready, isTrue);
      expect(
        stale.steps.firstWhere((s) => s.id == 'dependencies').state,
        PrepareState.warning,
      );

      // Without pub get and without the list: no plugin would be built.
      File(p.join(temp.path, '.flutter-plugins-dependencies')).deleteSync();
      final none = await prepare().run(temp.path);
      expect(none.ready, isFalse);
    },
  );

  test(
    'AC-032-4 a podspec-only plugin is drafted before the long build',
    () async {
      freshProject();
      addPlugin('modern', swiftPackage: true);
      addPlugin('draftable', podspec: podspecKnown);
      addPlugin('dart_only');
      writeMetadata();
      final report = await prepare().run(temp.path);
      expect(
        {for (final plugin in report.plugins) plugin.name: plugin.state},
        {'modern': 'ready', 'draftable': 'drafted', 'dart_only': 'ready'},
      );
      expect(
        File(
          p.join(
            temp.path,
            'xcross_overrides',
            'draftable',
            '1.0.0',
            'Package.swift',
          ),
        ).existsSync(),
        isTrue,
      );
      // Run again: the draft is there now and is not written twice. It is
      // xcross's own draft nobody has looked at (feature 028), so it asks for
      // a look, which does not block.
      final again = await prepare().run(temp.path);
      final draft = again.plugins.firstWhere((x) => x.name == 'draftable');
      expect((draft.state, draft.kind), ('attention', 'draft'));
      expect(draft.detail, contains('look it over'));
      expect(again.ready, isTrue);
      expect(again.leftOut, isEmpty);
    },
  );

  test('AC-032-5 a plugin with an unknown pod is named as left out', () async {
    freshProject();
    addPlugin('vendored', podspec: podspecUnknown);
    writeMetadata();
    final report = await prepare().run(temp.path);
    expect(report.ready, isTrue);
    expect(report.leftOut.map((x) => x.name), ['vendored']);
    expect(report.leftOut.single.detail, contains('SomeVendorSDK'));
    expect(report.render(), contains('✖ vendored 1.0.0'));
    expect(report.render(), contains('leaves out the native code of vendored'));
    expect(
      Directory(p.join(temp.path, 'xcross_overrides')).existsSync(),
      isFalse,
    );

    // --strict makes it a failure; the plain run does not.
    final strict = await prepare().run(temp.path, strict: true);
    expect(strict.ready, isFalse);
    await command([]); // not strict: no error
    await expectLater(command(['--strict']), throwsA(isA<CliError>()));
  });

  test('AC-032-6 drafts switched off leave podspec-only plugins out', () async {
    freshProject();
    addPlugin('draftable', podspec: podspecKnown);
    writeMetadata();
    final report = await prepare(
      environment: {'XCROSS_PLUGIN_DRAFTS': 'off'},
    ).run(temp.path);
    expect(report.leftOut.map((x) => x.name), ['draftable']);
    expect(report.leftOut.single.detail, contains('XCROSS_PLUGIN_DRAFTS=off'));
  });

  test(
    'AC-032-7 --json is one ios_prepare line; --no-pub skips pub get',
    () async {
      freshProject();
      addPlugin('vendored', podspec: podspecUnknown);
      writeMetadata();
      await command(['--json', '--no-pub']);
      expect(pubGets, isEmpty);
      final json = jsonDecode(out.join().trim()) as Map<String, Object?>;
      expect(json['v'], 1);
      expect(json['type'], 'ios_prepare');
      expect(json['ready'], isTrue);
      expect(json['leftOut'], ['vendored']);
      expect(json['bundleId'], 'com.example.fresh');
      expect((json['steps']! as List).length, 4);

      out.clear();
      await command(['--json']);
      expect(pubGets, [p.normalize(temp.path)]);
    },
  );
}
