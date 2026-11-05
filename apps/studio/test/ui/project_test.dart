// Features 027 and 028: the Project page (permissions, capabilities, plugins)
// and the to-do list that follows the developer around the app.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcross_studio/app/app.dart';
import 'package:xcross_studio/app/services.dart';
import 'package:xcross_studio/design_system/design_system.dart';
import 'package:xcross_studio/src/cli/xcross_commands.dart';
import 'package:xcross_studio/src/host/host_platform.dart';
import 'package:xcross_studio/src/state/job.dart';
import 'package:xcross_studio/src/state/log_session.dart';
import 'package:xcross_studio/src/state/settings.dart';

import '../support/fake_launcher.dart';
import 'app_test.dart' show settle, go;

String _json(Map<String, Object?> event) => jsonEncode({'v': 1, ...event});

Map<String, Object?> _permissions({bool micFixed = false}) => {
  'type': 'permissions',
  'permissions': [
    {
      'key': 'NSMicrophoneUsageDescription',
      'name': 'Microphone',
      'value': micFixed ? 'This app records voice messages.' : 'TODO',
      'status': micFixed ? 'ok' : 'placeholder',
      'description': 'Record audio.',
      'neededBy': ['record'],
    },
  ],
  'missing': [
    {
      'resource': 'camera',
      'keys': ['NSCameraUsageDescription'],
      'plugins': ['image_picker_ios'],
    },
  ],
  'catalog': [
    {
      'key': 'NSCameraUsageDescription',
      'name': 'Camera',
      'description': 'Take photos and videos, scan codes.',
      'suggestion': 'This app uses the camera to scan codes.',
    },
    {
      'key': 'NSMicrophoneUsageDescription',
      'name': 'Microphone',
      'description': 'Record audio.',
      'suggestion': 'This app uses the microphone to record audio.',
    },
    {
      'key': 'NSContactsUsageDescription',
      'name': 'Contacts',
      'description': 'Read the address book.',
      'suggestion': 'This app reads your contacts.',
    },
  ],
};

Map<String, Object?> _plugins({bool fixed = false}) => {
  'type': 'plugin_status',
  'plugins': [
    {
      'name': 'fluttertoast',
      'version': '8.2.14',
      'kind': 'draft',
      'overridePath': 'xcross_overrides/fluttertoast/8.2.14',
      'edited': false,
      'problems': fixed
          ? <Object?>[]
          : [
              {
                'code': 'manifest_missing',
                'message': 'The draft lacks Classes/PrivacyInfo.xcprivacy.',
              },
            ],
      'action': fixed ? null : 'regenerate',
      'canRegenerate': true,
      'command': fixed ? null : ['plugin', 'shim', 'fluttertoast', '--force'],
    },
    {
      'name': 'path_provider_foundation',
      'version': '2.6.0',
      'kind': 'swiftpm',
      'overridePath': null,
      'edited': false,
      'problems': <Object?>[],
      'action': null,
      'canRegenerate': false,
      'command': null,
    },
  ],
};

final _capabilities = {
  'type': 'capabilities',
  'entitlements': {
    'path': 'ios/Runner/Runner.entitlements',
    'exists': false,
    'xcodeKnowsFile': false,
  },
  'capabilities': [
    {
      'id': 'push',
      'name': 'Push Notifications',
      'description': 'Receive remote notifications.',
      'key': 'aps-environment',
      'kind': 'choice',
      'choices': ['development', 'production'],
      'ascCapability': 'PUSH_NOTIFICATIONS',
      'inInfoPlist': false,
      'enabled': false,
      'value': null,
    },
    {
      'id': 'associated-domains',
      'name': 'Associated Domains',
      'description': 'Universal links.',
      'key': 'com.apple.developer.associated-domains',
      'kind': 'list',
      'choices': <String>[],
      'ascCapability': 'ASSOCIATED_DOMAINS',
      'inInfoPlist': false,
      'example': 'applinks:example.com',
      'enabled': true,
      'value': ['applinks:a.example.com'],
    },
  ],
  'unknownEntitlements': <String>[],
};

class _World {
  bool micFixed = false;
  bool pluginFixed = false;
  bool clean = false;
}

