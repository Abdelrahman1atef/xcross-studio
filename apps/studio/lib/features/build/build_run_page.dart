import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../app/app_controller.dart';
import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/cli/xcross_commands.dart';
import '../../src/state/job.dart';
import '../../src/state/project_info.dart';
import '../common/attention_widgets.dart';
import '../common/flutter_sdk_fix.dart';
import '../common/job_views.dart';

/// Build & Run (§6.2): build, sign, install and launch with every step the
/// CLI reports visible.
class BuildRunPage extends StatefulWidget {
  const BuildRunPage({super.key, this.onInstall});

  /// Called with a built `.ipa` when the user wants to install it.
  final ValueChanged<String>? onInstall;

  @override
  State<BuildRunPage> createState() => _BuildRunPageState();
}

class _BuildRunPageState extends State<BuildRunPage> {
  ProjectInfo? _info;
  String? _loadedFor;
  Job? _job;
  Job? _check;
  BuildMode _mode = BuildMode.release;
  bool _ipa = true;
  final _buildName = TextEditingController();
  final _buildNumber = TextEditingController();

  @override
  void dispose() {
    _buildName.dispose();
    _buildNumber.dispose();
    super.dispose();
  }

  Future<void> _load(String? path) async {
    _loadedFor = path;
    if (path == null) {
      setState(() => _info = null);
      return;
    }
    final info = await ProjectInfo.read(path);
    if (mounted && _loadedFor == path) setState(() => _info = info);
  }

  /// Newest `.ipa` in the output folder (for CLIs without `artifact` events).
  String? _newestIpa() {
    final info = _info;
    if (info == null) return null;
    final dir = Directory(info.outputDirectory);
    if (!dir.existsSync()) return null;
    final ipas = dir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.ipa'),
    );
    if (ipas.isEmpty) return null;
    return (ipas.toList()..sort(
          (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
        ))
        .first
        .path;
  }

  List<String> _runCommand(String? udid) =>
      XcrossCommands.run(mode: _mode, udid: udid);

