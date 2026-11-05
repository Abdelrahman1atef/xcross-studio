// Feature 023: the App icon destination.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:xcross_studio/app/app.dart';
import 'package:xcross_studio/app/services.dart';
import 'package:xcross_studio/design_system/design_system.dart';
import 'package:xcross_studio/features/icons/device_gallery.dart';
import 'package:xcross_studio/features/icons/studio_model.dart';
import 'package:xcross_studio/src/cli/xcross_commands.dart';
import 'package:xcross_studio/src/host/host_platform.dart';
import 'package:xcross_studio/src/state/job.dart';
import 'package:xcross_studio/src/state/log_session.dart';
import 'package:xcross_studio/src/state/settings.dart';

import '../support/fake_launcher.dart';
import 'app_test.dart' show settle, go;

const _withSplash = <String, Object?>{
  'v': 1,
  'type': 'splash_check',
  'ios': {'background': '#123456', 'logo': 'LaunchImage'},
  'android': null,
  'issues': <Object?>[],
  'errors': 0,
};

const _noSplash = <String, Object?>{
  'v': 1,
  'type': 'splash_check',
  'ios': null,
  'android': null,
  'issues': <Object?>[],
  'errors': 0,
};

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

/// The number field beside the slider named [label].
TextField fieldOf(WidgetTester tester, String label) {
  final row = find
      .ancestor(of: find.text(label), matching: find.byType(Row))
      .first;
  return tester.widget<TextField>(
    find.descendant(of: row, matching: find.byType(TextField)),
  );
}

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

  Future<FakeLauncher> pump(
    WidgetTester tester, {
    bool withProject = true,
    Map<String, Object?> splashReport = _withSplash,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1600, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final launcher = FakeLauncher(
      onStart: (process, arguments) async {
        final command = arguments.join(' ');
        if (command == XcrossCommands.iconsCheck().join(' ')) {
          process.out(jsonEncode(_check(setPath)));
        }
        if (command == XcrossCommands.splashCheck().join(' ')) {
          process.out(jsonEncode(splashReport));
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
      ..projectPath = withProject ? project.path : null;
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

  /// What the preview processes were sent, oldest first.
  List<Map<String, Object?>> allDesigns(FakeLauncher launcher) => [
    for (final process in launcher.processes)
      for (final line in process.stdinLines)
        jsonDecode(line) as Map<String, Object?>,
  ];

  /// The icon's designs: the splash has its own process and follows the icon's
  /// image from the start (AC-026-14).
  List<Map<String, Object?>> designs(FakeLauncher launcher) => [
    for (final design in allDesigns(launcher))
      if (design['kind'] != 'splash') design,
  ];

  List<Map<String, Object?>> splashDesigns(FakeLauncher launcher) => [
    for (final design in allDesigns(launcher))
      if (design['kind'] == 'splash') design,
  ];

  /// Answers the preview processes, then lets the debounce pass.
  Future<void> debounce(WidgetTester tester, FakeLauncher launcher) async {
    await settle(tester, 2);
    for (final (index, start) in launcher.starts.indexed) {
      final process = launcher.processes[index];
      if (start.arguments.contains('--serve') &&
          process.stdinLines.isNotEmpty) {
        final last =
            jsonDecode(process.stdinLines.last) as Map<String, Object?>;
        process.out(
          jsonEncode({
            'v': 1,
            'type': 'icons_preview',
            'seq': last['seq'],
            'paths': <String, String>{},
          }),
        );
      }
    }
    await settle(tester, 2);
    await tester.pump(const Duration(milliseconds: 150));
    await settle(tester, 2);
  }

  Future<String> pickImage(WidgetTester tester, FakeLauncher launcher) async {
    final source = p.join(project.path, 'logo.png');
    File(source).writeAsBytesSync(_png);
    final field = find.widgetWithText(TextField, 'Image');
    if (field.evaluate().isEmpty) {
      await tester.tap(find.text('Image').first);
      await settle(tester, 2);
    }
    await tester.enterText(field, source);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await debounce(tester, launcher);
    return source;
  }

  testWidgets(
    'AC-024-17 the studio opens on a preview of the project icon, and '
    'writing it does not replace its own source',
    (tester) async {
      final launcher = await openStudio(tester);
      await debounce(tester, launcher);
      final first = designs(launcher).first;
      final icon = p.join(setPath, 'Icon-App-1024x1024@1x.png');
      expect(first['source'], icon);
      expect(first['padding'], '0');

      await tester.tap(find.widgetWithText(XButton, 'Write to project'));
      await settle(tester);
      final kept = p.join(
        project.path,
        '.xcross',
        'assets',
        'Icon-App-1024x1024@1x.png',
      );
      expect(File(kept).existsSync(), isTrue);
      final written = launcher.starts.lastWhere(
        (start) => start.arguments.take(2).join(' ') == 'icons generate',
      );
      expect(written.arguments[2], kept);
      await closeApp(tester);
    },
  );

  group('AC-026-14 the studio shows both', () {
    testWidgets('the icon tab shows the splash, the splash tab the icon', (
      tester,
    ) async {
      final launcher = await openStudio(tester);
      await debounce(tester, launcher);
      expect(find.byKey(const ValueKey('icon-tab-splash')), findsOneWidget);
      await tester.tap(find.text('Splash screen').first);
      await settle(tester, 2);
      expect(find.byKey(const ValueKey('splash-tab-icon')), findsOneWidget);
      await closeApp(tester);
    });

    testWidgets("a new splash starts from the icon's image", (tester) async {
      final launcher = await openStudio(tester);
      await debounce(tester, launcher);
      await debounce(tester, launcher);
      final icon = p.join(setPath, 'Icon-App-1024x1024@1x.png');
      expect(splashDesigns(launcher).last['source'], icon);
      await tester.tap(find.text('Splash screen').first);
      await settle(tester, 2);
      expect(find.textContaining("This is the icon's image"), findsOneWidget);
      await closeApp(tester);
    });

    testWidgets('choosing a logo stops following the icon', (tester) async {
      final launcher = await openStudio(tester);
      await debounce(tester, launcher);
      await tester.tap(find.text('Splash screen').first);
      await settle(tester, 2);
      final mine = p.join(project.path, 'mine.png');
      File(mine).writeAsBytesSync(_png);
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Logo (PNG with a transparent background)',
        ),
        mine,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await debounce(tester, launcher);
      await debounce(tester, launcher);
      expect(find.textContaining("This is the icon's image"), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<int>),
          matching: find.text('App icon'),
        ),
      );
      await settle(tester, 2);
      final other = await pickImage(tester, launcher);
      await debounce(tester, launcher);
      expect(designs(launcher).last['source'], other);
      expect(splashDesigns(launcher).last['source'], mine);
      await closeApp(tester);
    });

    testWidgets('the All screens tab holds the gallery and every size', (
      tester,
    ) async {
      final launcher = await openStudio(tester);
      await debounce(tester, launcher);
      await tester.tap(find.text('All screens'));
      await settle(tester, 2);
      expect(find.byType(DeviceGallery), findsOneWidget);
      expect(find.text('Every icon size'), findsOneWidget);
      await closeApp(tester);
    });
  });

  group('AC-026-18 what only the CLI had', () {
    testWidgets('a splash zip, every target and a badge image', (tester) async {
      final launcher = await openStudio(tester);
      await debounce(tester, launcher);
      expect(find.widgetWithText(ActionChip, 'Every target'), findsOneWidget);
      await tester.ensureVisible(
        find.widgetWithText(ActionChip, 'Every target'),
      );
      await tester.tap(find.widgetWithText(ActionChip, 'Every target'));
      await settle(tester, 2);
      for (final target in const ['Web', 'macOS', 'watchOS', 'tvOS']) {
        final chip = tester.widget<FilterChip>(
          find.widgetWithText(FilterChip, target),
        );
        expect(chip.selected, isTrue, reason: target);
      }

      final badge = p.join(project.path, 'badge.png');
      File(badge).writeAsBytesSync(_png);
      await tester.enterText(
        find.widgetWithText(TextField, 'Badge image (optional)'),
        badge,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await debounce(tester, launcher);
      expect(designs(launcher).last['badge-image'], badge);

      await tester.tap(find.text('Splash screen'));
      await settle(tester, 2);
      expect(find.widgetWithText(XButton, 'Export zip…'), findsOneWidget);
      await closeApp(tester);
    });

    testWidgets('sliders reach the whole range, and padding takes decimals', (
      tester,
    ) async {
      final launcher = await openStudio(tester);
      await debounce(tester, launcher);
      await tester.tap(find.text('Splash screen'));
      await settle(tester, 2);
      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      final width = sliders.firstWhere((slider) => slider.max == 1024);
      expect(width.min, 16);
      final padding = sliders.firstWhere((slider) => slider.max == 45);
      expect(padding.divisions, 90, reason: 'half a percent at a time');
      await closeApp(tester);
    });
  });

  group('AC-026-19 AC-026-20 AC-026-21 the splash controls', () {
    testWidgets('a size for each kind of device reaches the CLI', (
      tester,
    ) async {
      final launcher = await openStudio(tester);
      await debounce(tester, launcher);
      await tester.tap(find.text('Splash screen'));
      await settle(tester, 2);
      await tester.tap(
        find.descendant(
          of: find
              .ancestor(
                of: find.text('A different size on each kind of device'),
                matching: find.byType(Row),
              )
              .first,
          matching: find.byType(Switch),
        ),
      );
      await debounce(tester, launcher);
      final sent = splashDesigns(launcher).last;
      expect(sent['ipad-logo-width'], '120');
      expect(sent['android-logo-width'], '120');
      expect(sent['android12-icon-width'], '120');
      expect(fieldOf(tester, 'iPad').controller!.text, '120');
      await closeApp(tester);
    });

    testWidgets('without them, nothing extra is sent', (tester) async {
      final launcher = await openStudio(tester);
      await debounce(tester, launcher);
      final sent = splashDesigns(launcher).last;
      expect(sent.containsKey('ipad-logo-width'), isFalse);
      expect(sent.containsKey('android12-icon-background'), isFalse);
      expect(sent.containsKey('branding-width'), isFalse);
      await closeApp(tester);
    });

    testWidgets('a platform turned off asks for fewer images', (tester) async {
      final launcher = await openStudio(tester);
      await debounce(tester, launcher);
      await tester.tap(find.text('Splash screen'));
      await settle(tester, 2);
      await tester.ensureVisible(find.widgetWithText(FilterChip, 'Android'));
      await tester.tap(find.widgetWithText(FilterChip, 'Android'));
      await debounce(tester, launcher);
      final variants = splashDesigns(launcher).last['variants']! as List;
      expect(variants, contains('logo'));
      expect(variants, isNot(contains('android12')));
      await closeApp(tester);
    });
  });

  group('every splash control has an effect', () {
    Future<FakeLauncher> openSplash(WidgetTester tester) async {
      final launcher = await openStudio(tester);
      await debounce(tester, launcher);
      await tester.tap(find.text('Splash screen'));
      await settle(tester, 2);
      return launcher;
    }

    Future<void> slide(WidgetTester tester, String label, double to) async {
      final row = find
          .ancestor(of: find.text(label), matching: find.byType(Row))
          .first;
      final slider = tester.widget<Slider>(
        find.descendant(of: row, matching: find.byType(Slider)),
      );
      slider.onChanged!(to);
      await tester.pump();
    }

    testWidgets('AC-026-29 margin has no one-value control, and each side '
        'reaches the CLI', (tester) async {
      final launcher = await openSplash(tester);
      expect(find.byTooltip('Set each side of Margin'), findsNothing);
      await slide(tester, 'Top', 80);
      await debounce(tester, launcher);
      expect(splashDesigns(launcher).last['margin'], '80,0,0,0');
      await closeApp(tester);
    });

    testWidgets('AC-026-28 padding reaches the CLI, by half percents', (
      tester,
    ) async {
      final launcher = await openSplash(tester);
      await slide(tester, 'Padding', 12.5);
      await debounce(tester, launcher);
      expect(splashDesigns(launcher).last['padding'], '12.5');
      await closeApp(tester);
    });

    testWidgets('a number typed beside a slider reaches the CLI, kept in its '
        'range and on a step', (tester) async {
      final launcher = await openSplash(tester);
      Future<void> type(String label, String text) async {
        final field = find.descendant(
          of: find
              .ancestor(of: find.text(label), matching: find.byType(Row))
              .first,
          matching: find.byType(TextField),
        );
        await tester.enterText(field, text);
        await tester.pump();
      }

      await type('Padding', '12.3');
      await debounce(tester, launcher);
      expect(splashDesigns(launcher).last['padding'], '12.5');
      // 99 is more than a side can have; 45 is the most.
      await type('Padding', '99');
      await debounce(tester, launcher);
      expect(splashDesigns(launcher).last['padding'], '45');
      // A comma is a decimal point in some keyboards.
      await type('Padding', '7,5');
      await debounce(tester, launcher);
      expect(splashDesigns(launcher).last['padding'], '7.5');
      await type('Top', '120');
      await debounce(tester, launcher);
      expect(splashDesigns(launcher).last['margin'], '120,0,0,0');
      await closeApp(tester);
    });

    testWidgets('the arrow keys in the number field change it one step', (
      tester,
    ) async {
      final launcher = await openSplash(tester);
      Finder field(String label) => find.descendant(
        of: find
            .ancestor(of: find.text(label), matching: find.byType(Row))
            .first,
        matching: find.byType(TextField),
      );
      await tester.tap(field('Padding'));
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
      }
      expect(fieldOf(tester, 'Padding').controller!.text, '1.5');
      await debounce(tester, launcher);
      expect(splashDesigns(launcher).last['padding'], '1.5');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(fieldOf(tester, 'Padding').controller!.text, '1');
      // Down at the minimum stays at the minimum.
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }
      expect(fieldOf(tester, 'Padding').controller!.text, '0');
      // Page Up is ten steps.
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pump();
      expect(fieldOf(tester, 'Padding').controller!.text, '5');
      await closeApp(tester);
    });

    testWidgets('AC-026-30 Android 12 has a slider as wide as its canvas, '
        'starting where the logo already is', (tester) async {
      final launcher = await openSplash(tester);
      await tester.tap(
        find.descendant(
          of: find
              .ancestor(
                of: find.text('A different size on each kind of device'),
                matching: find.byType(Row),
              )
              .first,
          matching: find.byType(Switch),
        ),
      );
      await debounce(tester, launcher);
      final row = find
          .ancestor(of: find.text('Android 12+'), matching: find.byType(Row))
          .first;
      final slider = tester.widget<Slider>(
        find.descendant(of: row, matching: find.byType(Slider)),
      );
      expect(slider.max, 288);
      await slide(tester, 'Android 12+', 250);
      await debounce(tester, launcher);
      expect(splashDesigns(launcher).last['android12-icon-width'], '250');
      await closeApp(tester);
    });

    testWidgets('AC-026-31 an iPad size shows on an iPad', (tester) async {
      final launcher = await openSplash(tester);
      expect(find.byKey(const ValueKey('splash-tab-iPad')), findsNothing);
      await tester.tap(
        find.descendant(
          of: find
              .ancestor(
                of: find.text('A different size on each kind of device'),
                matching: find.byType(Row),
              )
              .first,
          matching: find.byType(Switch),
        ),
      );
      await debounce(tester, launcher);
      expect(find.byKey(const ValueKey('splash-tab-iPad')), findsOneWidget);
      await closeApp(tester);
    });

    testWidgets('AC-026-30 a size saved past the canvas comes back on it', (
      tester,
    ) async {
      File(p.join(project.path, 'logo.png')).writeAsBytesSync(_png);
      File(p.join(project.path, 'xcross_assets.json')).writeAsStringSync(
        jsonEncode({
          'splash': {'source': 'logo.png', 'android12-icon-width': '497'},
        }),
      );
      final launcher = await openStudio(tester);
      await debounce(tester, launcher);
      expect(splashDesigns(launcher).last['android12-icon-width'], '288');
      await closeApp(tester);
    });
  });

  testWidgets('AC-026-23 the studio restores the new options', (tester) async {
    File(p.join(project.path, 'logo.png')).writeAsBytesSync(_png);
    File(p.join(project.path, 'xcross_assets.json')).writeAsStringSync(
      jsonEncode({
        'splash': {
          'source': 'logo.png',
          'ipad-logo-width': '200',
          'android-logo-width': '60',
          'android12-icon-width': '100',
          'android12-icon-background': '#112233',
          'dark-android12-icon-background': '#445566',
          'branding': 'logo.png',
          'branding-width': '90',
          'branding-bottom': '40',
        },
      }),
    );
    final launcher = await openStudio(tester);
    await debounce(tester, launcher);
    final sent = splashDesigns(launcher).last;
    expect(sent['ipad-logo-width'], '200');
    expect(sent['android-logo-width'], '60');
    expect(sent['android12-icon-width'], '100');
    expect(sent['android12-icon-background'], '#112233');
    expect(sent['dark-android12-icon-background'], '#445566');
    expect(sent['branding-width'], '90');
    expect(sent['branding-bottom'], '40');
    await closeApp(tester);
  });

  group('AC-026-15 one action for both', () {
    testWidgets('writes the icon and the splash, and reports each', (
      tester,
    ) async {
      final launcher = await openStudio(tester);
      await debounce(tester, launcher);
      await debounce(tester, launcher);
      await tester.tap(find.text('All screens'));
      await settle(tester, 2);
      await tester.tap(
        find.widgetWithText(XButton, 'Write icon and splash to project'),
      );
      await settle(tester);
      await settle(tester);
      String? started(String command) => launcher.starts
          .map((start) => start.arguments.take(2).join(' '))
          .where((name) => name == command)
          .firstOrNull;
      expect(started('icons generate'), isNotNull);
      expect(started('splash generate'), isNotNull);
      expect(find.textContaining('icon files'), findsOneWidget);
      expect(find.textContaining('splash files'), findsOneWidget);
      await closeApp(tester);
    });

    testWidgets('without a project it says why', (tester) async {
      final launcher = await pump(tester, withProject: false);
      await go(tester, 'App icon');
      await settle(tester);
      await tester.tap(find.widgetWithText(XButton, 'Icon and splash studio…'));
      await settle(tester, 2);
      await debounce(tester, launcher);
      await tester.tap(find.text('All screens'));
      await settle(tester, 2);
      final button = tester.widget<XButton>(
        find.widgetWithText(XButton, 'Write icon and splash to project'),
      );
      expect(button.onPressed, isNull);
      expect(button.disabledReason, 'Open a Flutter project first');
      await closeApp(tester);
    });
  });

  group('AC-026-16 the page shows the project', () {
    testWidgets('the same gallery, from the files', (tester) async {
      await pump(tester);
      await go(tester, 'App icon');
      await settle(tester);
      expect(find.byType(DeviceGallery), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Android icon sizes'),
        800,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Android icon sizes'), findsOneWidget);
    });

    testWidgets('says the splash is missing, and how to make it', (
      tester,
    ) async {
      await pump(tester, splashReport: _noSplash);
      await go(tester, 'App icon');
      await settle(tester);
      expect(
        find.textContaining('This project has no splash yet'),
        findsOneWidget,
      );
    });

    testWidgets('reads the splash files the check names', (tester) async {
      final imageSet = Directory(
        p.join(
          project.path,
          'ios',
          'Runner',
          'Assets.xcassets',
          'LaunchImage.imageset',
        ),
      )..createSync(recursive: true);
      File(p.join(imageSet.path, 'LaunchImage@2x.png')).writeAsBytesSync(_png);
      await pump(tester);
      await go(tester, 'App icon');
      await settle(tester);
      expect(find.textContaining('no splash yet'), findsNothing);
      final gallery = tester.widget<DeviceGallery>(find.byType(DeviceGallery));
      expect(gallery.content.logo, isNotNull);
      expect(gallery.content.background, const Color(0xFF123456));
    });
  });

  testWidgets('AC-024-18 the preview stays in view while the controls scroll', (
    tester,
  ) async {
    final launcher = await openStudio(tester);
    await debounce(tester, launcher);
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    await settle(tester, 2);
    final strip = find.widgetWithText(ChoiceChip, 'Web');
    final source = find.text('Source');
    final stripBefore = tester.getTopLeft(strip);
    final sourceBefore = tester.getTopLeft(source);
    await tester.drag(source, const Offset(0, -200));
    await settle(tester, 2);
    expect(tester.getTopLeft(strip), stripBefore);
    expect(tester.getTopLeft(source).dy, lessThan(sourceBefore.dy));
    await closeApp(tester);
  });

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
    final source = await pickImage(tester, launcher);

    // One for the icon and one for the splash, however many designs were sent.
    expect(
      commands(launcher).where((c) => c.contains('icons preview --serve')),
      hasLength(2),
    );
    final sent = designs(launcher).last;
    expect(sent['source'], source);
    expect(sent['padding'], '0');

    await tester.tap(find.widgetWithText(XButton, 'Write to project'));
    await settle(tester);
    final written = commands(launcher)
        .lastWhere((command) => command.startsWith('icons generate'));
    expect(written, contains('--padding 0'));
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
    await debounce(tester, launcher);

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
    // Margin always shows its sides: one value would do nothing (AC-026-29).
    expect(find.text('Margin'), findsOneWidget);
    expect(find.text('Top'), findsOneWidget);
    // The phones are there before a logo is.
    expect(find.text('Android 12+ (safe circle)'), findsOneWidget);

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
    await debounce(tester, launcher);
    expect(find.text('iPhone'), findsWidgets);
    expect(find.text('Android'), findsWidgets);
    expect(find.text('Android 12+ (safe circle)'), findsOneWidget);

    final sent = splashDesigns(launcher).last;
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
    final settings = Settings()
      ..wizardDismissed = true
      ..consoleOpen = true;
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
    await settle(tester);
    await debounce(tester, launcher);
    // Nothing chosen yet: a symbol on a colour, so there is a preview.
    final first = designs(launcher).first;
    expect(first['background'], IconStudioDesign.symbolBackground);
    expect(first['trim'], isTrue);
    await pickImage(tester, launcher);
    final write = tester.widget<XButton>(
      find.widgetWithText(XButton, 'Write to project'),
    );
    expect(write.onPressed, isNull);
    expect(write.disabledReason, 'Open a Flutter project first');
    final export = tester.widget<XButton>(
      find.widgetWithText(XButton, 'Export folder…'),
    );
    expect(export.onPressed, isNotNull);

    // The studio borrows the console's room, and gives it back.
    expect(settings.consoleOpen, isFalse);
    await tester.tap(find.byTooltip('Close'));
    await settle(tester, 2);
    expect(settings.consoleOpen, isTrue);
    expect(find.text('Open a Flutter project'), findsOneWidget);
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
