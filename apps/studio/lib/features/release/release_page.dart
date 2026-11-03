import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../app/app_controller.dart';
import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/cli/xcross_commands.dart';
import '../../src/cli/xcross_events.dart';
import '../../src/state/job.dart';
import '../../src/state/project_info.dart';
import '../../src/state/readiness.dart';
import '../common/job_views.dart';
import '../common/readiness_views.dart';

/// Release (feature 022): US-IOS-001 in order, from readiness to App Store
/// submission. Every step runs an `xcross` command (features 016–021).
class ReleasePage extends StatefulWidget {
  const ReleasePage({super.key});

  @override
  State<ReleasePage> createState() => _ReleasePageState();
}

class _ReleasePageState extends State<ReleasePage> {
  final Map<int, Job> _jobs = {};
  bool _autoBuildNumber = true;
  ReleaseGateResult? _gate;
  ReleaseCheckReport? _check;
  final List<PublishEvent> _publish = [];
  TestFlightStatus? _testflight;
  AppStoreStatus? _store;
  final _group = TextEditingController(text: 'QA');
  final _whatToTest = TextEditingController();

  @override
  void dispose() {
    _group.dispose();
    _whatToTest.dispose();
    super.dispose();
  }

  Future<void> _run(
    int step,
    String title,
    List<String> command, {
    bool structured = false,
    void Function(XcrossEvent event)? onEvent,
  }) async {
    final services = Services.of(context);
    final project = services.settings.projectPath;
    if (project == null) return;
    final job = services.jobs.run(
      title,
      command,
      workingDirectory: project,
      structured: structured,
      onEvent: (event) {
        onEvent?.call(event);
        if (mounted) setState(() {});
      },
    );
    setState(() => _jobs[step] = job);
    await job.done;
    if (mounted) setState(() {});
  }

