import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/cli/xcross_commands.dart';
import '../../src/state/job.dart';
import '../../src/state/readiness.dart';
import 'job_views.dart';

/// Where Apple lets a signed-in developer download Xcode. XCross Studio never
/// downloads Xcode itself: the download needs the user's own Apple ID.
const xcodeDownloadUrl = 'https://developer.apple.com/download/all/?q=Xcode';
const _flutterInstallUrl = 'https://docs.flutter.dev/install';

XStatus _statusOf(Health health) => switch (health) {
  Health.ok => XStatus.ready,
  Health.warning => XStatus.warning,
  Health.failed => XStatus.failed,
  Health.checking => XStatus.running,
  Health.unknown => XStatus.idle,
};

/// Settings card for the Darwin SDK: what the last check says, the Xcode.xip
/// to build it from, "Install SDK", and a link to Apple's download page.
/// Reinstalling is also how an SDK installed by an older xcross gets the
/// Swift runtime libraries an App Store build needs.
class DarwinSdkSettingsCard extends StatefulWidget {
  const DarwinSdkSettingsCard({super.key});

  @override
  State<DarwinSdkSettingsCard> createState() => _DarwinSdkSettingsCardState();
}

class _DarwinSdkSettingsCardState extends State<DarwinSdkSettingsCard> {
  Job? _install;

