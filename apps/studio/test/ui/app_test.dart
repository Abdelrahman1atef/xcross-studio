import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcross_studio/app/app.dart';
import 'package:xcross_studio/app/services.dart';
import 'package:xcross_studio/design_system/design_system.dart';
import 'package:xcross_studio/src/cli/xcross_commands.dart';
import 'package:xcross_studio/src/host/host_platform.dart';
import 'package:xcross_studio/src/product.dart';
import 'package:xcross_studio/src/state/job.dart';
import 'package:xcross_studio/src/state/log_session.dart';
import 'package:xcross_studio/src/state/settings.dart';
import 'package:xcross_studio/src/state/signing_accounts.dart';

import '../support/fake_launcher.dart';

const _appInfo =
    '{"v":1,"type":"appinfo","bundleId":"com.example.app","name":"Demo",'
    '"version":"1.0","build":"3","executable":"Runner","signer":"development",'
    '"teamId":"TEAM123456","entitlements":{"aps-environment":"development"},'
    '"push":"development","associatedDomains":[]}';

const _device =
    '{"v":1,"type":"device","udid":"00008020-001A2B3C4D5E6F70",'
    '"name":"Test Phone","osVersion":"16.7.16","connection":"usb"}';

String check(String section, String name, String status, String message) =>
    '{"v":1,"type":"check","section":"$section","name":"$name",'
    '"status":"$status","message":"$message","path":null}';

/// Doctor output of a PC without Swift and with credentials.
final failingDoctor = [
  check('Flutter project', 'Flutter SDK', 'success', 'Found'),
  check('iOS toolchain', 'swift', 'failure', 'Not found.'),
  check('iOS toolchain', 'Darwin SDK', 'failure', 'Missing.'),
  check('Deployment', 'Authentication', 'success', 'Apple ID saved'),
  check('Deployment', 'Device service', 'success', 'Reachable'),
];