  XStatus _statusOf(int step) => switch (_jobs[step]?.status) {
    JobStatus.running => XStatus.running,
    JobStatus.succeeded => XStatus.ready,
    JobStatus.failed || JobStatus.cancelled => XStatus.failed,
    _ => XStatus.idle,
  };

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([services.settings, services.readiness]),
      builder: (context, _) {
        final project = services.settings.projectPath;
        return WorkspaceLayout(
          title: 'Release',
          subtitle:
              'Build, check, upload and submit an App Store release in the '
              'order of US-IOS-001. Every step runs an xcross command.',
          children: project == null
              ? const [
                  XEmptyState(
                    icon: Icons.rocket_launch_outlined,
                    title: 'Open a Flutter project',
                    message:
                        'Choose a project on Overview to prepare its App Store '
                        'release.',
                  ),
                ]
              : _steps(context, project),
        );
      },
    );
  }

  List<Widget> _steps(BuildContext context, String project) {
    final services = Services.of(context);
    final readiness = services.readiness;
    return [
      _ReleaseStep(
        number: 1,
        title: 'Readiness',
        status: readiness.checking
            ? XStatus.running
            : readiness.needsSetup
            ? XStatus.failed
            : readiness.checks.isEmpty
            ? XStatus.idle
            : XStatus.ready,
        description:
            'Toolchain, Darwin SDK (iOS 26 or later), sign-in, device and push '
            'notifications.',
        actions: [
          XButton(
            label: 'Run checks',
            icon: Icons.refresh,
            variant: XButtonVariant.secondary,
            loading: readiness.checking,
            loadingLabel: 'Checking…',
            onPressed: readiness.runDoctor,
          ),
        ],
        child: Wrap(
          spacing: XSpace.s2,
          runSpacing: XSpace.s2,
          children: [
            for (final area in ReadinessArea.values)
              if (area != ReadinessArea.push ||
                  readiness.area(area).checks.isNotEmpty)
                XStatusBadge(
                  status: statusOfHealth(readiness.area(area).health),
                  label: areaTitle(area),
                ),
          ],
        ),
      ),
      FutureBuilder<ProjectInfo>(
        future: ProjectInfo.read(project),
        builder: (context, snapshot) => _ReleaseStep(
          number: 2,
          title: 'Version and build',
          status: XStatus.idle,
          description:
              'pubspec.yaml version ${snapshot.data?.version ?? '…'}. With the '
              'switch on, the build number is one past the newest build on App '
              'Store Connect.',
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use the next App Store Connect build number'),
            value: _autoBuildNumber,
            onChanged: (value) => setState(() => _autoBuildNumber = value),
          ),
        ),
      ),
      _ReleaseStep(
        number: 3,
        title: 'Signing',
        status: statusOfHealth(readiness.signing.health),
        description:
            'App Store signing needs an App Store Connect team key with the '
            'Admin or App Manager role (an Apple ID only signs for devices).',
        actions: [
          XButton(
            label: 'Open Signing',
            variant: XButtonVariant.secondary,
            onPressed: () => services.app.go(Destination.signing),
          ),
        ],
      ),
      _ReleaseStep(
        number: 4,
        title: 'Quality gate',
        status: _gate == null
            ? _statusOf(4)
            : (_gate!.passed ? XStatus.ready : XStatus.failed),
        description: 'flutter analyze and flutter test in the project.',
        command: XcrossCommands.releaseGate(),
        job: _jobs[4],
        actions: [
          XButton(
            label: 'Run the gate',
            icon: Icons.fact_check_outlined,
            loading: _jobs[4]?.isRunning ?? false,
            loadingLabel: 'Running…',
            onPressed: () => _run(
              4,
              'Quality gate',
              XcrossCommands.releaseGate(),
              onEvent: (event) {
                if (event is ReleaseGateResult) _gate = event;
              },
            ),
          ),
        ],
        child: _gate == null
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final step in _gate!.steps)
                    XCheckRow(
                      status: step.passed ? XStatus.ready : XStatus.failed,
                      label: step.name,
                      detail: step.passed ? null : step.tail.join('\n'),
                    ),
                ],
              ),
      ),
      _ReleaseStep(
        number: 5,
        title: 'Archive and IPA',
        status: _statusOf(5),
        description:
            'Signs for the App Store and writes build/xcross-ios/ipa and '
            'build/xcross-ios/archive/Runner.xcarchive.',
        command: XcrossCommands.appStoreBuild(
          autoBuildNumber: _autoBuildNumber,
        ),
        job: _jobs[5],
        actions: [
          XButton(
            label: 'Build for the App Store',
            icon: Icons.inventory_2_outlined,
            loading: _jobs[5]?.isRunning ?? false,
            loadingLabel: 'Building…',
            onPressed: () => _run(
              5,
              'App Store build',
              XcrossCommands.appStoreBuild(autoBuildNumber: _autoBuildNumber),
              structured: true,
            ),
          ),
        ],
        child: _jobs[5]?.artifacts.isEmpty ?? true
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final artifact in _jobs[5]!.artifacts)
                    XNote('${artifact.kind}: ${artifact.path}'),
                ],
              ),
      ),
      _ReleaseStep(
        number: 6,
        title: 'Release check',
        status: _check == null
            ? _statusOf(6)
            : (_check!.errors == 0 ? XStatus.ready : XStatus.failed),
        description:
            'What App Store Connect would reject: signing, SDK, Info.plist, '
            'permissions, privacy manifests, icons, iPad.',
        command: XcrossCommands.releaseCheck(),
        job: _jobs[6],
        actions: [
          XButton(
            label: 'Check the IPA',
            icon: Icons.rule,
            loading: _jobs[6]?.isRunning ?? false,
            loadingLabel: 'Checking…',
            onPressed: () => _run(
              6,
              'Release check',
              XcrossCommands.releaseCheck(),
              onEvent: (event) {
                if (event is ReleaseCheckReport) _check = event;
              },
            ),
          ),
        ],
        child: _check == null ? null : _CheckReport(report: _check!),
      ),
      _ReleaseStep(
        number: 7,
        title: 'Upload and processing',
        status: _statusOf(7),
        description:
            'Uploads with the App Store Connect Build Upload API, then waits '
            'until Apple has processed the build.',
        command: XcrossCommands.publish(),
        job: _jobs[7],
        actions: [
          XButton(
            label: 'Upload',
            icon: Icons.cloud_upload_outlined,
            loading: _jobs[7]?.isRunning ?? false,
            loadingLabel: 'Uploading…',
            onPressed: () {
              _publish.clear();
              _run(
                7,
                'Upload to App Store Connect',
                XcrossCommands.publish(),
                onEvent: (event) {
                  if (event is PublishEvent) _publish.add(event);
                },
              );
            },
          ),
        ],
        child: _publish.isEmpty ? null : _PublishProgress(events: _publish),
      ),
      _ReleaseStep(
        number: 8,
        title: 'TestFlight',
        status: _statusOf(8),
        description:
            'Builds on App Store Connect with their processing and beta '
            'states; add one to a group with notes for testers.',
        command: XcrossCommands.testflightStatus(),
        job: _jobs[8],
        actions: [
          XButton(
            label: 'Refresh',
            icon: Icons.refresh,
            variant: XButtonVariant.secondary,
            loading: _jobs[8]?.isRunning ?? false,
            loadingLabel: 'Reading…',
            onPressed: () => _run(
              8,
              'TestFlight status',
              XcrossCommands.testflightStatus(),
              onEvent: (event) {
                if (event is TestFlightStatus) _testflight = event;
              },
            ),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_testflight != null)
              for (final build in _testflight!.builds)
                XNote(
                  '${build['version']} (${build['buildNumber']})  '
                  '${build['processingState']}  internal: '
                  '${build['internalBuildState'] ?? '—'}  external: '
                  '${build['externalBuildState'] ?? '—'}',
                ),
            const SizedBox(height: XSpace.s2),
            Wrap(
              spacing: XSpace.s2,
              runSpacing: XSpace.s2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                XTextField(controller: _group, label: 'Group', width: 180),
                XButton(
                  label: 'Add newest build to group',
                  variant: XButtonVariant.secondary,
                  onPressed: () => _run(
                    8,
                    'Add to TestFlight group',
                    XcrossCommands.testflightAdd(_group.text),
                  ),
                ),
                XTextField(
                  controller: _whatToTest,
                  label: 'What to Test',
                  width: 320,
                ),
                XButton(
                  label: 'Save notes',
                  variant: XButtonVariant.secondary,
                  onPressed: () => _run(
                    8,
                    'What to Test',
                    XcrossCommands.whatToTest(_whatToTest.text),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      _ReleaseStep(
        number: 9,
        title: 'App Store submission',
        status: _statusOf(9),
        description:
            'The App Store version, its build and review submissions. App '
            'Privacy, pricing and agreements are set in App Store Connect.',
        command: XcrossCommands.appStoreStatus(),
        job: _jobs[9],
        actions: [
          XButton(
            label: 'Refresh',
            icon: Icons.refresh,
            variant: XButtonVariant.secondary,
            onPressed: () => _run(
              9,
              'App Store status',
              XcrossCommands.appStoreStatus(),
              onEvent: (event) {
                if (event is AppStoreStatus) _store = event;
              },
            ),
          ),
          XButton(
            label: 'Check (dry run)',
            variant: XButtonVariant.secondary,
            onPressed: () => _run(
              9,
              'Submission check',
              XcrossCommands.appStoreSubmit(dryRun: true),
            ),
          ),
          XButton(
            label: 'Submit for review',
            icon: Icons.send_outlined,
            onPressed: () => _submit(context),
          ),
        ],
        child: _store == null
            ? null
            : XNote(
                'Version ${_store!.version ?? '—'} (${_store!.state ?? '—'}), '
                'build ${_store!.build ?? 'not attached'}; '
                '${_store!.submissions.length} recent review submissions.',
              ),
      ),
      _ReleaseStep(
        number: 10,
        title: 'Release record and CI',
        status: XStatus.idle,
        description:
            'build/xcross-ios/release.json (US-IOS-001 §11), and a GitHub '
            'workflow that runs these steps on ubuntu-latest.',
        command: XcrossCommands.releaseCi(),
        job: _jobs[10],
        actions: [
          XButton(
            label: 'Create CI workflow',
            icon: Icons.integration_instructions_outlined,
            variant: XButtonVariant.secondary,
            onPressed: () =>
                _run(10, 'CI workflow', XcrossCommands.releaseCi()),
          ),
        ],
        child: _ReleaseRecord(project: project),
      ),
    ];
  }

  Future<void> _submit(BuildContext context) async {
    final confirmed = await showXConfirmDialog(
      context,
      title: 'Submit this version for App Review?',
      message:
          'xcross attaches nothing new: it submits the App Store version with '
          'the build already attached. Apple reviews it; you can cancel the '
          'submission in App Store Connect.',
      confirmLabel: 'Submit for review',
    );
    if (confirmed && mounted) {
      await _run(
        9,
        'Submit for review',
        XcrossCommands.appStoreSubmit(dryRun: false),
      );
    }
  }
}

/// One numbered step.
class _ReleaseStep extends StatelessWidget {
  const _ReleaseStep({
    required this.number,
    required this.title,
    required this.status,
    required this.description,
    this.actions = const [],
    this.command,
    this.job,
    this.child,
  });

  final int number;
  final String title;
  final XStatus status;
  final String description;
  final List<Widget> actions;
  final List<String>? command;
  final Job? job;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: XSpace.s3),
    child: XCard(
      title: '$number. $title',
      trailing: XStatusBadge(status: status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          XNote(description),
          if (child != null) ...[const SizedBox(height: XSpace.s3), child!],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: XSpace.s3),
            Wrap(spacing: XSpace.s2, runSpacing: XSpace.s2, children: actions),
          ],
          if (command != null) ...[
            const SizedBox(height: XSpace.s2),
            XCommandPreview(arguments: command!),
          ],
          if (job != null) ...[
            const SizedBox(height: XSpace.s2),
            JobConsole(job: job!, height: 140, showTitle: false),
          ],
        ],
      ),
    ),
  );
}