  List<String> _buildCommand() => XcrossCommands.build(
    mode: _mode,
    ipa: _ipa,
    buildName: _buildName.text,
    buildNumber: _buildNumber.text,
  );

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final settings = services.settings;
    return ListenableBuilder(
      listenable: Listenable.merge([settings, services.devices]),
      builder: (context, _) {
        if (_loadedFor != settings.projectPath) _load(settings.projectPath);
        final info = _info;
        final project = settings.projectPath;
        final ready = info?.isFlutterProject ?? false;
        final device = services.devices.selected;
        final legacy = device?.legacy ?? false;
        if (legacy && _mode == BuildMode.debug) _mode = BuildMode.release;
        final running = _job?.isRunning ?? false;
        final reason = !ready
            ? 'Open a Flutter project first (Overview).'
            : (running ? 'A build is running.' : null);
        return WorkspaceLayout(
          title: 'Build & Run',
          subtitle:
              'Build, sign, install and launch your Flutter app on the iPhone.',
          actions: [
            XButton(
              label: 'Check project',
              icon: Icons.fact_check_outlined,
              variant: XButtonVariant.text,
              loading: _check?.isRunning ?? false,
              loadingLabel: 'Checking…',
              disabledReason: 'Open a Flutter project first.',
              onPressed: !ready
                  ? null
                  : () => setState(
                      () => _check = services.jobs.run(
                        'Flutter doctor',
                        XcrossCommands.flutterDoctor(),
                        workingDirectory: project,
                        structured: true,
                      ),
                    ),
            ),
          ],
          children: [
            // Features 027 and 028: what to settle before building.
            const AttentionList(title: 'Before you build'),
            XCard(
              title: 'Project',
              child: XFilePickerField(
                label: 'Flutter project folder',
                value: project,
                error: info != null && !info.isFlutterProject
                    ? 'Not a Flutter project with an ios/ folder.'
                    : null,
                hint: info?.name == null
                    ? null
                    : '${info!.name} ${info.version ?? ''} · '
                          '${info.bundleId ?? 'bundle id not found'}',
                onChanged: (path) =>
                    settings.update((s) => s.projectPath = path),
              ),
            ),
            XCard(
              title: 'Options',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: XSpace.s4,
                    runSpacing: XSpace.s3,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SegmentedButton<BuildMode>(
                        segments: [
                          ButtonSegment(
                            value: BuildMode.debug,
                            label: const Text('Debug'),
                            enabled: !legacy,
                            tooltip: legacy
                                ? 'iOS 15/16: debug needs a debugger'
                                : null,
                          ),
                          const ButtonSegment(
                            value: BuildMode.profile,
                            label: Text('Profile'),
                          ),
                          const ButtonSegment(
                            value: BuildMode.release,
                            label: Text('Release'),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (m) =>
                            setState(() => _mode = m.first),
                      ),
                      FilterChip(
                        label: const Text('.ipa file'),
                        selected: _ipa,
                        onSelected: (v) => setState(() => _ipa = v),
                      ),
                      XTextField(
                        controller: _buildName,
                        label: 'Version (optional)',
                        width: 170,
                        onChanged: (_) => setState(() {}),
                      ),
                      XTextField(
                        controller: _buildNumber,
                        label: 'Build no. (optional)',
                        width: 160,
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                  const SizedBox(height: XSpace.s3),
                  XCheckRow(
                    status: device == null
                        ? XStatus.warning
                        : (legacy ? XStatus.warning : XStatus.ready),
                    label: device == null
                        ? 'No iPhone selected'
                        : 'iPhone: ${device.name}',
                    detail: device == null
                        ? 'Build works without one; Build & Run needs it '
                              '(Devices).'
                        : 'iOS ${device.osVersion ?? '?'} · '
                              '${device.connection.toUpperCase()}'
                              '${legacy ? ' · release/profile only (no '
                                        'debugger on iOS 15/16)' : ''}',
                  ),
                  const SizedBox(height: XSpace.s3),
                  XCommandPreview(
                    label: 'Build & Run',
                    arguments: _runCommand(settings.udid),
                    workingDirectory: project,
                  ),
                  const SizedBox(height: XSpace.s2),
                  XCommandPreview(
                    label: _ipa ? 'Build IPA' : 'Build .app',
                    arguments: _buildCommand(),
                    workingDirectory: project,
                  ),
                  const SizedBox(height: XSpace.s4),
                  Wrap(
                    spacing: XSpace.s2,
                    runSpacing: XSpace.s2,
                    children: [
                      XButton(
                        label: 'Build & Run',
                        icon: Icons.play_arrow,
                        loading: running && _job!.title.startsWith('Run'),
                        loadingLabel: 'Running…',
                        disabledReason:
                            reason ??
                            (device == null ? 'Select an iPhone first.' : null),
                        onPressed: reason != null || device == null
                            ? null
                            : () => setState(
                                () => _job = services.jobs.run(
                                  'Run (${_mode.name})',
                                  _runCommand(settings.udid),
                                  workingDirectory: project,
                                  structured: true,
                                ),
                              ),
                      ),
                      XButton(
                        label: _ipa ? 'Build IPA' : 'Build .app',
                        icon: Icons.build_outlined,
                        variant: XButtonVariant.secondary,
                        loading: running && _job!.title.startsWith('Build'),
                        loadingLabel: 'Building…',
                        disabledReason: reason,
                        onPressed: reason != null
                            ? null
                            : () => setState(
                                () => _job = services.jobs.run(
                                  'Build (${_mode.name})',
                                  _buildCommand(),
                                  workingDirectory: project,
                                  structured: true,
                                ),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_check != null)
              XCard(
                title: 'Project check',
                child: JobPanel(job: _check!, consoleHeight: 180),
              ),
            if (_job != null) _jobCard(context, _job!, legacy),
          ],
        );
      },
    );
  }

  Widget _jobCard(BuildContext context, Job job, bool legacy) {
    final services = Services.of(context);
    return ListenableBuilder(
      listenable: job,
      builder: (context, _) {
        final interactive =
            job.isRunning && job.title == 'Run (debug)' && !legacy;
        final ipa = job.status == JobStatus.succeeded
            ? (job.artifact('ipa') ?? _newestIpa())
            : null;
        final app = job.status == JobStatus.succeeded
            ? job.artifact('app')
            : null;
        final artifact = ipa ?? app;
        return XCard(
          title: job.title,
          subtitle: job.displayCommand,
          trailing: XStatusBadge(
            status: statusOf(job),
            label: switch (job.status) {
              JobStatus.running => 'Running · ${elapsedOf(job)}',
              JobStatus.succeeded => 'Completed · ${elapsedOf(job)}',
              JobStatus.failed => 'Failed (exit ${job.exitCode ?? '-'})',
              JobStatus.cancelled => 'Stopped',
            },
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (interactive) ...[
                Wrap(
                  spacing: XSpace.s2,
                  children: [
                    XButton(
                      label: 'Hot Reload (r)',
                      icon: Icons.bolt,
                      variant: XButtonVariant.secondary,
                      onPressed: () => job.send('r'),
                    ),
                    XButton(
                      label: 'Hot Restart (R)',
                      icon: Icons.restart_alt,
                      variant: XButtonVariant.secondary,
                      onPressed: () => job.send('R'),
                    ),
                  ],
                ),
                const SizedBox(height: XSpace.s3),
              ],
              if (artifact != null) ...[
                XCallout(
                  status: XStatus.ready,
                  title: 'Built ${p.basename(artifact)}',
                  children: [
                    SelectableText(artifact),
                    const SizedBox(height: XSpace.s2),
                    Wrap(
                      spacing: XSpace.s2,
                      runSpacing: XSpace.s2,
                      children: [
                        XButton(
                          label: 'Copy path',
                          icon: Icons.copy,
                          variant: XButtonVariant.text,
                          onPressed: () =>
                              Clipboard.setData(ClipboardData(text: artifact)),
                        ),
                        XButton(
                          label: 'Open folder',
                          icon: Icons.folder_outlined,
                          variant: XButtonVariant.text,
                          onPressed: () =>
                              services.launcher.openFolder(p.dirname(artifact)),
                        ),
                        if (ipa != null)
                          XButton(
                            label: 'Install ${p.basename(ipa)}',
                            icon: Icons.install_mobile,
                            onPressed: () {
                              if (widget.onInstall != null) {
                                widget.onInstall!(ipa);
                                return;
                              }
                              services.settings.update((s) => s.lastIpa = ipa);
                              services.app.go(Destination.devices);
                            },
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: XSpace.s3),
              ],
              if (GenSnapshotProblem.fromJob(job) case final problem?) ...[
                FlutterSdkFixCard(
                  problem: problem,
                  retryLabel: job.title.startsWith('Run')
                      ? 'Build & Run again'
                      : 'Build again',
                  onFixed: () => setState(
                    () => _job = services.jobs.run(
                      job.title,
                      job.command,
                      workingDirectory: job.workingDirectory,
                      structured: true,
                    ),
                  ),
                ),
                const SizedBox(height: XSpace.s3),
              ],
              JobPanel(
                job: job,
                input: job.title.startsWith('Run'),
                skipCodes: const {GenSnapshotProblem.code},
              ),
            ],
          ),
        );
      },
    );
  }
}
