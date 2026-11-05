// studio: 018 — Settings installs what the toolchain is missing: the Darwin SDK
// (with the Swift runtime libraries an App Store build needs) and the host
// tools, instead of a "checked" row and a command to type.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcross_studio/app/app.dart';
import 'package:xcross_studio/app/services.dart';
import 'package:xcross_studio/design_system/design_system.dart';
import 'package:xcross_studio/features/common/toolchain_install.dart';
import 'package:xcross_studio/src/cli/xcross_commands.dart';
import 'package:xcross_studio/src/host/host_platform.dart';
import 'package:xcross_studio/src/state/job.dart';
import 'package:xcross_studio/src/state/log_session.dart';
import 'package:xcross_studio/src/state/settings.dart';

import '../support/fake_launcher.dart';
import 'app_test.dart' show settle, go;

String _check(String name, String status, String message) => jsonEncode({
  'v': 1,
  'type': 'check',
  'section': 'Toolchain',
  'name': name,
  'status': status,
  'message': message,
  'path': null,
});

const _noSwiftRuntime =
    'Installed, but without the Swift runtime libraries an App Store build '
    'needs (App Store Connect error 90426). Install it again with '
    '`xcross sdk install <Xcode.xip>`.';

Future<FakeLauncher> _pump(
  WidgetTester tester, {
  List<String> doctor = const [],
  String? xip,
}) async {
  await tester.binding.setSurfaceSize(const Size(1600, 4000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final launcher = FakeLauncher(
    onStart: (process, arguments) async {
      if (arguments.join(' ') == 'flutter doctor') doctor.forEach(process.out);
      await process.exit(0);
    },
  );
  final settings = Settings()
    ..wizardDismissed = true
    ..xcodeXip = xip;
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
  await go(tester, 'Settings');
  await settle(tester);
  return launcher;
}

List<String> _commands(FakeLauncher launcher) => [
  for (final start in launcher.starts) start.arguments.join(' '),
];

void main() {
  testWidgets('the SDK without Swift libraries is not shown as ready', (
    tester,
  ) async {
    final launcher = await _pump(
      tester,
      doctor: [_check('Darwin SDK', 'warning', _noSwiftRuntime)],
      xip: r'C:\Downloads\Xcode_27.1.xip',
    );
    await tester.tap(find.widgetWithText(XButton, 'Check again').first);
    await settle(tester);
    expect(
      find.textContaining('Darwin SDK needs to be installed again'),
      findsOneWidget,
    );
    expect(find.textContaining('error 90426'), findsWidgets);
    expect(find.textContaining('Darwin SDK is ready'), findsNothing);

    await tester.tap(find.widgetWithText(XButton, 'Install SDK'));
    await settle(tester);
    expect(
      _commands(launcher),
      contains(r'sdk install C:\Downloads\Xcode_27.1.xip'),
    );
    // The check runs again by itself once the install ends.
    expect(
      _commands(launcher).where((c) => c == 'flutter doctor').length,
      greaterThan(1),
    );
  });

  testWidgets('Install SDK waits for an Xcode.xip and links to Apple', (
    tester,
  ) async {
    final launcher = await _pump(tester);
    final install = tester.widget<XButton>(
      find.widgetWithText(XButton, 'Install SDK'),
    );
    expect(install.onPressed, isNull);

    await tester.tap(find.widgetWithText(XButton, 'Get Xcode from Apple'));
    await settle(tester);
    expect(launcher.opened, [xcodeDownloadUrl]);
  });

  testWidgets('the host tools are installed with one confirmed click', (
    tester,
  ) async {
    final launcher = await _pump(
      tester,
      doctor: [
        _check('swift', 'failure', 'Not found.'),
        _check('clang++', 'failure', 'Not found.'),
      ],
    );
    await tester.tap(find.widgetWithText(XButton, 'Check again').first);
    await settle(tester);
    await tester.tap(find.widgetWithText(XButton, 'Install missing tools'));
    await settle(tester);
    expect(_commands(launcher), isNot(contains('setup --yes')));
    await tester.tap(find.widgetWithText(XButton, 'Install'));
    await settle(tester);
    expect(_commands(launcher), contains('setup --yes'));
  });
}