  void _start(String xip) {
    final services = Services.of(context);
    final job = services.jobs.run(
      'SDK install',
      XcrossCommands.sdkInstall(xip),
    );
    setState(() => _install = job);
    job.done.then((_) {
      if (mounted) services.readiness.runDoctor();
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final settings = services.settings;
    final readiness = services.readiness;
    final install = _install;
    return ListenableBuilder(
      listenable: Listenable.merge([settings, readiness, ?install]),
      builder: (context, _) {
        final health = readiness.area(ReadinessArea.darwinSdk);
        final running = install?.isRunning ?? false;
        final xip = settings.xcodeXip;
        return XCard(
          title: 'Darwin SDK',
          subtitle: 'Built once from your own Xcode.xip.',
          trailing: XButton(
            label: 'Check again',
            icon: Icons.refresh,
            variant: XButtonVariant.text,
            loading: readiness.checking,
            loadingLabel: 'Checking…',
            onPressed: readiness.runDoctor,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              XCheckRow(
                status: _statusOf(health.health),
                label: switch (health.health) {
                  Health.ok => 'Darwin SDK is ready',
                  Health.warning => 'Darwin SDK needs to be installed again',
                  Health.failed => 'Darwin SDK is missing or not usable',
                  Health.checking => 'Checking…',
                  Health.unknown => 'Not checked yet',
                },
                detail: health.health == Health.ok ? null : health.message,
              ),
              const SizedBox(height: XSpace.s3),
              XFilePickerField(
                label: 'Xcode.xip',
                directory: false,
                extensions: const ['xip'],
                value: xip,
                onChanged: (path) => settings.update((s) => s.xcodeXip = path),
              ),
              const SizedBox(height: XSpace.s3),
              Wrap(
                spacing: XSpace.s2,
                runSpacing: XSpace.s2,
                children: [
                  XButton(
                    label: health.health == Health.ok
                        ? 'Install SDK again'
                        : 'Install SDK',
                    icon: Icons.archive_outlined,
                    loading: running,
                    loadingLabel: 'Installing SDK…',
                    disabledReason: 'Choose your Xcode.xip first.',
                    onPressed: xip == null || running
                        ? null
                        : () => _start(xip),
                  ),
                  XButton(
                    label: 'Get Xcode from Apple',
                    icon: Icons.open_in_new,
                    variant: XButtonVariant.secondary,
                    onPressed: () =>
                        services.launcher.openUrl(xcodeDownloadUrl),
                  ),
                ],
              ),
              const SizedBox(height: XSpace.s2),
              const XNote(
                'Download Xcode (the .xip) from Apple with your Apple ID, pick '
                'it above, then Install SDK. It takes a few minutes and keeps '
                'only what builds need, including the Swift runtime libraries '
                'App Store uploads require.',
              ),
              if (install != null) ...[
                const SizedBox(height: XSpace.s3),
                JobPanel(job: install, consoleHeight: 180, input: true),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Settings card for the host tools (Flutter, Swift, LLVM): shows what is
/// missing and installs it with `xcross setup --yes` after a confirmation.
class MissingToolsCard extends StatefulWidget {
  const MissingToolsCard({super.key});

  @override
  State<MissingToolsCard> createState() => _MissingToolsCardState();
}

class _MissingToolsCardState extends State<MissingToolsCard> {
  Job? _setup;

  Future<void> _install() async {
    final services = Services.of(context);
    final confirmed = await showXConfirmDialog(
      context,
      title: 'Install missing tools?',
      message:
          'xcross setup downloads the setup script for your package manager '
          '(winget, Scoop, Chocolatey or direct vendor downloads) from the '
          'xcross repository, prints its origin and SHA-256, and runs it. It '
          'installs what is missing: the Swift toolchain, LLVM, Python and '
          'pymobiledevice3 (and the Visual Studio C++ tools on Windows when '
          'absent). Installers may ask for administrator approval.',
      confirmLabel: 'Install',
      details: [
        const XCommandPreview(
          arguments: ['setup', '--yes'],
          label: 'Runs',
          initiallyExpanded: true,
        ),
      ],
    );
    if (!confirmed || !mounted) return;
    final job = services.jobs.run('Setup', XcrossCommands.setup(yes: true));
    setState(() => _setup = job);
    job.done.then((_) {
      if (mounted) services.readiness.runDoctor();
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final readiness = services.readiness;
    final setup = _setup;
    return ListenableBuilder(
      listenable: Listenable.merge([readiness, ?setup]),
      builder: (context, _) {
        final running = setup?.isRunning ?? false;
        final flutter = readiness.area(ReadinessArea.flutter);
        final host = [
          (ReadinessArea.swift, 'Swift toolchain'),
          (ReadinessArea.llvm, 'LLVM (clang, ld64.lld)'),
        ];
        final missing = [
          for (final (area, _) in host)
            if (readiness.area(area).health
                case Health.failed || Health.warning)
              area,
        ];
        return XCard(
          title: 'Install missing tools',
          subtitle: 'One click for Swift, LLVM, Python and pymobiledevice3.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              XCheckRow(
                status: _statusOf(flutter.health),
                label: 'Flutter',
                detail: flutter.health == Health.ok ? null : flutter.message,
              ),
              for (final (area, label) in host)
                XCheckRow(
                  status: _statusOf(readiness.area(area).health),
                  label: label,
                  detail: readiness.area(area).health == Health.ok
                      ? null
                      : readiness.area(area).message,
                ),
              const SizedBox(height: XSpace.s3),
              Wrap(
                spacing: XSpace.s2,
                runSpacing: XSpace.s2,
                children: [
                  XButton(
                    label: missing.isEmpty
                        ? 'Run the installer anyway'
                        : 'Install missing tools',
                    icon: Icons.download,
                    variant: missing.isEmpty
                        ? XButtonVariant.secondary
                        : XButtonVariant.primary,
                    loading: running,
                    loadingLabel: 'Installing…',
                    onPressed: running ? null : _install,
                  ),
                  if (flutter.health == Health.failed)
                    XButton(
                      label: 'Get Flutter',
                      icon: Icons.open_in_new,
                      variant: XButtonVariant.secondary,
                      onPressed: () =>
                          services.launcher.openUrl(_flutterInstallUrl),
                    ),
                ],
              ),
              if (setup != null) ...[
                const SizedBox(height: XSpace.s3),
                JobPanel(job: setup, consoleHeight: 180, input: true),
              ],
            ],
          ),
        );
      },
    );
  }
}
