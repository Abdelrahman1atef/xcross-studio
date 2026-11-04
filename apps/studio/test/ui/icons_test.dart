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
        if (arguments.length > 1 &&
            arguments[0] == 'splash' &&
            arguments[1] == 'generate') {
          process.out(
            jsonEncode({
              'v': 1,
              'type': 'splash_generate',
              'path': project.path,
              'written': List.generate(6, (i) => 'splash$i.png'),
              'backup': p.join(project.path, '.xcross', 'icon-backups', 'y'),
              'issues': <Object?>[],
            }),
          );
        }
        // The preview server stays up until it is cancelled.
        if (command.contains('--watch') || command.contains('--serve')) return;
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

  /// The studio open on the App icon page, with the check done.
  Future<FakeLauncher> openStudio(WidgetTester tester) async {
    final launcher = await pump(tester);
    await go(tester, 'App icon');
    await settle(tester);
    await tester.tap(find.widgetWithText(XButton, 'Icon and splash studio…'));
    await settle(tester, 2);
    return launcher;
  }

  /// Ends the studio, so its preview process goes too.
  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester, 2);
  }

  /// What the preview process was sent, oldest first.
  List<Map<String, Object?>> designs(FakeLauncher launcher) => [
    for (final process in launcher.processes)
      for (final line in process.stdinLines)
        jsonDecode(line) as Map<String, Object?>,
  ];

  /// Lets the preview's debounce pass.
  Future<void> debounce(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 150));
    await settle(tester, 2);
  }

  Future<String> pickImage(WidgetTester tester) async {
    final source = p.join(project.path, 'logo.png');
    File(source).writeAsBytesSync(_png);
    await tester.enterText(find.widgetWithText(TextField, 'Image'), source);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester, 2);
    await debounce(tester);
    return source;
  }

  testWidgets('AC-024-17 / AC-024-18 the icon tab names every design choice '
      'and every target', (tester) async {
    await openStudio(tester);
    expect(find.text('Icon and splash studio'), findsOneWidget);
    for (final section in ['Source', 'Foreground', 'Background', 'More']) {
      expect(find.text(section), findsWidgets, reason: section);
    }
    for (final label in [
      'iOS',
      'Android',
      'Web',
      'macOS',
      'Notification',
      'watchOS',
      'tvOS',
      'Android TV',
      'Play Store banner',
    ]) {
      expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
    }
    for (final label in ['Clipart', 'Gradient', 'Mesh', 'Squircle']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.textContaining('Trim'), findsOneWidget);
    expect(find.textContaining('Themed'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('AC-024-17 / AC-024-20 a design goes to one preview process and '
      'writes through icons generate with its targets, saved in the project', (
    tester,
  ) async {
    final launcher = await openStudio(tester);
    final source = await pickImage(tester);

    expect(
      commands(launcher).where((c) => c.contains('icons preview --serve')),
      hasLength(1),
    );
    final sent = designs(launcher).single;
    expect(sent['source'], source);
    expect(sent['padding'], '15');

    await tester.tap(find.widgetWithText(XButton, 'Write to project'));
    await settle(tester);
    final written = commands(launcher)
        .lastWhere((command) => command.startsWith('icons generate'));
    expect(written, contains('--padding 15'));
    expect(written, contains('--targets ios'));
    expect(written, contains('--save-config'));
    expect(find.textContaining('Wrote 15 icon files'), findsOneWidget);
    expect(find.textContaining('Replaced files are in'), findsOneWidget);
    // Writing into the project checks it again.
    expect(
      commands(launcher).where((c) => c == 'icons check --json'),
      hasLength(2),
    );
    await closeApp(tester);
  });

  testWidgets('AC-024-20 the saved design comes back when the studio opens', (
    tester,
  ) async {
    File(p.join(project.path, 'xcross_assets.json')).writeAsStringSync(
      jsonEncode({
        'icons': {
          'source': 'logo.png',
          'padding': '10,14,18,14',
          'background': '#0A84FF',
          'targets': 'ios,android,tvos',
        },
      }),
    );
    File(p.join(project.path, 'logo.png')).writeAsBytesSync(_png);
    final launcher = await openStudio(tester);
    await debounce(tester);

    final sent = designs(launcher).single;
    expect(sent['source'], p.join(project.path, 'logo.png'));
    expect(sent['padding'], '10,14,18,14');
    expect(sent['background'], '#0A84FF');
    FilterChip chip(String label) =>
        tester.widget<FilterChip>(find.widgetWithText(FilterChip, label));
    expect(chip('iOS').selected, isTrue);
    expect(chip('Android').selected, isTrue);
    expect(chip('tvOS').selected, isTrue);
    expect(chip('Web').selected, isFalse);
    await closeApp(tester);
  });

  testWidgets('AC-024-15 the default targets are the folders the project has', (
    tester,
  ) async {
    Directory(p.join(project.path, 'android')).createSync();
    await openStudio(tester);
    FilterChip chip(String label) =>
        tester.widget<FilterChip>(find.widgetWithText(FilterChip, label));
    expect(chip('iOS').selected, isTrue);
    expect(chip('Android').selected, isTrue);
    expect(chip('Web').selected, isFalse);
    expect(chip('macOS').selected, isFalse);
    await closeApp(tester);
  });

  testWidgets('AC-024-19 the splash tab previews on phones and writes through '
      'splash generate', (tester) async {
    final launcher = await openStudio(tester);
    await tester.tap(find.text('Splash screen'));
    await settle(tester, 2);
    expect(find.text('Margin 0 pt'), findsOneWidget);

    final logo = p.join(project.path, 'splash.png');
    File(logo).writeAsBytesSync(_png);
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Logo (PNG with a transparent background)',
      ),
      logo,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester, 2);
    await debounce(tester);
    expect(find.text('iPhone'), findsWidgets);
    expect(find.text('Android'), findsWidgets);
    expect(find.text('Android 12+ (safe circle)'), findsOneWidget);

    final sent = designs(launcher).lastWhere((d) => d['kind'] == 'splash');
    expect(sent['source'], logo);

    await tester.tap(find.widgetWithText(XButton, 'Write splash to project'));
    await settle(tester);
    final written = commands(launcher)
        .lastWhere((command) => command.startsWith('splash generate'));
    expect(written, contains('--logo-width 120'));
    expect(written, contains('--platforms ios,android'));
    expect(written, contains('--save-config'));
    expect(find.textContaining('Wrote 6 splash files'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('AC-024-16 without a project the studio exports but does not '
      'write', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final launcher = FakeLauncher(
      onStart: (process, arguments) async {
        if (!arguments.join(' ').contains('--serve')) await process.exit(0);
      },
    );
    final settings = Settings()..wizardDismissed = true;
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
    await go(tester, 'App icon');
    await settle(tester);
    expect(find.text('Open a Flutter project'), findsOneWidget);
    await tester.tap(find.widgetWithText(XButton, 'Icon and splash studio…'));
    await settle(tester, 2);
    await pickImage(tester);
    final write = tester.widget<XButton>(
      find.widgetWithText(XButton, 'Write to project'),
    );
    expect(write.onPressed, isNull);
    expect(write.disabledReason, 'Open a Flutter project first');
    final export = tester.widget<XButton>(
      find.widgetWithText(XButton, 'Export folder…'),
    );
    expect(export.onPressed, isNotNull);
    await closeApp(tester);
  });

  test('a command given input before it has started still gets it', () async {
    late FakeProcess started;
    final launcher = FakeLauncher(
      onStart: (process, arguments) => started = process,
    );
    final jobs = JobCenter(
      launcher: launcher,
      invocation: () => const XcrossInvocation.binary(),
    );
    final job = jobs.background('Icon preview', const ['icons', 'preview']);
    job.send('first');
    await Future<void>.delayed(Duration.zero);
    job.send('second');
    expect(started.stdinLines, ['first', 'second']);
    await job.cancel();
    await job.done;
  });
}
