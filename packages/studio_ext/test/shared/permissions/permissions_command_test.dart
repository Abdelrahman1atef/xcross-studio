// studio: 027 — `xcross permissions` and `xcross capabilities`
// (AC-027-5…AC-027-12).
import 'dart:convert';
import 'dart:io';

import 'package:apple_developer_kit/shared/appstoreconnect/asc_capabilities.dart';
import 'package:args/command_runner.dart';
import 'package:cli_kit/composition/native_host.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/permissions/permissions_command.dart';
import 'package:studio_ext/src/shared/permissions/capability_catalog.dart';
import 'package:studio_ext/src/shared/permissions/permission_catalog.dart';
import 'package:studio_ext/src/shared/release/release_tables.dart';
import 'package:test/test.dart';

const _info =
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
    '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    '<plist version="1.0">\n<dict>\n'
    '\t<key>CFBundleName</key>\n\t<string>\$(PRODUCT_NAME)</string>\n'
    '\t<key>NSMicrophoneUsageDescription</key>\n'
    '\t<string>TODO</string>\n'
    '\t<key>UIBackgroundModes</key>\n'
    '\t<array>\n\t\t<string>fetch</string>\n\t</array>\n'
    '</dict>\n</plist>\n';

void main() {
  late Directory project;
  late StringBuffer out;

  setUp(() {
    project = Directory.systemTemp.createTempSync('permissions-');
    void write(String relative, String text) =>
        File(p.joinAll([project.path, ...relative.split('/')]))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(text);
    write('pubspec.yaml', 'name: app\n');
    write('ios/Runner/Info.plist', _info);
    write(
      '.flutter-plugins-dependencies',
      jsonEncode({
        'plugins': {
          'ios': [
            {'name': 'image_picker_ios'},
            {'name': 'geolocator_apple'},
          ],
        },
      }),
    );
    out = StringBuffer();
  });
  tearDown(() => project.deleteSync(recursive: true));

  PermissionsContext context(DateTime? now) => PermissionsContext(
    fileSystem: detectPlatformHost().fileSystem,
    paths: p.context,
    currentDirectory: () => Directory.current.path,
    write: (text) => out.write(text),
    now: now == null ? null : () => now,
  );

  Future<void> run(List<String> args, {DateTime? now}) =>
      (CommandRunner<void>('xcross', 'test')
            ..addCommand(PermissionsCommand(context(now)))
            ..addCommand(CapabilitiesCommand(context(now))))
          .run([...args, '--project', project.path]);

  Map<String, Object?> json() =>
      (jsonDecode(out.toString().trim()) as Map).cast<String, Object?>();

  String read(String relative) => File(
    p.joinAll([project.path, ...relative.split('/')]),
  ).readAsStringSync();

  group('AC-027-5 permissions list', () {
    test(
      'shows what is set, what is a placeholder, and what plugins need',
      () async {
        await run(['permissions', 'list', '--json']);
        final report = json();
        expect(report['type'], 'permissions');
        final permissions = (report['permissions']! as List)
            .cast<Map<String, Object?>>();
        expect(permissions.single['key'], 'NSMicrophoneUsageDescription');
        expect(permissions.single['status'], 'placeholder');
        expect(permissions.single['name'], 'Microphone');
        final missing = (report['missing']! as List)
            .cast<Map<String, Object?>>();
        expect(
          {for (final m in missing) m['resource']},
          {'camera', 'photo library', 'location'},
        );
        final camera = missing.firstWhere((m) => m['resource'] == 'camera');
        expect(camera['keys'], ['NSCameraUsageDescription']);
        expect(camera['plugins'], ['image_picker_ios']);
        expect(report['catalog']! as List, isNotEmpty);
      },
    );

    test('the text report names the missing key', () async {
      await run(['permissions', 'list']);
      expect(out.toString(), contains('NSMicrophoneUsageDescription'));
      expect(
        out.toString(),
        contains(
          'missing: camera (image_picker_ios) needs NSCameraUsageDescription',
        ),
      );
    });

    test('a folder without an iOS app is a coded error', () {
      File(p.join(project.path, 'ios', 'Runner', 'Info.plist')).deleteSync();
      expect(
        run(['permissions', 'list']),
        throwsA(
          isA<CliError>().having(
            (e) => e.message,
            'message',
            contains('[permissions.no_ios]'),
          ),
        ),
      );
    });
  });

  group('AC-027-6 permissions set and remove', () {
    test(
      'set adds the key and leaves everything else, with a backup',
      () async {
        final when = DateTime(2026, 11, 5, 18, 30, 15);
        await run([
          'permissions',
          'set',
          'NSCameraUsageDescription',
          'This app uses the camera to scan codes.',
          '--json',
        ], now: when);
        final change = json();
        expect(change['changed'], isTrue);
        expect(
          change['backup'],
          '.xcross/permission-backups/20261105-183015/ios/Runner/Info.plist',
        );
        expect(read(change['backup']! as String), _info);
        expect(
          read('ios/Runner/Info.plist'),
          _info.replaceFirst(
            '</dict>\n</plist>',
            '\t<key>NSCameraUsageDescription</key>\n'
                '\t<string>This app uses the camera to scan codes.</string>\n'
                '</dict>\n</plist>',
          ),
        );
      },
    );

    test('setting the same sentence again changes nothing', () async {
      await run([
        'permissions',
        'set',
        'NSMicrophoneUsageDescription',
        'TODO',
        '--json',
      ]);
      expect(json()['changed'], isFalse);
      expect(json()['backup'], isNull);
      expect(read('ios/Runner/Info.plist'), _info);
    });

    test('a placeholder sentence is written with a note', () async {
      await run([
        'permissions',
        'set',
        'NSCameraUsageDescription',
        'TODO',
        '--json',
      ]);
      expect((json()['notes']! as List).single, contains('placeholder'));
    });

    test(
      'remove takes the key out, and is a no-op for a key that is not there',
      () async {
        await run([
          'permissions',
          'remove',
          'NSMicrophoneUsageDescription',
          '--json',
        ]);
        expect(json()['changed'], isTrue);
        expect(
          read('ios/Runner/Info.plist'),
          _info.replaceFirst(
            '\t<key>NSMicrophoneUsageDescription</key>\n\t<string>TODO</string>\n',
            '',
          ),
        );
        out.clear();
        await run([
          'permissions',
          'remove',
          'NSMicrophoneUsageDescription',
          '--json',
        ]);
        expect(json()['changed'], isFalse);
      },
    );

    test(
      'a key that is not a purpose string, or an empty sentence, is refused',
      () {
        expect(
          run(['permissions', 'set', 'CFBundleName', 'Name of the app']),
          throwsA(
            isA<CliError>().having(
              (e) => e.message,
              'message',
              contains('[permissions.bad_key]'),
            ),
          ),
        );
        expect(
          run(['permissions', 'set', 'NSCameraUsageDescription', '  ']),
          throwsA(
            isA<CliError>().having(
              (e) => e.message,
              'message',
              contains('[permissions.empty_value]'),
            ),
          ),
        );
      },
    );

    test('a binary Info.plist is refused, not rewritten', () {
      File(
        p.join(project.path, 'ios', 'Runner', 'Info.plist'),
      ).writeAsStringSync('bplist00xxxx');
      expect(
        run(['permissions', 'set', 'NSCameraUsageDescription', 'Scan codes.']),
        throwsA(
          isA<CliError>().having(
            (e) => e.message,
            'message',
            contains('[permissions.binary_plist]'),
          ),
        ),
      );
      expect(read('ios/Runner/Info.plist'), 'bplist00xxxx');
    });
  });

  group('AC-027-7 capabilities', () {
    test(
      'list shows what is on, and that the entitlements file is missing',
      () async {
        await run(['capabilities', 'list', '--json']);
        final report = json();
        expect((report['entitlements']! as Map)['exists'], isFalse);
        final byId = {
          for (final c
              in (report['capabilities']! as List).cast<Map<String, Object?>>())
            c['id']: c,
        };
        expect(byId['background-modes']!['enabled'], isTrue);
        expect(byId['push']!['enabled'], isFalse);
        expect(byId['push']!['ascCapability'], 'PUSH_NOTIFICATIONS');
      },
    );

    test(
      'add push creates the entitlements file and says what is left to do',
      () async {
        await run(['capabilities', 'add', 'push', '--json']);
        final change = json();
        expect(change['changed'], isTrue);
        expect(
          (change['notes']! as List).join('\n'),
          allOf(
            contains('PUSH_NOTIFICATIONS'),
            contains('CODE_SIGN_ENTITLEMENTS'),
          ),
        );
        expect(
          read('ios/Runner/Runner.entitlements'),
          contains(
            '<key>aps-environment</key>\n\t<string>development</string>',
          ),
        );
      },
    );

    test('add associated-domains needs a value, and values add up', () async {
      expect(
        run(['capabilities', 'add', 'associated-domains']),
        throwsA(
          isA<CliError>().having(
            (e) => e.message,
            'message',
            contains('[capabilities.value_required]'),
          ),
        ),
      );
      await run([
        'capabilities',
        'add',
        'associated-domains',
        '--value',
        'applinks:a.example.com',
      ]);
      await run([
        'capabilities',
        'add',
        'associated-domains',
        '--value',
        'webcredentials:a.example.com',
        '--value',
        'applinks:a.example.com',
      ]);
      expect(
        read('ios/Runner/Runner.entitlements'),
        contains(
          '\t<array>\n'
          '\t\t<string>applinks:a.example.com</string>\n'
          '\t\t<string>webcredentials:a.example.com</string>\n'
          '\t</array>',
        ),
      );
    });

    test(
      'add background-modes works in Info.plist and keeps the modes already there',
      () async {
        await run([
          'capabilities',
          'add',
          'background-modes',
          '--value',
          'remote-notification',
        ]);
        expect(
          read('ios/Runner/Info.plist'),
          contains(
            '<array>\n\t\t<string>fetch</string>\n'
            '\t\t<string>remote-notification</string>\n\t</array>',
          ),
        );
        expect(
          run([
            'capabilities',
            'add',
            'background-modes',
            '--value',
            'dancing',
          ]),
          throwsA(isA<UsageException>()),
        );
      },
    );

    test('remove turns it off; a value removes just that value', () async {
      await run(['capabilities', 'add', 'push']);
      out.clear();
      await run(['capabilities', 'remove', 'push', '--json']);
      expect(json()['changed'], isTrue);
      expect(
        read('ios/Runner/Runner.entitlements'),
        isNot(contains('aps-environment')),
      );
      out.clear();
      await run(['capabilities', 'remove', 'push', '--json']);
      expect(json()['changed'], isFalse);

      await run([
        'capabilities',
        'add',
        'app-groups',
        '--value',
        'group.a',
        '--value',
        'group.b',
      ]);
      await run(['capabilities', 'remove', 'app-groups', '--value', 'group.a']);
      final entitlements = read('ios/Runner/Runner.entitlements');
      expect(entitlements, contains('group.b'));
      expect(entitlements, isNot(contains('group.a')));
    });

    test(
      'an entitlements file the project names is the one that is edited',
      () async {
        File(p.join(project.path, 'ios', 'Runner.xcodeproj', 'project.pbxproj'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(
            'CODE_SIGN_ENTITLEMENTS = Runner/Custom.entitlements;\n',
          );
        await run(['capabilities', 'add', 'push', '--json']);
        expect(
          (json()['notes']! as List).join(),
          isNot(contains('CODE_SIGN_ENTITLEMENTS')),
          reason: 'Xcode already knows the file',
        );
        expect(
          File(
            p.join(project.path, 'ios', 'Runner', 'Custom.entitlements'),
          ).existsSync(),
          isTrue,
        );
      },
    );

    test('an unknown capability lists the known ones', () {
      expect(
        run(['capabilities', 'add', 'teleport']),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            contains('push'),
          ),
        ),
      );
    });
  });

  group('AC-027-8 catalogs', () {
    test('every key the release check knows is in the permission catalog', () {
      final keys = <String>{
        for (final needs in ReleaseTables.pluginUsage.values)
          for (final need in needs) ...need.anyOf,
        for (final rule in ReleaseTables.usageSymbols) ...rule.allOf,
      };
      for (final key in keys) {
        expect(PermissionCatalog.of(key), isNotNull, reason: key);
      }
      for (final info in PermissionCatalog.all) {
        expect(ReleaseTables.isUsageKey(info.key), isTrue, reason: info.key);
        expect(
          ReleaseTables.isPlaceholderPurpose(info.key, info.suggestion),
          isFalse,
          reason: '${info.key} suggests a sentence the release check rejects',
        );
      }
    });

    test(
      'each capability names the App Store Connect type xcross maps it to',
      () {
        for (final capability in CapabilityCatalog.all) {
          expect(
            AscCapabilities.byEntitlementKey[capability.key],
            capability.ascCapability,
            reason: capability.id,
          );
        }
        final ids = CapabilityCatalog.all.map((c) => c.id).toList();
        expect(ids.toSet(), hasLength(ids.length));
      },
    );
  });
}
