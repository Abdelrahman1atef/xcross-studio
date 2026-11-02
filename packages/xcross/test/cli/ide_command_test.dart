import 'dart:convert';
import 'dart:io';

import 'package:cli_kit/host/linux/linux_host.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/cli/ide/subcommands/idea_command.dart';
import 'package:xcross/src/shared/cli/ide/subcommands/vscode_command.dart';
import 'package:xcross/src/shared/cli/ide/subcommands/vscode_json_merge.dart';
import 'package:xcross/src/shared/cli/ide/xcross_executable.dart';
import 'package:xcross/src/shared/errors/errors.dart';

import '../log_fixture.dart';
import 'runtime_fixture.dart';

void main() {
  test('uses configured IDE launcher and selector overrides', () {
    final launcher = XcrossIdeLauncher(
      host: testRuntime().host,
      log: testLog(),
      executable: '/configured/xcross',
      configPath: '/configured/config.yaml',
      declarative: true,
    );

    expect(
      launcher.resolve(subcommand: 'vscode', brokenFeature: 'debugging'),
      '/configured/xcross',
    );
    expect(launcher.generatedEnvironment, {
      'XCROSS_CONFIG': '/configured/config.yaml',
    });
  });

  group('VscodeJsonMerge.stripJsonc / VscodeJsonMerge.parseJsonc', () {
    test('strips line and block comments outside strings', () {
      const raw = '''
{
  // line comment
  "a": 1, /* block */
  "url": "http://example.com" // keep // in string above
}
''';
      expect(VscodeJsonMerge.parseJsonc(raw), {
        'a': 1,
        'url': 'http://example.com',
      });
    });

    test('strips trailing commas in objects and arrays', () {
      expect(VscodeJsonMerge.parseJsonc('{\n  "a": 1,\n  "b": false,\n}\n'), {
        'a': 1,
        'b': false,
      });
      expect(VscodeJsonMerge.parseJsonc('[1, 2, ]'), [1, 2]);
      expect(VscodeJsonMerge.parseJsonc('{"a": 1, // trailing\n}'), {'a': 1});
      // Comma inside a string must survive.
      expect(VscodeJsonMerge.parseJsonc('{"x": "a,b"}'), {'x': 'a,b'});
    });
  });

  group('VscodeJsonMerge.mergeLaunchDoc', () {
    test('creates a fresh document', () {
      final doc = VscodeJsonMerge.mergeLaunchDoc(null);
      expect(doc['version'], '0.2.0');
      final configs = doc['configurations']! as List;
      expect(configs, hasLength(2));
      expect(configs.first, {
        ...VscodeJsonMerge.xcrossLaunchFields(),
        'env': {'XCROSS': 'true'},
        'args': <Object?>[],
      });
      expect(configs.last, {
        ...VscodeJsonMerge.xcrossLaunchFields(xcrossReleaseLaunchName),
        'env': {'XCROSS': 'true'},
        'args': <Object?>['--release'],
      });
    });

    test('AC-005-1 the iPhone shows as debug and release entries; a '
        'release entry keeps its args', () {
      final first = VscodeJsonMerge.mergeLaunchDoc(null);
      final names = [
        for (final c in first['configurations']! as List) (c as Map)['name'],
      ];
      expect(names, [xcrossLaunchName, xcrossReleaseLaunchName]);
      expect(xcrossLaunchName, contains('iPhone'));
      expect(xcrossReleaseLaunchName, contains('iOS 15/16'));

      final again = VscodeJsonMerge.mergeLaunchDoc({
        'configurations': [
          {
            'name': xcrossReleaseLaunchName,
            'type': 'dart',
            'env': {'XCROSS': 'true'},
            'args': ['--udid', 'ABC'],
          },
        ],
      });
      final configs = again['configurations']! as List;
      expect(configs, hasLength(2));
      final release =
          configs.firstWhere(
                (c) => (c as Map)['name'] == xcrossReleaseLaunchName,
              )
              as Map;
      expect(release['args'], ['--udid', 'ABC', '--release']);
    });

    test('propagates configured selector into generated environment', () {
      final doc = VscodeJsonMerge.mergeLaunchDoc(
        null,
        generatedEnvironment: const {'XCROSS_CONFIG': '/config.yaml'},
      );
      for (final config in doc['configurations']! as List) {
        expect((config as Map)['env'], {
          'XCROSS_CONFIG': '/config.yaml',
          'XCROSS': 'true',
        });
      }
    });

    test('appends beside foreign configs and preserves their content', () {
      final doc = VscodeJsonMerge.mergeLaunchDoc({
        'version': '0.2.0',
        'configurations': [
          {'name': 'Flutter', 'type': 'dart', 'request': 'launch'},
        ],
      });
      final configs = doc['configurations']! as List;
      expect(configs, hasLength(3));
      expect(configs.first, {
        'name': 'Flutter',
        'type': 'dart',
        'request': 'launch',
      });
      expect((configs[1] as Map)['env'], {'XCROSS': 'true'});
    });

    test('preserves args on an existing xcross entry', () {
      final doc = VscodeJsonMerge.mergeLaunchDoc({
        'version': '0.2.0',
        'configurations': [
          {
            'name': 'xcross: iOS device',
            'type': 'dart',
            'xcross': true,
            'env': {'MY_KEY': 'mine'},
            'args': ['--udid', 'ABC'],
            'extra': true,
          },
        ],
      });
      final entry = (doc['configurations']! as List).first as Map;
      expect(entry['name'], xcrossLaunchName, reason: 'legacy name renamed');
      expect(entry['args'], ['--udid', 'ABC']);
      expect(entry['env'], {'MY_KEY': 'mine', 'XCROSS': 'true'});
      expect(entry.containsKey('xcross'), isFalse);
      expect(entry['extra'], true);
      expect(entry['program'], 'lib/main.dart');
      expect(entry['debuggerType'], 'flutter');
    });

    test('matches by name when the xcross marker is missing', () {
      final doc = VscodeJsonMerge.mergeLaunchDoc({
        'configurations': [
          {'name': 'xcross: iOS device', 'type': 'dart'},
        ],
      });
      final entry = (doc['configurations']! as List).first as Map;
      expect(entry['env'], {'XCROSS': 'true'});
      expect(entry['args'], <Object?>[]);
    });
  });

  group('VscodeJsonMerge.mergeSettingsDoc', () {
    test('upserts DAP keys without wiping siblings', () {
      expect(
        VscodeJsonMerge.mergeSettingsDoc({
          'editor.fontSize': 14,
          dapPathSetting: 'stale',
        }),
        {
          'editor.fontSize': 14,
          dapPathSetting: dapPathValue,
          promptErrorsSetting: false,
        },
      );
    });
  });

  group('VscodeCommand upsert', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('xcross-ide-vscode-');
    });

    tearDown(() {
      temp.deleteSync(recursive: true);
    });

    test(
      testOn: '!windows',

      'creates launch.json and settings.json, then skips when current',
      () async {
        await VscodeCommand(
          XcrossIdeLauncher(
            host: LinuxHost(currentDirectory: temp.path),
            log: testLog(),
            executable: '/test/xcross',
          ),
        ).run();
        final launch = File(p.join(temp.path, '.vscode', 'launch.json'));
        final settings = File(p.join(temp.path, '.vscode', 'settings.json'));
        final shim = File(p.join(temp.path, '.vscode', 'xcross_dap.dart'));
        expect(shim.existsSync(), isTrue);
        final shimSource = shim.readAsStringSync();
        expect(shimSource, contains("'flutter', 'dap'"));
        expect(shimSource, contains("if (args.contains('--test')) '--test'"));
        expect(shimSource, isNot(contains('Platform.environment')));
        expect(shimSource, isNot(contains('bin/flutter')));

        expect(launch.existsSync(), isTrue);
        expect(settings.existsSync(), isTrue);

        final launchBefore = launch.readAsStringSync();
        final settingsBefore = settings.readAsStringSync();
        await VscodeCommand(
          XcrossIdeLauncher(
            host: LinuxHost(currentDirectory: temp.path),
            log: testLog(),
            executable: '/test/xcross',
          ),
        ).run();
        expect(launch.readAsStringSync(), launchBefore);
        expect(settings.readAsStringSync(), settingsBefore);
      },
    );

    test(
      testOn: '!windows',
      'merges into existing files and fixes stale DAP path',
      () async {
        final vscode = Directory(p.join(temp.path, '.vscode'))..createSync();
        File(p.join(vscode.path, 'launch.json')).writeAsStringSync(
          jsonEncode({
            'version': '0.2.0',
            'configurations': [
              {'name': 'Flutter', 'type': 'dart', 'request': 'launch'},
            ],
          }),
        );
        File(p.join(vscode.path, 'settings.json')).writeAsStringSync(
          jsonEncode({'editor.fontSize': 14, dapPathSetting: 'stale'}),
        );

        await VscodeCommand(
          XcrossIdeLauncher(
            host: LinuxHost(currentDirectory: temp.path),
            log: testLog(),
            executable: '/test/xcross',
          ),
        ).run();

        final launch =
            jsonDecode(
                  File(p.join(vscode.path, 'launch.json')).readAsStringSync(),
                )
                as Map;
        final configs = launch['configurations'] as List;
        final first = configs.first as Map;
        final last = configs.last as Map;
        expect(configs, hasLength(2));
        expect(first['name'], 'Flutter');
        expect(last['env'], {'XCROSS': 'true'});

        final settings =
            jsonDecode(
                  File(p.join(vscode.path, 'settings.json')).readAsStringSync(),
                )
                as Map;
        expect(settings['editor.fontSize'], 14);
        expect(settings[dapPathSetting], dapPathValue);
        expect(settings[promptErrorsSetting], false);
      },
    );

    test(testOn: '!windows', 'refuses to clobber invalid JSONC', () async {
      final vscode = Directory(p.join(temp.path, '.vscode'))..createSync();
      File(p.join(vscode.path, 'launch.json')).writeAsStringSync('{not json');

      await expectLater(
        VscodeCommand(
          XcrossIdeLauncher(
            host: LinuxHost(currentDirectory: temp.path),
            log: testLog(),
            executable: '/test/xcross',
          ),
        ).run(),
        throwsA(isA<XcrossError>()),
      );
    });
  });

  group('IdeaCommand.buildIdeaRunXml', () {
    test('embeds exe, DAPConfiguration, xcross launch, and dart mapping', () {
      final xml = IdeaCommand.buildIdeaRunXml(r'C:\tools\xcross.exe');
      expect(xml, contains('type="DAPConfiguration"'));
      expect(xml, contains('factoryName="DAPConfiguration"'));
      expect(xml, contains(r'C:\tools\xcross.exe'));
      expect(xml, contains(' flutter dap'));
      expect(
        xml,
        contains('&quot;env&quot;:{&quot;XCROSS&quot;:&quot;true&quot;}'),
      );
      expect(xml, contains('*.dart'));
      expect(xml, contains(r'$PROJECT_DIR$'));
      expect(xml, contains('debugServerWaitStrategy" value="TIMEOUT"'));
      expect(xml, contains('connectTimeout" value="0"'));
    });

    test('embeds configured selector in launch environment', () {
      final xml = IdeaCommand.buildIdeaRunXml(
        '/xcross',
        environment: const {'XCROSS_CONFIG': '/config.yaml'},
      );
      expect(
        xml,
        contains('&quot;XCROSS_CONFIG&quot;:&quot;/config.yaml&quot;'),
      );
    });

    test('quotes paths with spaces', () {
      final xml = IdeaCommand.buildIdeaRunXml(r'C:\Program Files\xcross.exe');
      expect(
        xml,
        contains(r'&quot;C:\Program Files\xcross.exe&quot; flutter dap'),
      );
    });
  });

  group('IdeaCommand', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('xcross-ide-idea-');
    });

    tearDown(() {
      temp.deleteSync(recursive: true);
    });

    test(
      testOn: '!windows',
      'writes .run/xcross_ios_device.run.xml once',
      () async {
        await IdeaCommand(
          XcrossIdeLauncher(
            host: LinuxHost(currentDirectory: temp.path),
            log: testLog(),
            executable: '/test/xcross',
          ),
        ).run();
        final file = File(
          p.join(temp.path, '.run', 'xcross_ios_device.run.xml'),
        );
        expect(file.existsSync(), isTrue);
        final body = file.readAsStringSync();
        expect(body, contains('DAPConfiguration'));
        expect(body, contains('*.dart'));

        final before = body;
        await IdeaCommand(
          XcrossIdeLauncher(
            host: LinuxHost(currentDirectory: temp.path),
            log: testLog(),
            executable: '/test/xcross',
          ),
        ).run();
        expect(file.readAsStringSync(), before);
      },
    );

    test(
      testOn: '!windows',
      'AC-005-1 writes debug + release entries and updates its own stale '
      'file, never a user-made one',
      () async {
        Future<void> run(String exe) => IdeaCommand(
          XcrossIdeLauncher(
            host: LinuxHost(currentDirectory: temp.path),
            log: testLog(),
            executable: exe,
          ),
        ).run();
        final run_ = p.join(temp.path, '.run');
        await run('/old/xcross');
        final debug = File(p.join(run_, 'xcross_ios_device.run.xml'));
        final release = File(p.join(run_, 'xcross_ios_release.run.xml'));
        expect(debug.readAsStringSync(), contains(xcrossLaunchName));
        expect(release.readAsStringSync(), contains(xcrossReleaseLaunchName));
        expect(release.readAsStringSync(), contains('--release'));

        // A newer xcross path: xcross's own files are updated, with a backup.
        await run('/new/xcross');
        expect(debug.readAsStringSync(), contains('/new/xcross flutter dap'));
        expect(
          File('${debug.path}.bak').readAsStringSync(),
          contains('/old/xcross flutter dap'),
        );

        // A run config the user wrote is left alone.
        release.writeAsStringSync('<component name="Mine" />');
        await run('/newer/xcross');
        expect(release.readAsStringSync(), '<component name="Mine" />');
        expect(IdeaCommand.isXcrossRunXml(debug.readAsStringSync()), isTrue);
      },
    );
  });
}
