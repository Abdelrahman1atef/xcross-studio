// Feature 023: the App icon destination.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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

/// A 1×1 PNG; the page only displays the files.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYPgPAAEDAQAIicLsAAAAAElFTkSuQmCC',
);

Map<String, Object?> _slot(
  String role,
  String label,
  String idiom,
  num points,
  int scale,
  String status, {
  bool required = false,
}) => {
  'role': role,
  'label': label,
  'idiom': idiom,
  'points': points,
  'scale': scale,
  'pixels': (points * scale).round(),
  'file': 'Icon-App-${points}x$points@${scale}x.png',
  'status': status,
  'actual': status == 'wrong_size' ? '100x100' : null,
  'required': required,
};

Map<String, Object?> _check(String setPath, {bool ready = false}) => {
  'v': 1,
  'type': 'icons_check',
  'set': 'AppIcon',
  'path': setPath,
  'style': 'all-sizes',
  'source': 'Icon-App-1024x1024@1x.png',
  'slots': [
    _slot('notification', 'Notification', 'iphone', 20, 3, 'ok'),
    _slot('settings', 'Settings', 'iphone', 29, 3, 'ok'),
    _slot('spotlight', 'Spotlight', 'iphone', 40, 3, 'ok'),
    _slot(
      'home',
      'Home screen',
      'iphone',
      60,
      2,
      ready ? 'ok' : 'missing',
      required: true,
    ),
    _slot('appStore', 'App Store', 'ios-marketing', 1024, 1, 'ok'),
  ],
  'placement': {
    'background': '#FFFFFF',
    'box': [0.25, 0.25, 0.5, 0.5],
    'offset': [0.0, 0.0],
    'outsideMask': 0.0,
    'prerounded': false,
    'transparent': !ready,
    'fullBleed': false,
  },
  'issues': ready
      ? <Object?>[]
      : [
          {
            'code': 'icons.alpha',
            'severity': 'error',
            'message': 'Icon-App-1024x1024@1x.png has an alpha channel.',
            'hint': 'Export it without transparency.',
            'file': 'Icon-App-1024x1024@1x.png',
          },
          {
            'code': 'icons.missing',
            'severity': 'error',
            'message': 'Home screen 60 pt @2x (120 px) has no image.',
            'hint': 'Make the set with xcross icons generate.',
          },
        ],
  'errors': ready ? 0 : 2,
  'warnings': 0,
};

void main() {
  late Directory project;
  late String setPath;
  setUp(() {
    project = Directory.systemTemp.createTempSync('studio-023-');
    File(p.join(project.path, 'pubspec.yaml'))
        .writeAsStringSync('name: demo\nversion: 1.0.0+7\n');
    setPath = p.join(
      project.path,
      'ios',
      'Runner',
      'Assets.xcassets',
      'AppIcon.appiconset',
    );
    Directory(setPath).createSync(recursive: true);
    for (final name in [
      'Icon-App-20x20@3x.png',
      'Icon-App-29x29@3x.png',
      'Icon-App-40x40@3x.png',
      'Icon-App-1024x1024@1x.png',
    ]) {
      File(p.join(setPath, name)).writeAsBytesSync(_png);
    }
  });
  tearDown(() => project.deleteSync(recursive: true));

  Future<FakeLauncher> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final launcher = FakeLauncher(
      onStart: (process, arguments) async {
        final command = arguments.join(' ');
        if (command == XcrossCommands.iconsCheck().join(' ')) {
          process.out(jsonEncode(_check(setPath)));
        }
        if (arguments.length > 1 &&
            arguments[0] == 'icons' &&
            arguments[1] == 'generate') {
          process.out(
            jsonEncode({
              'v': 1,
              'type': 'icons_generate',
              'path': setPath,
              'written': List.generate(15, (i) => 'icon$i.png'),
              'backup': p.join(project.path, '.xcross', 'icon-backups', 'x'),
              'background': '#0A84FF',
              'padding': 12,
              'upscaled': false,
              'check': _check(setPath, ready: true),
            }),
          );
        }
        if (command.contains('--watch')) return;
        await process.exit(0);
      },
    );
    final settings = Settings()
      ..wizardDismissed = true
      ..projectPath = project.path;
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
    return launcher;
  }

  List<String> commands(FakeLauncher launcher) => [
    for (final start in launcher.starts) start.arguments.join(' '),
  ];

  testWidgets('AC-023-8 / AC-023-9 the page checks the set when opened and '
      'shows it as iOS does, every slot and the issues', (tester) async {
    final launcher = await pump(tester);
    expect(commands(launcher), isNot(contains('icons check --json')));

    await go(tester, 'App icon');
    await settle(tester);
    final check = launcher.starts.where(
      (s) => s.arguments.join(' ') == 'icons check --json',
    );
    expect(check, hasLength(1));
    expect(check.single.workingDirectory, project.path);

    expect(find.text('How iOS shows it'), findsOneWidget);
    for (final preview in [
      'App Store icon, 1024 px',
      'Home screen',
      'Home screen, dark',
      'Notification',
      'Settings',
      'Spotlight',
      'App Store',
    ]) {
      expect(find.text(preview), findsWidgets, reason: preview);
    }
    expect(find.text('Order paid'), findsOneWidget);
    expect(find.text('20 pt @3x · 60 px'), findsOneWidget);
    expect(find.text('1024 px'), findsOneWidget);
    expect(find.text('Missing'), findsOneWidget);
    expect(find.textContaining('[icons.alpha]'), findsOneWidget);
    expect(find.text('2 errors, 0 warnings'), findsOneWidget);
    expect(
      find.textContaining('logo 50% × 50% · centred · inside the corners'),
      findsOneWidget,
    );
  });

  testWidgets('AC-023-10 Make icon set writes through xcross icons generate '
      'and shows the backup', (tester) async {
    final launcher = await pump(tester);
    await go(tester, 'App icon');
    await settle(tester);

    await tester.tap(find.widgetWithText(XButton, 'Make icon set…'));
    await settle(tester, 2);
    expect(find.text('Make icon set'), findsOneWidget);

    final source = p.join(project.path, 'logo.png');
    File(source).writeAsBytesSync(_png);
    await tester.enterText(
      find.widgetWithText(TextField, 'Image (PNG)'),
      source,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester, 2);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Blue'));
    await settle(tester, 2);

    await tester.tap(find.widgetWithText(XButton, 'Write icon set'));
    await settle(tester);
    expect(
      commands(launcher),
      contains(
        XcrossCommands.iconsGenerate(
          source,
          background: '#0A84FF',
          padding: 12,
        ).join(' '),
      ),
    );
    expect(find.text('Wrote 15 icons'), findsOneWidget);
    expect(find.textContaining('The old set is in'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    // The panel closes after a successful write.
    expect(find.text('Make icon set'), findsNothing);
  });
}
