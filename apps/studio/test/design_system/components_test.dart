import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcross_studio/design_system/design_system.dart';
import 'package:xcross_studio/src/cli/xcross_events.dart';
import 'package:xcross_studio/src/state/job.dart';
import 'package:xcross_studio/src/state/readiness.dart';
import 'package:xcross_studio/src/state/settings.dart';
import 'package:xcross_studio/src/cli/xcross_commands.dart';

import '../support/fake_launcher.dart';

Future<void> pumpThemed(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: xDarkTheme(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

double _luminance(Color color) {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('AC-013-11 shared tokens (palette values: AC-029 tokens_test)', () {
    test('shared spacing, radii and type scale are unchanged', () {
      expect(
        [XSpace.s1, XSpace.s2, XSpace.s3, XSpace.s4, XSpace.s6, XSpace.s8],
        [4, 8, 12, 16, 24, 32],
      );
      expect([XRadius.sm, XRadius.md, XRadius.lg, XRadius.xl], [6, 10, 12, 16]);
      expect(XType.title.fontSize, 24);
      expect(XType.section.fontSize, 18);
      expect(XType.card.fontSize, 15);
      expect(XType.body.fontSize, 14);
      expect(XType.mono.fontFamily, 'JetBrainsMono');
    });

    test('text and status colours meet WCAG AA (4.5:1) on every surface', () {
      for (final palette in [XColors.dark, XColors.light]) {
        for (final background in [
          palette.canvas,
          palette.surface,
          palette.surfaceElevated,
        ]) {
          // textMuted is placeholder/inactive metadata; see tokens_test.dart.
          expect(
            contrast(palette.textMuted, background),
            greaterThanOrEqualTo(3.0),
            reason: 'textMuted on $background',
          );
          for (final text in [
            palette.textPrimary,
            palette.textSecondary,
            palette.success,
            palette.warning,
            palette.error,
          ]) {
            expect(
              contrast(text, background),
              greaterThanOrEqualTo(4.5),
              reason: '$text on $background',
            );
          }
        }
      }
      // Log text on the console surface.
      for (final text in [
        XColors.dark.textPrimary,
        XColors.dark.textSecondary,
        XColors.dark.textMuted,
        XColors.dark.error,
        XColors.dark.warning,
        XColors.dark.success,
        XColors.dark.primary,
        XColors.dark.primaryHover,
      ]) {
        expect(contrast(text, XColors.dark.console), greaterThanOrEqualTo(4.5));
      }
    });
  });

  testWidgets('AC-013-12 status badges always show an icon and text', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      const Column(
        children: [
          XStatusBadge(status: XStatus.ready),
          XStatusBadge(status: XStatus.warning),
          XStatusBadge(status: XStatus.failed),
          XStatusBadge(status: XStatus.idle),
        ],
      ),
    );
    for (final status in [
      XStatus.ready,
      XStatus.warning,
      XStatus.failed,
      XStatus.idle,
    ]) {
      expect(find.text(status.defaultLabel), findsOneWidget);
      expect(find.byIcon(status.icon), findsOneWidget);
    }
    expect(find.text('Needs attention'), findsOneWidget);
  });

  testWidgets('AC-013-13 the stepper shows each step state', (tester) async {
    await pumpThemed(
      tester,
      const XBuildStepper(
        steps: [
          XStepItem(
            'Resolving dependencies',
            XStepState.passed,
            detail: '1.2s',
          ),
          XStepItem('Compiling Runner', XStepState.active),
          XStepItem('Signing', XStepState.failed, detail: 'no profile'),
          XStepItem('Install', XStepState.skipped),
          XStepItem('Launch', XStepState.waiting),
        ],
      ),
    );
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsOneWidget);
    expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    expect(
      find.bySemanticsLabel('Failed: Signing, no profile'),
      findsOneWidget,
    );
  });

  testWidgets('AC-013-14 diagnostic cards show only real codes, and the fix', (
    tester,
  ) async {
    var viewed = false;
    await pumpThemed(
      tester,
      Column(
        children: [
          XDiagnosticCard(
            severity: XDiagnosticSeverity.error,
            message: 'No iPhone is connected by USB.',
            code: 'device.not_found',
            hint: 'Connect the iPhone and tap Trust.',
            command: 'xcross devices --json',
            onViewLogs: () => viewed = true,
          ),
          const XDiagnosticCard(
            severity: XDiagnosticSeverity.warning,
            message: 'Something without a code.',
          ),
        ],
      ),
    );
    expect(find.text('Code: device.not_found'), findsOneWidget);
    expect(find.textContaining('Code:'), findsOneWidget);
    expect(find.text('Connect the iPhone and tap Trust.'), findsOneWidget);
    await tester.tap(find.text('View logs'));
    expect(viewed, isTrue);
    expect(find.text('Copy command'), findsOneWidget);
  });

  testWidgets('AC-013-15 the command preview never shows a password', (
    tester,
  ) async {
    final command = XcrossCommands.authAppleId(
      'me@example.com',
      password: 'hunter2',
      anisetteUrl: 'https://ani.example',
    );
    expect(
      XCommandPreview.render('xcross', command),
      'xcross auth --apple-id=me@example.com --password •••• '
      '--anisette-url=https://ani.example',
    );
    expect(
      XCommandPreview.render('xcross', ['auth', '--password=s3cret']),
      'xcross auth --password=••••',
    );
    await pumpThemed(
      tester,
      XCommandPreview(arguments: command, initiallyExpanded: true),
    );
    expect(find.textContaining('hunter2'), findsNothing);
    expect(find.textContaining('••••'), findsWidgets);
  });

  testWidgets('AC-013-16 a loading button keeps its operation label', (
    tester,
  ) async {
    var taps = 0;
    await pumpThemed(
      tester,
      Column(
        children: [
          XButton(
            label: 'Sign in',
            loading: true,
            loadingLabel: 'Signing…',
            onPressed: () => taps++,
          ),
          const XButton(
            label: 'Install',
            disabledReason: 'Choose an .ipa file first.',
            onPressed: null,
          ),
        ],
      ),
    );
    expect(find.text('Signing…'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
    await tester.tap(find.text('Signing…'));
    expect(taps, 0);
    expect(find.byTooltip('Choose an .ipa file first.'), findsOneWidget);
  });

  testWidgets('AC-013-17 progress is determinate only with a real fraction', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      const Column(
        children: [
          XProgressIndicator(label: 'Downloading engine', fraction: 0.42),
          XProgressIndicator(label: 'Compiling…'),
        ],
      ),
    );
    expect(find.text('42%'), findsOneWidget);
    final bars = tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .toList();
    expect(bars.first.value, closeTo(0.42, 1e-9));
    expect(bars.last.value, isNull);
  });

  test(
    'AC-013-4 doctor checks map to readiness areas without invention',
    () async {
      final jobs = JobCenter(
        launcher: FakeLauncher(
          onStart: (process, _) async {
            for (final line in [
              '{"v":1,"type":"check","section":"iOS toolchain","name":"swift",'
                  '"status":"failure","message":"Not found.","path":null}',
              '{"v":1,"type":"check","section":"iOS toolchain",'
                  '"name":"clang++","status":"success","message":"ok","path":null}',
              '{"v":1,"type":"check","section":"Deployment",'
                  '"name":"Device","status":"warning",'
                  '"message":"No connected iOS device found.","path":null}',
            ]) {
              process.out(line);
            }
            await process.exit(1);
          },
        ),
        invocation: () => const XcrossInvocation.binary(),
      );
      final readiness = ReadinessController(jobs, Settings());
      await readiness.runDoctor().done;
      expect(readiness.area(ReadinessArea.swift).health, Health.failed);
      expect(readiness.area(ReadinessArea.llvm).health, Health.ok);
      expect(readiness.area(ReadinessArea.device).health, Health.warning);
      expect(readiness.area(ReadinessArea.darwinSdk).health, Health.unknown);
      expect(readiness.area(ReadinessArea.auth).health, Health.unknown);
      expect(readiness.toolchain.health, Health.failed);
      expect(readiness.needsSetup, isTrue);
      expect(
        ReadinessController.areaOf(
          const DoctorCheckResult(
            section: 'Flutter project',
            name: 'Project',
            status: 'warning',
            message: 'No pubspec.yaml',
          ),
        ),
        isNull,
      );
    },
  );
}