/// Lets the fake processes finish and pumps frames (spinners never
/// "settle", and stream shutdown needs real async turns).
Future<void> settle(WidgetTester tester, [int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class Studio {
  Studio(this.launcher, this.services);

  final FakeLauncher launcher;
  final StudioServices services;

  List<String> get commands => [
    for (final s in launcher.starts) s.arguments.join(' '),
  ];
}

Future<Studio> pumpStudio(
  WidgetTester tester, {
  List<String> doctor = const [],
  Size size = const Size(1500, 1000),
  bool startupChecks = true,
  Settings? settings,
  String? authStatus,
  SigningAccounts? signingAccounts,
  Map<String, String> accountDetails = const {},
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final launcher = FakeLauncher(
    onStart: (process, arguments) async {
      final command = arguments.join(' ');
      if (arguments.first == 'devices') process.out(_device);
      if (command.startsWith('app info')) process.out(_appInfo);
      if (command == '--version') process.out('xcross 9.9.9-test');
      if (command == 'flutter doctor') doctor.forEach(process.out);
      if (command == 'auth status --json' && authStatus != null) {
        process.out(authStatus);
      }
      if (command.startsWith('auth account --json')) {
        // Feature 031: the reply is scripted per Key ID.
        final keyId = arguments[arguments.indexOf('--key-id') + 1];
        if (accountDetails[keyId] case final reply?) process.out(reply);
      }
      await process.exit(0);
    },
  );
  final config = (settings ?? Settings())..logApp ??= 'com.example.app';
  final jobs = JobCenter(
    launcher: launcher,
    invocation: () => const XcrossInvocation.binary(),
  );
  final services = StudioServices(
    host: HostPlatform.current(),
    launcher: launcher,
    settings: config,
    jobs: jobs,
    logs: LogSession(jobs, notifyEvery: Duration.zero),
    signingAccounts: signingAccounts,
  );
  await tester.pumpWidget(
    StudioApp(services: services, startupChecks: startupChecks),
  );
  await settle(tester);
  return Studio(launcher, services);
}

Future<void> go(WidgetTester tester, String destination) async {
  await tester.tap(
    find.descendant(
      of: find.byType(XSidebarItem),
      matching: find.text(destination),
    ),
  );
  await settle(tester, 3);
}

void main() {
  testWidgets('AC-008-9 AC-013-1 every destination opens from the sidebar', (
    tester,
  ) async {
    await pumpStudio(tester);
    // Feature 022 added Release and Archives; 023 App icon.
    expect(find.byType(XSidebarItem), findsNWidgets(10));
    expect(find.text('Readiness'), findsOneWidget);
    for (final (label, marker) in [
      ('Build & Run', 'Options'),
      ('Devices', 'Install an app (.ipa)'),
      ('Signing', 'Sign in'),
      ('Logs & Debug', 'Device log'),
      ('Project', 'No project open'),
      ('App icon', 'Open a Flutter project'),
      ('Release', 'Open a Flutter project'),
      ('Archives', 'Open a Flutter project'),
      ('Settings', 'xcross command-line tool'),
      ('Overview', 'Readiness'),
    ]) {
      await go(tester, label);
      expect(find.text(marker), findsWidgets, reason: label);
    }
  });

  testWidgets('AC-008-1 Devices lists the iPhone from devices --json', (
    tester,
  ) async {
    final studio = await pumpStudio(tester);
    await go(tester, 'Devices');
    expect(studio.commands, contains('devices --json'));
    expect(find.text('Test Phone'), findsWidgets);
    expect(find.textContaining('iOS 16.7.16'), findsWidgets);
    expect(find.textContaining('release and profile only'), findsOneWidget);
    expect(find.text('iPhone: Test Phone'), findsOneWidget, reason: 'top bar');
  });

  testWidgets('AC-008-7 app info shows push and associated-domain badges', (
    tester,
  ) async {
    await pumpStudio(tester);
    await go(tester, 'Logs & Debug');
    await tester.tap(find.text('Read installed app info'));
    await settle(tester);
    expect(find.textContaining('Demo 1.0'), findsOneWidget);
    expect(
      find.textContaining('Push entitlement  development'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_circle), findsWidgets);
    expect(find.textContaining('Associated domains  none'), findsOneWidget);
  });

  testWidgets('FR-001 "Run from source" shows the repository field', (
    tester,
  ) async {
    await pumpStudio(tester);
    await go(tester, 'Settings');
    expect(find.text('XCross Studio repository folder'), findsNothing);
    await tester.tap(find.text('Run from source'));
    await settle(tester, 2);
    expect(find.text('XCross Studio repository folder'), findsOneWidget);
    await tester.tap(find.text('Installed xcross'));
    await settle(tester, 2);
    expect(find.text('xcross executable'), findsOneWidget);
  });

  testWidgets('AC-013-2 Ctrl+, Ctrl+L and the Ctrl+K quick commands', (
    tester,
  ) async {
    await pumpStudio(tester);
    Future<void> chord(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settle(tester, 2);
    }

    await chord(LogicalKeyboardKey.comma);
    expect(find.text('xcross command-line tool'), findsOneWidget);
    await chord(LogicalKeyboardKey.keyL);
    expect(find.text('Device log'), findsOneWidget);
    await chord(LogicalKeyboardKey.keyK);
    expect(find.text('Type a command…'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'devices');
    await settle(tester, 2);
    await tester.tap(find.text('Go to Devices'));
    await settle(tester, 4);
    expect(find.text('Install an app (.ipa)'), findsOneWidget);
  });

  testWidgets('AC-013-3 narrow windows use an icon rail', (tester) async {
    await pumpStudio(tester, size: const Size(900, 900));
    final items = tester.widgetList<XSidebarItem>(find.byType(XSidebarItem));
    expect(items, hasLength(10));
    expect(items.every((item) => item.compact), isTrue);
    expect(
      find.descendant(
        of: find.byType(XSidebarItem),
        matching: find.text('Build & Run'),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'AC-013-4 status bar and readiness cards come from doctor checks',
    (tester) async {
      final studio = await pumpStudio(
        tester,
        doctor: failingDoctor,
        settings: Settings()..wizardDismissed = true,
      );
      expect(studio.commands, containsAll(['flutter doctor', '--version']));
      expect(find.text('Toolchain failed'), findsOneWidget);
      expect(find.text('Signing ready'), findsOneWidget);
      expect(find.text('xcross 9.9.9-test'), findsOneWidget);
      expect(find.textContaining('swift: Not found.'), findsWidgets);
      expect(find.text('Fix Setup'), findsOneWidget, reason: 'next step');
    },
  );

  testWidgets(
    'AC-013-5 the wizard opens while setup fails and remembers Close',
    (tester) async {
      final studio = await pumpStudio(tester, doctor: failingDoctor);
      expect(find.text('Set up XCross Studio'), findsOneWidget);
      expect(find.text('1. Environment'), findsWidgets);
      for (final step in [
        'Darwin SDK',
        'Authentication',
        'Device (optional)',
      ]) {
        expect(find.textContaining(step), findsWidgets, reason: step);
      }
      expect(find.text('Copy command'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Show details'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await settle(tester, 10);
      expect(find.text('Set up XCross Studio'), findsNothing);
      expect(studio.services.settings.wizardDismissed, isTrue);
    },
  );

  testWidgets('AC-013-5 a dismissed wizard does not open again', (
    tester,
  ) async {
    await pumpStudio(
      tester,
      doctor: failingDoctor,
      settings: Settings()..wizardDismissed = true,
    );
    expect(find.text('Set up XCross Studio'), findsNothing);
  });

  testWidgets(
    'AC-013-6 Overview without a project offers Open Flutter Project',
    (tester) async {
      await pumpStudio(tester);
      expect(find.text('No Flutter project open'), findsOneWidget);
      expect(find.text('Open Flutter Project'), findsOneWidget);
      expect(find.text('Project: No project'), findsOneWidget);
    },
  );

  testWidgets('AC-013-7 sign out needs a destructive confirmation', (
    tester,
  ) async {
    final studio = await pumpStudio(tester, size: const Size(1500, 2400));
    await go(tester, 'Signing');
    final signOut = find.text('Sign out / clear credentials');
    await tester.tap(signOut);
    await settle(tester, 2);
    expect(find.text('Sign out and clear credentials?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester, 2);
    expect(studio.commands, isNot(contains('auth clean')));
    await tester.tap(signOut);
    await settle(tester, 2);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
    await settle(tester);
    expect(studio.commands, contains('auth clean'));
  });

  testWidgets(
    'AC-TK-1 Signing offers only App Store Connect team-key sign-in',
    (tester) async {
      await pumpStudio(tester);
      await go(tester, 'Signing');
      expect(
        find.text('Sign in with an App Store Connect team key'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, 'Issuer ID'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Apple ID (email)'), findsNothing);
      expect(find.textContaining('anisette'), findsNothing);
    },
  );

  test('AC-TK-2 Studio never builds an Apple ID sign-in command', () {
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final code = file
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('--apple-id')), reason: file.path);
      expect(code, isNot(contains('--anisette-url')), reason: file.path);
      expect(code, isNot(contains('authAppleId')), reason: file.path);
    }
  });

  testWidgets('AC-013-9 the console dock shows the newest command', (
    tester,
  ) async {
    await pumpStudio(tester);
    expect(find.text('Console'), findsOneWidget);
    expect(find.text('Collapse console'), findsNothing);
    await tester.tap(find.byTooltip('Collapse console'));
    await settle(tester, 2);
    expect(find.byTooltip('Open console'), findsOneWidget);
  });

  test('AC-008-8 the GUI never imports the xcross packages', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final package in [
      'xcross:',
      'studio_ext:',
      'cli_kit:',
      'dart_mobile_device:',
      'apple_developer_kit:',
    ]) {
      expect(pubspec, isNot(contains('  $package')), reason: package);
    }
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(matches(RegExp(r"import 'package:(xcross|studio_ext|cli_kit)/"))),
        reason: file.path,
      );
    }
  });

  test('AC-013-10 design-system components never touch the CLI or state', () {
    for (final file in Directory(
      'lib/design_system',
    ).listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      expect(source, isNot(contains('src/cli/')), reason: file.path);
      expect(source, isNot(contains('src/state/')), reason: file.path);
      expect(source, isNot(contains('dart:io')), reason: file.path);
    }
  });

  testWidgets('AC-RB-1 the app title and the window header show productName', (
    tester,
  ) async {
    await pumpStudio(tester);
    await settle(tester);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, productName);
    expect(find.text(productName), findsWidgets);
    expect(productName, 'XCross Studio', reason: 'default until release day');
  });

  test('AC-RB-2 no user-visible product name is hard-coded in lib/', () {
    // Allowed: comments, the constant's default, and the settings folder name
    // (renaming the product must not orphan settings).
    const allowed = {'product.dart', 'host_platform.dart'};
    final literal = RegExp(r'''['"][^'"\n]*XCross Studio[^'"\n]*['"]''');
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (allowed.contains(file.uri.pathSegments.last)) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].trimLeft();
        if (code.startsWith('//')) continue;
        if (literal.hasMatch(code)) offenders.add('${file.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty);
  });
}
