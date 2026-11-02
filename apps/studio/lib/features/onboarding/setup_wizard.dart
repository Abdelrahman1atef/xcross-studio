import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/cli/xcross_commands.dart';
import '../../src/state/job.dart';
import '../../src/state/readiness.dart';
import '../common/doctor_checklist.dart';
import '../common/flutter_sdk_fix.dart';
import '../common/job_views.dart';
import '../common/readiness_views.dart';
import '../signing/signing_page.dart';

/// Opens the first-run wizard (§7) as a full-screen dialog.
Future<void> showSetupWizard(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const SetupWizard(),
      ),
    );

/// The five setup stages; each has Retry, Show details and Copy command.
enum WizardStep { environment, sdk, auth, device, firstBuild }

extension on WizardStep {
  String get title => switch (this) {
    WizardStep.environment => 'Environment',
    WizardStep.sdk => 'Darwin SDK',
    WizardStep.auth => 'Authentication',
    WizardStep.device => 'Device',
    WizardStep.firstBuild => 'First build',
  };

  bool get required => switch (this) {
    WizardStep.environment || WizardStep.sdk || WizardStep.auth => true,
    WizardStep.device || WizardStep.firstBuild => false,
  };
}

class SetupWizard extends StatefulWidget {
  const SetupWizard({super.key});

  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  WizardStep _step = WizardStep.environment;
  final Map<WizardStep, Job> _jobs = {};
  final Map<WizardStep, List<String>> _commands = {};
  bool _details = false;

  XStatus _status(WizardStep step) {
    final services = Services.of(context);
    final readiness = services.readiness;
    XStatus area(List<ReadinessArea> areas) {
      final healths = [for (final a in areas) readiness.area(a).health];
      if (healths.contains(Health.failed)) return XStatus.failed;
      if (healths.contains(Health.warning)) return XStatus.warning;
      if (healths.contains(Health.checking)) return XStatus.running;
      if (healths.every((h) => h == Health.ok)) return XStatus.ready;
      return XStatus.idle;
    }

    final job = _jobs[step];
    if (job != null && job.isRunning) return XStatus.running;
    return switch (step) {
      WizardStep.environment => area([
        ReadinessArea.flutter,
        ReadinessArea.swift,
        ReadinessArea.llvm,
        ReadinessArea.iosCompiler,
      ]),
      WizardStep.sdk => area([ReadinessArea.darwinSdk]),
      WizardStep.auth => area([ReadinessArea.auth]),
      WizardStep.device =>
        services.devices.selected == null ? XStatus.warning : XStatus.ready,
      WizardStep.firstBuild =>
        services.jobs.jobs.any(
              (j) =>
                  (j.title.startsWith('Build') || j.title.startsWith('Run')) &&
                  j.status == JobStatus.succeeded,
            )
            ? XStatus.ready
            : XStatus.idle,
    };
  }

  void _run(
    WizardStep step,
    String title,
    List<String> command, {
    bool structured = false,
  }) {
    final services = Services.of(context);
    final job = services.jobs.run(title, command, structured: structured);
    setState(() {
      _jobs[step] = job;
      _commands[step] = command;
      _details = true;
    });
    job.done.then((_) {
      if (mounted) services.readiness.runDoctor();
    });
  }

