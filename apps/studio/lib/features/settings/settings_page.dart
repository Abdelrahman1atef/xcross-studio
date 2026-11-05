import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/cli/xcross_commands.dart';
import '../../src/state/job.dart';
import '../../src/state/settings.dart';
import '../common/doctor_checklist.dart';
import '../common/flutter_sdk_fix.dart';
import '../common/job_views.dart';
import '../common/toolchain_install.dart';

/// Settings (§6.7): the xcross CLI, toolchain readout, IDE integration,
/// appearance and shortcuts.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool? _sourceMode;
  Job? _update;
  Job? _ide;

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final settings = services.settings;
    final readiness = services.readiness;
    return ListenableBuilder(
      listenable: Listenable.merge([settings, readiness]),
      builder: (context, _) {
        final fromSource =
            _sourceMode ?? settings.invocation.executable == 'dart';
        final project = settings.projectPath;
        return WorkspaceLayout(
          title: 'Settings',
          children: [
            XCard(
              title: 'xcross command-line tool',
              subtitle: readiness.cliVersion ?? 'Version not read yet',
              trailing: XButton(
                label: 'Check for updates',
                variant: XButtonVariant.text,
                loading: _update?.isRunning ?? false,
                loadingLabel: 'Checking…',
                onPressed: () => setState(
                  () => _update = services.jobs.run(
                    'Update check',
                    XcrossCommands.updateCheck(),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Installed xcross'),
                        icon: Icon(Icons.terminal),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Run from source'),
                        icon: Icon(Icons.code),
                      ),
                    ],
                    selected: {fromSource},
                    onSelectionChanged: (choice) {
                      setState(() => _sourceMode = choice.first);
                      settings.update((s) {
                        s.invocation =
                            choice.first && s.sourceRepository != null
                            ? XcrossInvocation.fromSource(s.sourceRepository!)
                            : const XcrossInvocation.binary();
                      });
                    },
                  ),
                  const SizedBox(height: XSpace.s3),
                  if (fromSource)
                    XFilePickerField(
                      label: 'XCross Studio repository folder',
                      hint: 'Runs: dart run <folder>/packages/xcross/bin/xcross.dart',
                      value: settings.sourceRepository,
                      onChanged: (path) => settings.update((s) {
                        s.sourceRepository = path;
                        s.invocation = path == null
                            ? const XcrossInvocation.binary()
                            : XcrossInvocation.fromSource(path);
                      }),
                    )
                  else
                    XFilePickerField(
                      label: 'xcross executable',
                      hint:
                          'Leave as "xcross" to use the one bundled with the '
                          'app, else the one on PATH.',
                      directory: false,
                      extensions: Platform.isWindows
                          ? const ['exe', 'bat']
                          : const [],
                      value: settings.invocation.executable,
                      onChanged: (path) => settings.update(
                        (s) => s.invocation = XcrossInvocation.binary(
                          path ?? 'xcross',
                        ),
                      ),
                    ),
                  const SizedBox(height: XSpace.s2),
                  Text(
                    'Using: ${settings.effectiveInvocation}'
                    '${settings.invocation.isDefault && settings.bundledXcross != null ? '  (bundled with the app)' : ''}',
                    style: XType.mono.copyWith(
                      color: XTheme.of(context).colors.textSecondary,
                    ),
                  ),
                  if (_update != null) ...[
                    const SizedBox(height: XSpace.s3),
                    JobConsole(job: _update!, height: 120),
                  ],
                ],
              ),
            ),
            XCard(
              title: 'Toolchain',
              subtitle: 'From "xcross flutter doctor".',
              trailing: Wrap(
                spacing: XSpace.s2,
                children: [
                  XButton(
                    label: 'Setup wizard',
                    variant: XButtonVariant.text,
                    onPressed: () => services.app.openWizard?.call(),
                  ),
                  XButton(
                    label: 'Run checks',
                    icon: Icons.health_and_safety_outlined,
                    variant: XButtonVariant.secondary,
                    loading: readiness.checking,
                    loadingLabel: 'Checking…',
                    onPressed: readiness.runDoctor,
                  ),
                ],
              ),
              child: readiness.checks.isEmpty
                  ? XNote(
                      readiness.checking
                          ? 'Checking…'
                          : 'No checks yet. Run checks to read the Flutter '
                                'SDK, Swift, LLVM, Darwin SDK, device service '
                                'and sign-in status.',
                    )
                  : DoctorChecklist(checks: readiness.checks),
            ),
            const MissingToolsCard(),
            const DarwinSdkSettingsCard(),
            const FlutterSdkSettingsCard(), // feature 014
            XCard(
              title: 'IDE integration',
              subtitle: 'Run & Debug on the iPhone from your editor.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: XSpace.s2,
                    runSpacing: XSpace.s2,
                    children: [
                      XButton(
                        label: 'Set up VS Code',
                        icon: Icons.code,
                        variant: XButtonVariant.secondary,
                        disabledReason: 'Open a Flutter project first.',
                        onPressed: project == null
                            ? null
                            : () => setState(
                                () => _ide = services.jobs.run(
                                  'VS Code',
                                  XcrossCommands.ide('vscode'),
                                  workingDirectory: project,
                                ),
                              ),
                      ),
                      XButton(
                        label: 'Set up JetBrains IDEA',
                        icon: Icons.integration_instructions_outlined,
                        variant: XButtonVariant.secondary,
                        disabledReason: 'Open a Flutter project first.',
                        onPressed: project == null
                            ? null
                            : () => setState(
                                () => _ide = services.jobs.run(
                                  'JetBrains IDEA',
                                  XcrossCommands.ide('idea'),
                                  workingDirectory: project,
                                ),
                              ),
                      ),
                    ],
                  ),
                  if (_ide != null) ...[
                    const SizedBox(height: XSpace.s3),
                    JobConsole(job: _ide!, height: 120),
                  ],
                ],
              ),
            ),
            XCard(
              title: 'Appearance',
              child: SegmentedButton<ThemePreference>(
                segments: const [
                  ButtonSegment(
                    value: ThemePreference.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemePreference.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemePreference.system,
                    label: Text('System'),
                    icon: Icon(Icons.brightness_auto_outlined),
                  ),
                ],
                selected: {settings.theme},
                onSelectionChanged: (v) =>
                    settings.update((s) => s.theme = v.first),
              ),
            ),
            const XCard(
              title: 'Keyboard shortcuts',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Shortcut('Ctrl + K', 'Quick commands'),
                  _Shortcut('Ctrl + ,', 'Settings'),
                  _Shortcut('Ctrl + L', 'Logs & Debug'),
                  _Shortcut('Ctrl + J', 'Show or hide the console'),
                  _Shortcut('Ctrl + 1 … 7', 'Sidebar destinations'),
                ],
              ),
            ),
            XCard(
              title: 'About and data',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const XNote(
                    'XCross Studio is free, open-source software (AGPL-3.0) '
                    'and is not affiliated with or endorsed by Apple. It never '
                    'downloads or ships Xcode, iOS SDKs or developer disk '
                    'images: you provide your own and sign with your own Apple '
                    'ID or App Store Connect key.',
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: settings.acceptedNotice,
                    onChanged: (value) => settings.update(
                      (s) => s.acceptedNotice = value ?? false,
                    ),
                    title: const Text('I understand'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  XNote(
                    'Settings live in ${services.host.configDirectory(Platform.environment)}. '
                    'Credentials are kept by xcross itself; this app never '
                    'stores passwords or keys, and masks them in commands.',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut(this.keys, this.action);

  final String keys;
  final String action;

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(keys, style: XType.mono.copyWith(color: c.textPrimary)),
          ),
          Text(action, style: XType.body.copyWith(color: c.textSecondary)),
        ],
      ),
    );
  }
}