/// `release check` results, errors first.
class _CheckReport extends StatelessWidget {
  const _CheckReport({required this.report});

  final ReleaseCheckReport report;

  @override
  Widget build(BuildContext context) {
    final ordered = [
      for (final severity in const ['error', 'warning', 'info'])
        ...report.issues.where((issue) => issue.severity == severity),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        XNote(
          '${report.errors} errors, ${report.warnings} warnings · '
          '${report.configuration['bundleId'] ?? ''} '
          '${report.configuration['version'] ?? ''}',
        ),
        for (final issue in ordered)
          XCheckRow(
            status: switch (issue.severity) {
              'error' => XStatus.failed,
              'warning' => XStatus.warning,
              _ => XStatus.idle,
            },
            label: '[${issue.code}] ${issue.message}',
            detail: issue.hint,
          ),
      ],
    );
  }
}

/// Part progress and states of `xcross publish --json`.
class _PublishProgress extends StatelessWidget {
  const _PublishProgress({required this.events});

  final List<PublishEvent> events;

  @override
  Widget build(BuildContext context) {
    final progress = events.lastWhereOrNull((e) => e.event == 'progress');
    final states = [
      for (final event in events)
        if (event.event == 'state')
          '${event.fields['upload'] ?? event.fields['processing']}',
    ];
    final issues = [
      for (final event in events)
        if (event.event == 'issue')
          '${event.fields['severity']} ${event.fields['code']}: '
              '${event.fields['description']}',
    ];
    final total = progress?.fields['total'];
    final bytes = progress?.fields['bytes'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (progress != null)
          XProgressIndicator(
            label:
                'Part ${progress.fields['part']} of ${progress.fields['parts']}',
            fraction: total is num && bytes is num && total > 0
                ? (bytes / total).clamp(0, 1).toDouble()
                : null,
          ),
        if (states.isNotEmpty) XNote('States: ${states.join(' → ')}'),
        for (final issue in issues) XNote(issue),
      ],
    );
  }
}