  Future<void> _installPrerequisites() async {
    final confirmed = await showXConfirmDialog(
      context,
      title: 'Install prerequisites?',
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
    if (confirmed && mounted) {
      _run(WizardStep.environment, 'Setup', XcrossCommands.setup(yes: true));
    }
  }

  void _close() {
    Services.of(context).settings.update((s) => s.wizardDismissed = true);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final c = XTheme.of(context).colors;
    return ListenableBuilder(
      listenable: Listenable.merge([
        services.readiness,
        services.devices,
        services.settings,
        services.jobs,
      ]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          backgroundColor: c.surface,
          title: const Text('Set up XCross Studio'),
          automaticallyImplyLeading: false,
          actions: [
            XButton(
              label: 'Close',
              variant: XButtonVariant.text,
              onPressed: _close,
            ),
            const SizedBox(width: XSpace.s3),
          ],
        ),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 260,
              color: c.surface,
              padding: const EdgeInsets.all(XSpace.s3),
              child: Column(
                children: [
                  for (final (i, step) in WizardStep.values.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: XSpace.s1),
                      child: XSidebarItem(
                        icon: switch (_status(step)) {
                          XStatus.ready => Icons.check_circle,
                          XStatus.failed => Icons.cancel,
                          XStatus.warning => Icons.error_outline,
                          XStatus.running => Icons.autorenew,
                          XStatus.idle => Icons.radio_button_unchecked,
                        },
                        label:
                            '${i + 1}. ${step.title}'
                            '${step.required ? '' : ' (optional)'}',
                        selected: step == _step,
                        onTap: () => setState(() {
                          _step = step;
                          _details = _jobs[step] != null;
                        }),
                      ),
                    ),
                ],
              ),
            ),
            VerticalDivider(width: 1, color: c.border),
            Expanded(child: _content(context)),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final services = Services.of(context);
    final step = _step;
    final status = _status(step);
    final job = _jobs[step];
    final command = _commands[step] ?? _defaultCommand(step);
    final index = WizardStep.values.indexOf(step);
    return ListView(
      padding: const EdgeInsets.all(XSpace.s6),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${index + 1}. ${step.title}',
                style: XType.title.copyWith(
                  color: XTheme.of(context).colors.textPrimary,
                ),
              ),
            ),
            XStatusBadge(
              status: status,
              label: step.required ? null : '${status.defaultLabel} · optional',
            ),
          ],
        ),
        const SizedBox(height: XSpace.s4),
        ..._stepBody(context, step),
        const SizedBox(height: XSpace.s4),
        Wrap(
          spacing: XSpace.s2,
          runSpacing: XSpace.s2,
          children: [
            XButton(
              label: 'Retry',
              icon: Icons.replay,
              variant: XButtonVariant.secondary,
              disabledReason: 'Nothing to retry yet.',
              onPressed: job == null || job.isRunning
                  ? null
                  : () => _run(
                      step,
                      job.title,
                      job.command,
                      structured: job.structured,
                    ),
            ),
            XButton(
              label: _details ? 'Hide details' : 'Show details',
              icon: Icons.terminal,
              variant: XButtonVariant.text,
              onPressed: () => setState(() => _details = !_details),
            ),
            if (command != null)
              XButton(
                label: 'Copy command',
                icon: Icons.copy,
                variant: XButtonVariant.text,
                onPressed: () => Clipboard.setData(
                  ClipboardData(
                    text: XCommandPreview.render('xcross', command),
                  ),
                ),
              ),
            const SizedBox(width: XSpace.s6),
            if (index > 0)
              XButton(
                label: 'Back',
                variant: XButtonVariant.text,
                onPressed: () =>
                    setState(() => _step = WizardStep.values[index - 1]),
              ),
            if (index < WizardStep.values.length - 1)
              XButton(
                label: 'Next',
                icon: Icons.arrow_forward,
                variant: status == XStatus.ready
                    ? XButtonVariant.primary
                    : XButtonVariant.secondary,
                onPressed: () =>
                    setState(() => _step = WizardStep.values[index + 1]),
              )
            else
              XButton(label: 'Finish', onPressed: _close),
          ],
        ),
        if (_details) ...[
          const SizedBox(height: XSpace.s4),
          if (job != null)
            JobPanel(job: job, consoleHeight: 220, input: true)
          else if (services.readiness.doctor != null)
            JobConsole(job: services.readiness.doctor!, height: 220)
          else
            const XNote('No command has run for this step yet.'),
        ],
      ],
    );
  }

  List<String>? _defaultCommand(WizardStep step) => switch (step) {
    WizardStep.environment => XcrossCommands.setup(yes: true),
    WizardStep.sdk => XcrossCommands.sdkInstall(
      Services.of(context).settings.xcodeXip ?? '<Xcode.xip>',
    ),
    WizardStep.auth => const ['auth'],
    WizardStep.device => XcrossCommands.devices(),
    WizardStep.firstBuild => XcrossCommands.run(mode: BuildMode.release),
  };

  List<Widget> _stepBody(BuildContext context, WizardStep step) {
    final services = Services.of(context);
    final readiness = services.readiness;
    switch (step) {
      case WizardStep.environment:
        return [
          const XNote(
            'Required host tools: Flutter, a Swift toolchain, LLVM (clang, '
            'ld64.lld) and Python with pymobiledevice3, plus the device '
            'service (Apple Mobile Device Service on Windows, usbmuxd on '
            'Linux).',
          ),
          const SizedBox(height: XSpace.s3),
          Wrap(
            spacing: XSpace.s3,
            runSpacing: XSpace.s3,
            children: [
              for (final area in [
                ReadinessArea.flutter,
                ReadinessArea.swift,
                ReadinessArea.llvm,
                ReadinessArea.iosCompiler,
                ReadinessArea.device,
              ])
                XToolchainCard(
                  title: areaTitle(area),
                  state: toolchainStateOf(readiness.area(area).health),
                  message: readiness.area(area).message,
                  width: 220,
                ),
            ],
          ),
          // Feature 014: one-click fix for a Flutter without an iOS compiler.
          for (final check in readiness.area(ReadinessArea.iosCompiler).checks)
            if (GenSnapshotProblem.fromCheck(check) case final problem?) ...[
              const SizedBox(height: XSpace.s3),
              FlutterSdkFixCard(
                problem: problem,
                retryLabel: 'Check again',
                onFixed: readiness.runDoctor,
              ),
            ],
          const SizedBox(height: XSpace.s4),
          Wrap(
            spacing: XSpace.s2,
            children: [
              XButton(
                label: 'Check',
                icon: Icons.health_and_safety_outlined,
                loading: readiness.checking,
                loadingLabel: 'Checking…',
                onPressed: () {
                  readiness.runDoctor();
                  setState(() => _details = true);
                },
              ),
              XButton(
                label: 'Install prerequisites',
                icon: Icons.download,
                variant: XButtonVariant.secondary,
                loading: _jobs[WizardStep.environment]?.isRunning ?? false,
                loadingLabel: 'Installing…',
                onPressed: _installPrerequisites,
              ),
            ],
          ),
          if (readiness.checks.isNotEmpty && _details) ...[
            const SizedBox(height: XSpace.s3),
            DoctorChecklist(checks: readiness.checks),
          ],
        ];
      case WizardStep.sdk:
        return [
          const XNote(
            'xcross extracts a private Darwin SDK from your own Xcode.xip '
            '(download it with your Apple ID from Apple). Nothing from Apple '
            'is shipped with XCross Studio. The SDK is tied to the Swift '
            'toolchain active now; reinstall it after changing Swift.',
          ),
          const SizedBox(height: XSpace.s3),
          XFilePickerField(
            label: 'Xcode.xip',
            directory: false,
            extensions: const ['xip'],
            value: services.settings.xcodeXip,
            onChanged: (path) =>
                services.settings.update((s) => s.xcodeXip = path),
          ),
          const SizedBox(height: XSpace.s3),
          XButton(
            label: 'Install SDK',
            icon: Icons.archive_outlined,
            loading: _jobs[WizardStep.sdk]?.isRunning ?? false,
            loadingLabel: 'Installing SDK…',
            disabledReason: 'Choose your Xcode.xip first.',
            onPressed: services.settings.xcodeXip == null
                ? null
                : () => _run(
                    WizardStep.sdk,
                    'SDK install',
                    XcrossCommands.sdkInstall(services.settings.xcodeXip!),
                  ),
          ),
          if (readiness.area(ReadinessArea.darwinSdk).message != null) ...[
            const SizedBox(height: XSpace.s3),
            XNote(readiness.area(ReadinessArea.darwinSdk).message!),
          ],
        ];
      case WizardStep.auth:
        return const [SigningForm()];
      case WizardStep.device:
        final devices = services.devices.devices;
        return [
          const XNote(
            'Connect the iPhone with a cable, unlock it and tap "Trust". iOS '
            '15/16 run release and profile builds; iOS 17+ debug runs also '
            'need the developer tunnel (Devices → Prepare USB tunnel).',
          ),
          const SizedBox(height: XSpace.s3),
          if (devices == null || devices.isEmpty)
            XNote(
              devices == null ? 'Looking for iPhones…' : 'No iPhone found yet.',
            )
          else
            for (final device in devices)
              XCheckRow(
                status: device.udid == services.settings.udid
                    ? XStatus.ready
                    : XStatus.idle,
                label: device.name,
                detail:
                    'iOS ${device.osVersion ?? '?'}'
                    '${device.legacy ? ' · release/profile only' : ''}',
              ),
          const SizedBox(height: XSpace.s3),
          XButton(
            label: 'Refresh',
            icon: Icons.refresh,
            variant: XButtonVariant.secondary,
            loading: services.devices.refreshing,
            loadingLabel: 'Looking…',
            onPressed: services.devices.refresh,
          ),
        ];
      case WizardStep.firstBuild:
        return [
          const XNote(
            'Open your Flutter project, then build and run it from Build & '
            'Run.',
          ),
          const SizedBox(height: XSpace.s3),
          XFilePickerField(
            label: 'Flutter project folder',
            value: services.settings.projectPath,
            onChanged: (path) =>
                services.settings.update((s) => s.projectPath = path),
          ),
          const SizedBox(height: XSpace.s3),
          XButton(
            label: 'Go to Build & Run',
            icon: Icons.play_arrow,
            disabledReason: 'Open a project first.',
            onPressed: services.settings.projectPath == null
                ? null
                : () {
                    services.app.go(Destination.build);
                    _close();
                  },
          ),
        ];
    }
  }
}
