// studio: 028 — `xcross plugin status`, `plugin ack`, and the safe `--force`
// (AC-028-1…AC-028-8).
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/plugins/plugin_command.dart';
import 'package:test/test.dart';

import '../../support/test_file_system.dart';

const _toastSpec =
    "Pod::Spec.new do |s|\n  s.name = 'toaster'\n"
    "  s.source_files = 'Classes/**/*'\n"
    "  s.dependency 'Flutter'\n"
    "  s.resource_bundles = {'toaster_privacy' => "
    "['Resources/PrivacyInfo.xcprivacy']}\nend\n";

const _plainSpec = "Pod::Spec.new do |s|\n  s.dependency 'Flutter'\nend\n";

void main() {
  late Directory temp;
  late List<String> out;
  final entries = <Map<String, String>>[];

  setUp(() {
    temp = Directory.systemTemp.createTempSync('xcross_plugin_status_');
    out = [];
    entries.clear();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  void addPlugin(
    String name, {
    String? podspec,
    bool swiftPackage = false,
    String version = '1.0.0',
    bool privacy = false,
  }) {
    final root = p.join(temp.path, 'pub', name);
    File(p.join(root, 'pubspec.yaml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('name: $name\nversion: $version\n');
    if (podspec != null) {
      File(p.join(root, 'ios', '$name.podspec'))
        ..createSync(recursive: true)
        ..writeAsStringSync(podspec);
      File(p.join(root, 'ios', 'Classes', 'Plugin.swift'))
        ..createSync(recursive: true)
        ..writeAsStringSync('import Flutter\n');
    }
    if (privacy) {
      File(p.join(root, 'ios', 'Resources', 'PrivacyInfo.xcprivacy'))
        ..createSync(recursive: true)
        ..writeAsStringSync('<plist/>');
    }
    if (swiftPackage) {
      File(p.join(root, 'ios', name, 'Package.swift'))
        ..createSync(recursive: true)
        ..writeAsStringSync('// shipped');
    }
    entries.removeWhere((entry) => entry['name'] == name);
    entries.add({'name': name, 'path': root});
  }

  Future<void> plugin(List<String> args) {
    File(p.join(temp.path, '.flutter-plugins-dependencies')).writeAsStringSync(
      jsonEncode({
        'plugins': {'ios': entries},
      }),
    );
    return (CommandRunner<void>('xcross', 'test')..addCommand(
          PluginCommand(
            fileSystem: const IoFileSystem(),
            paths: p.context,
            write: out.add,
          ),
        ))
        .run(['plugin', ...args, '--project', temp.path]);
  }

  Future<Map<String, Map<String, Object?>>> status() async {
    out.clear();
    await plugin(['status', '--json']);
    final report = jsonDecode(out.join().trim()) as Map<String, Object?>;
    expect(report['type'], 'plugin_status');
    return {
      for (final entry
          in (report['plugins']! as List).cast<Map<String, Object?>>())
        entry['name']! as String: entry,
    };
  }

  String overrides(String relative) =>
      p.joinAll([temp.path, 'xcross_overrides', ...relative.split('/')]);

  test(
    'AC-028-1 each plugin is classified, and a pod nobody knows is a problem',
    () async {
      addPlugin('modern', swiftPackage: true);
      addPlugin('dart_only');
      addPlugin('draftable', podspec: _plainSpec);
      addPlugin(
        'vendored',
        podspec:
            "Pod::Spec.new do |s|\n  s.dependency 'Flutter'\n"
            "  s.dependency 'SomeVendorSDK', '~> 1.0'\nend\n",
      );
      final all = await status();
      expect(all['modern']!['kind'], 'swiftpm');
      expect(all['dart_only']!['kind'], 'no_ios_code');
      expect(all['draftable']!['kind'], 'podspec_only');
      expect(all['draftable']!['problems'], isEmpty);
      final vendored = all['vendored']!;
      expect(
        ((vendored['problems']! as List).single as Map)['code'],
        'unknown_pods',
      );
      expect(vendored['action'], 'manual');
      expect(vendored['command'], isNull);
    },
  );

  test(
    'AC-028-2 a draft xcross wrote waits for a review until it is acknowledged',
    () async {
      addPlugin('draftable', podspec: _plainSpec);
      await plugin(['shim', 'draftable']);
      var draft = (await status())['draftable']!;
      expect(draft['kind'], 'draft');
      expect(draft['overridePath'], 'xcross_overrides/draftable/1.0.0');
      expect(
        ((draft['problems']! as List).single as Map)['code'],
        'review_pending',
      );
      expect(draft['action'], 'review');
      expect(draft['command'], ['plugin', 'ack', 'draftable']);
      expect(draft['canRegenerate'], isTrue);

      out.clear();
      await plugin(['ack', 'draftable']);
      expect(out.join(), contains('marked as reviewed'));
      draft = (await status())['draftable']!;
      expect(draft['problems'], isEmpty);
      expect(draft['action'], isNull);
      expect(
        () => plugin(['ack', 'draftable']),
        returnsNormally,
        reason: 'acknowledging twice is fine',
      );
    },
  );

  test(
    'AC-028-3 a draft without the privacy manifest the plugin ships is found, and regenerated with a backup',
    () async {
      addPlugin('toaster', podspec: _toastSpec, privacy: true);
      await plugin(['shim', 'toaster']);
      await plugin(['ack', 'toaster']);
      expect((await status())['toaster']!['problems'], isEmpty);

      // A draft from an older xcross: the manifest copy is not there.
      File(
        overrides('toaster/1.0.0/Classes/PrivacyInfo.xcprivacy'),
      ).deleteSync();
      final broken = (await status())['toaster']!;
      expect(
        ((broken['problems']! as List).single as Map)['code'],
        'manifest_missing',
      );
      expect(broken['action'], 'regenerate');
      expect(broken['command'], ['plugin', 'shim', 'toaster', '--force']);

      out.clear();
      await plugin(['shim', 'toaster', '--force']);
      expect(out.join(), contains('Kept the old files in'));
      expect(
        File(
          overrides('toaster/1.0.0/Classes/PrivacyInfo.xcprivacy'),
        ).existsSync(),
        isTrue,
      );
      final backups = Directory(p.join(temp.path, '.xcross', 'plugin-backups'))
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => p.basename(f.path));
      expect(backups, contains('Package.swift'));
      // Regenerating wrote a new draft, so it is up for review again.
      expect(
        (((await status())['toaster']!['problems']! as List).single
            as Map)['code'],
        'review_pending',
      );
    },
  );

  test(
    'AC-028-4 an override for another version of the plugin is stale, in status and in check',
    () async {
      addPlugin('draftable', podspec: _plainSpec);
      await plugin(['shim', 'draftable']);
      addPlugin('draftable', podspec: _plainSpec, version: '2.0.0');
      final stale = (await status())['draftable']!;
      expect(((stale['problems']! as List).first as Map)['code'], 'stale');
      expect(stale['action'], 'regenerate');
      await expectLater(
        plugin(['check']),
        throwsA(
          isA<CliError>().having(
            (e) => e.toString(),
            'message',
            contains('plugin.override_stale'),
          ),
        ),
      );
      // Regenerating writes the folder for the new version.
      await plugin(['shim', 'draftable', '--force']);
      expect(
        File(overrides('draftable/2.0.0/Package.swift')).existsSync(),
        isTrue,
      );
      final fixed = (await status())['draftable']!;
      expect(
        (fixed['problems']! as List).map((p) => (p as Map)['code']),
        isNot(contains('stale')),
      );
    },
  );

  test(
    'AC-028-5 a Package.swift the developer wrote is never replaced by accident',
    () async {
      addPlugin('handmade', podspec: _plainSpec);
      File(overrides('handmade/1.0.0/Package.swift'))
        ..createSync(recursive: true)
        ..writeAsStringSync('// swift-tools-version: 5.9\n// mine\n');
      final mine = (await status())['handmade']!;
      expect(mine['kind'], 'hand_written');
      expect(mine['canRegenerate'], isFalse);
      expect(mine['problems'], isEmpty);

      await expectLater(
        plugin(['shim', 'handmade', '--force']),
        throwsA(
          isA<CliError>().having(
            (e) => e.toString(),
            'message',
            contains('plugin.hand_written'),
          ),
        ),
      );
      expect(
        File(overrides('handmade/1.0.0/Package.swift')).readAsStringSync(),
        contains('// mine'),
      );

      await plugin(['shim', 'handmade', '--force', '--replace-hand-written']);
      expect(
        File(overrides('handmade/1.0.0/Package.swift')).readAsStringSync(),
        contains('DRAFT generated by `xcross plugin shim`'),
      );
      final backed = Directory(
        p.join(temp.path, '.xcross', 'plugin-backups'),
      ).listSync(recursive: true).whereType<File>().single;
      expect(backed.readAsStringSync(), contains('// mine'));
    },
  );

  test(
    'AC-028-6 the ledger is one file at the root of xcross_overrides',
    () async {
      addPlugin('draftable', podspec: _plainSpec);
      await plugin(['shim', 'draftable']);
      final ledger = File(overrides('.xcross-drafts.json'));
      expect(ledger.existsSync(), isTrue);
      final json =
          jsonDecode(ledger.readAsStringSync()) as Map<String, Object?>;
      expect(json.keys, ['draftable/1.0.0']);
      expect((json['draftable/1.0.0']! as Map)['reviewed'], isFalse);
      expect(
        Directory(
          overrides('draftable/1.0.0'),
        ).listSync().map((e) => p.basename(e.path)),
        ['Package.swift'],
        reason: 'nothing of the ledger is laid over the plugin at build time',
      );
    },
  );

  test(
    'AC-028-7 ack names a plugin that does not exist or has no draft',
    () async {
      addPlugin('modern', swiftPackage: true);
      await expectLater(
        plugin(['ack', 'missing']),
        throwsA(
          isA<CliError>().having(
            (e) => e.toString(),
            'message',
            contains('plugin.not_found'),
          ),
        ),
      );
      await expectLater(
        plugin(['ack', 'modern']),
        throwsA(
          isA<CliError>().having(
            (e) => e.toString(),
            'message',
            contains('plugin.no_draft'),
          ),
        ),
      );
    },
  );
}