/// `build/xcross-ios/release.json`, with Copy and Open folder.
class _ReleaseRecord extends StatelessWidget {
  const _ReleaseRecord({required this.project});

  final String project;

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final file = File(p.join(project, 'build', 'xcross-ios', 'release.json'));
    if (!file.existsSync()) {
      return const XNote(
        'No release record yet: `xcross publish` writes it when it uploads.',
      );
    }
    final text = file.readAsStringSync();
    Map<String, Object?> record = const {};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) record = decoded.cast<String, Object?>();
    } on FormatException {
      record = const {};
    }
    String field(String key, [String? sub]) {
      final value = record[key];
      if (sub == null) return '${value ?? '—'}';
      return value is Map ? '${value[sub] ?? '—'}' : '—';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        XNote(
          '${field('app')} ${field('version')} (${field('build')}) · upload '
          '${field('upload', 'state')} · processing '
          '${field('build_record', 'processingState')} · commit '
          '${field('git', 'commit')}',
        ),
        const SizedBox(height: XSpace.s2),
        Wrap(
          spacing: XSpace.s2,
          children: [
            XButton(
              label: 'Copy record',
              variant: XButtonVariant.secondary,
              onPressed: () => Clipboard.setData(ClipboardData(text: text)),
            ),
            XButton(
              label: 'Open folder',
              variant: XButtonVariant.secondary,
              onPressed: () => services.launcher.openFolder(file.parent.path),
            ),
          ],
        ),
      ],
    );
  }
}

extension<T> on List<T> {
  T? lastWhereOrNull(bool Function(T element) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}