Future<(FakeLauncher, _World)> _pump(
  WidgetTester tester, {
  required String project,
  bool clean = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1600, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final world = _World()..clean = clean;
  final launcher = FakeLauncher(
    onStart: (process, arguments) async {
      final command = arguments.join(' ');
      if (command == 'permissions list --json') {
        process.out(
          _json(
            world.clean
                ? {
                    'type': 'permissions',
                    'permissions': <Object?>[],
                    'missing': <Object?>[],
                    'catalog': <Object?>[],
                  }
                : _permissions(micFixed: world.micFixed),
          ),
        );
      } else if (command == 'plugin status --json') {
        process.out(
          _json(
            world.clean
                ? {'type': 'plugin_status', 'plugins': <Object?>[]}
                : _plugins(fixed: world.pluginFixed),
          ),
        );
      } else if (command == 'capabilities list --json') {
        process.out(_json(_capabilities));
      } else if (command.startsWith('permissions set')) {
        world.micFixed = true;
        process.out(
          _json({
            'type': 'permissions_change',
            'action': 'set',
            'key': arguments[2],
            'changed': true,
            'backup': '.xcross/permission-backups/1/ios/Runner/Info.plist',
            'notes': <String>[],
          }),
        );
      } else if (command == 'plugin shim fluttertoast --force') {
        world.pluginFixed = true;
        process.out('✔ Kept the old files in .xcross/plugin-backups/1');
      } else if (command.startsWith('capabilities add')) {
        process.out(
          _json({
            'type': 'capabilities_change',
            'action': 'add',
            'id': arguments[2],
            'changed': true,
            'backup': null,
            'notes': ['The App ID needs the PUSH_NOTIFICATIONS capability.'],
          }),
        );
      }
      await process.exit(0);
    },
  );
  final settings = Settings()
    ..wizardDismissed = true
    ..projectPath = project;
  final jobs = JobCenter(
    launcher: launcher,
    invocation: () => const XcrossInvocation.binary(),
  );
  await tester.pumpWidget(
    StudioApp(
      services: StudioServices(
        host: HostPlatform.current(),
        launcher: launcher,
        settings: settings,
        jobs: jobs,
        logs: LogSession(jobs, notifyEvery: Duration.zero),
      ),
    ),
  );
  await settle(tester);
  return (launcher, world);
}

List<String> _commands(FakeLauncher launcher) => [
  for (final start in launcher.starts) start.arguments.join(' '),
];

void main() {
  late Directory project;
  setUp(() {
    project = Directory.systemTemp.createTempSync('studio-027-');
    File('${project.path}/pubspec.yaml').writeAsStringSync('name: demo\n');
    Directory('${project.path}/ios').createSync();
  });
  tearDown(() => project.deleteSync(recursive: true));

  testWidgets('AC-028-9 the count shows in the sidebar and the top bar', (
    tester,
  ) async {
    await _pump(tester, project: project.path);
    // A plugin problem, the missing camera key and the placeholder sentence.
    final badge = tester.widget<Container>(
      find.byKey(const ValueKey('sidebar-badge')),
    );
    expect(badge, isNotNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('sidebar-badge')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    expect(find.text('3 to do'), findsOneWidget);
  });

  testWidgets('AC-028-9 a project with nothing to do shows no count', (
    tester,
  ) async {
    await _pump(tester, project: project.path, clean: true);
    expect(find.byKey(const ValueKey('sidebar-badge')), findsNothing);
    expect(find.byKey(const ValueKey('todo-chip')), findsNothing);
  });

  testWidgets('AC-028-10 Overview lists the things to do with their buttons', (
    tester,
  ) async {
    await _pump(tester, project: project.path);
    expect(find.text('Needs your attention'), findsOneWidget);
    expect(
      find.textContaining('fluttertoast: the override has no privacy manifest'),
      findsOneWidget,
    );
    expect(find.textContaining('Add the camera permission'), findsOneWidget);
    expect(find.widgetWithText(XButton, 'Regenerate'), findsOneWidget);
  });

  testWidgets(
    'AC-028-11 Regenerate asks first, names the backup, then clears the item',
    (tester) async {
      final (launcher, _) = await _pump(tester, project: project.path);
      await tester.tap(find.widgetWithText(XButton, 'Regenerate'));
      await settle(tester);
      expect(find.textContaining('.xcross/plugin-backups/'), findsWidgets);
      expect(
        _commands(launcher),
        isNot(contains('plugin shim fluttertoast --force')),
        reason: 'nothing ran before the confirmation',
      );
      await tester.tap(find.widgetWithText(XButton, 'Regenerate').last);
      await settle(tester);
      expect(_commands(launcher), contains('plugin shim fluttertoast --force'));
      expect(
        find.byKey(
          const ValueKey('attention-plugin:fluttertoast:manifest_missing'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'AC-027-13 a missing permission is added with a starting sentence',
    (tester) async {
      final (launcher, _) = await _pump(tester, project: project.path);
      await tester.tap(
        find.widgetWithText(XButton, 'Add with a starting sentence'),
      );
      await settle(tester);
      expect(
        _commands(launcher),
        contains(
          'permissions set NSCameraUsageDescription '
          'This app uses the camera to scan codes. --json',
        ),
      );
    },
  );

  testWidgets('AC-027-14 the Permissions tab edits, adds and saves', (
    tester,
  ) async {
    final (launcher, world) = await _pump(tester, project: project.path);
    await go(tester, 'Project');
    await settle(tester);
    expect(find.text('Microphone'), findsWidgets);
    expect(find.text('Needs a real sentence'), findsOneWidget);

    // Change the sentence of a row and save it.
    final field = find.descendant(
      of: find.byKey(const ValueKey('permission-NSMicrophoneUsageDescription')),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'This app records voice messages.');
    await tester.pump();
    await tester.tap(find.widgetWithText(XButton, 'Save'));
    await settle(tester);
    expect(
      _commands(launcher),
      contains(
        'permissions set NSMicrophoneUsageDescription '
        'This app records voice messages. --json',
      ),
    );
    expect(world.micFixed, isTrue);
    expect(
      find.textContaining('Saved NSMicrophoneUsageDescription'),
      findsOneWidget,
    );
    expect(find.text('Set'), findsOneWidget);

    // Add one from the catalog: search, pick, edit nothing, add.
    await tester.tap(find.widgetWithText(XButton, 'Add permission'));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('permission-filter')),
      'contact',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('catalog-NSCameraUsageDescription')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('catalog-NSContactsUsageDescription')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('permission-add')));
    await settle(tester);
    expect(
      _commands(launcher),
      contains(
        'permissions set NSContactsUsageDescription '
        'This app reads your contacts. --json',
      ),
    );
  });

  testWidgets('AC-027-15 a permission is only removed after a confirmation', (
    tester,
  ) async {
    final (launcher, _) = await _pump(tester, project: project.path);
    await go(tester, 'Project');
    await settle(tester);
    await tester.tap(find.widgetWithText(XButton, 'Remove'));
    await settle(tester);
    expect(find.textContaining('.xcross/permission-backups/'), findsOneWidget);
    expect(
      _commands(launcher).where((c) => c.startsWith('permissions remove')),
      isEmpty,
    );
  });

  testWidgets(
    'AC-027-16 the Capabilities tab turns one on and shows what to know',
    (tester) async {
      final (launcher, _) = await _pump(tester, project: project.path);
      await go(tester, 'Project');
      await settle(tester);
      await tester.tap(find.text('Capabilities'));
      await settle(tester);
      expect(find.text('Push Notifications'), findsOneWidget);
      expect(find.text('Associated Domains'), findsOneWidget);
      expect(find.text('applinks:a.example.com'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('capability-push')),
          matching: find.byType(Switch),
        ),
      );
      await settle(tester);
      expect(_commands(launcher), contains('capabilities add push --json'));
      expect(
        find.textContaining(
          'The App ID needs the PUSH_NOTIFICATIONS capability.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'AC-028-12 the Plugins tab keeps showing every plugin and its badge',
    (tester) async {
      await _pump(tester, project: project.path);
      await go(tester, 'Project');
      await settle(tester);
      await tester.tap(find.text('Plugins'));
      await settle(tester);
      expect(find.byKey(const ValueKey('plugin-fluttertoast')), findsOneWidget);
      expect(find.text('Needs action'), findsOneWidget);
      expect(find.text('SwiftPM supported'), findsOneWidget);
    },
  );
}
