import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/app_controller.dart';
import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/product.dart';
import '../../src/state/job.dart';
import '../../src/state/project_info.dart';
import '../../src/state/readiness.dart';
import '../common/attention_widgets.dart';
import '../common/flutter_sdk_fix.dart';
import '../common/job_views.dart';
import '../common/readiness_views.dart';

/// Overview (§6.1): "Am I ready to build, and what should I do next?"
class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key});

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  ProjectInfo? _info;
  String? _loadedFor;

  Future<void> _load(String? path) async {
    _loadedFor = path;
    if (path == null) {
      setState(() => _info = null);
      return;
    }
    final info = await ProjectInfo.read(path);
    if (mounted && _loadedFor == path) setState(() => _info = info);
  }

  Future<void> _openProject() async {
    final services = Services.of(context);
    final path = await getDirectoryPath(
      initialDirectory: services.settings.projectPath,
    );
    if (path != null) {
      await services.settings.update((s) => s.projectPath = path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final settings = services.settings;
    final readiness = services.readiness;
    return ListenableBuilder(
      listenable: Listenable.merge([
        settings,
        readiness,
        services.jobs,
        services.devices,
      ]),
      builder: (context, _) {
        if (_loadedFor != settings.projectPath) _load(settings.projectPath);
        final info = _info;
        final builds = [
          for (final job in services.jobs.jobs.reversed)
            if (job.title.startsWith('Build') || job.title.startsWith('Run'))
              job,
        ];
        return WorkspaceLayout(
          title: 'Overview',
          subtitle: 'Build for iOS. Anywhere.',
          actions: [
            XButton(
              label: 'Run checks',
              icon: Icons.health_and_safety_outlined,
              variant: XButtonVariant.secondary,
              loading: readiness.checking,
              loadingLabel: 'Checking…',
              onPressed: readiness.runDoctor,
            ),
            XButton(
              label: 'Setup wizard',
              icon: Icons.auto_awesome_outlined,
              variant: XButtonVariant.text,
              onPressed: () => services.app.openWizard?.call(),
            ),
          ],
          children: [
            _nextStep(context, info),
            const AttentionList(title: 'Needs your attention'),
            if (settings.projectPath == null)
              XCard(
                child: XEmptyState(
                  icon: Icons.folder_open,
                  title: 'No Flutter project open',
                  message:
                      'Open the folder of a Flutter app (it has pubspec.yaml '
                      'and an ios/ folder). $productName builds it for '
                      'iPhone from this computer.',
                  action: XButton(
                    label: 'Open Flutter Project',
                    icon: Icons.folder_open,
                    onPressed: _openProject,
                  ),
                ),
              )
            else
              _projectCard(context, info),
            const XSectionTitle('Readiness'),
            Wrap(
              spacing: XSpace.s3,
              runSpacing: XSpace.s3,
              children: [
                for (final area in ReadinessArea.values)
                  // Push only for a project the doctor found push checks in.
                  if (area != ReadinessArea.push ||
                      readiness.area(area).checks.isNotEmpty)
                    Builder(
                      builder: (context) {
                        final health = readiness.area(area);
                        return XToolchainCard(
                          title: areaTitle(area),
                          state: toolchainStateOf(health.health),
                          message: health.health == Health.unknown
                              ? 'Run checks to find out.'
                              : health.message,
                        );
                      },
                    ),
              ],
            ),
            if (_compilerProblem(readiness) case final problem?) ...[
              const SizedBox(height: XSpace.s3),
              FlutterSdkFixCard(
                problem: problem,
                retryLabel: 'Check again',
                onFixed: readiness.runDoctor,
              ),
            ],
            _deviceSummary(context),
            const XSectionTitle('Recent builds'),
            if (builds.isEmpty)
              const XNote('No builds yet in this session.')
            else
              for (final job in builds.take(5)) _buildRow(context, job),
          ],
        );
      },
    );
  }

  /// The missing iOS compiler, when the latest doctor run reported it.
  GenSnapshotProblem? _compilerProblem(ReadinessController readiness) {
    for (final check in readiness.area(ReadinessArea.iosCompiler).checks) {
      if (GenSnapshotProblem.fromCheck(check) case final problem?) {
        return problem;
      }
    }
    return null;
  }

  /// The one recommended action (§6.1): Open Project, Fix Setup or Build.
  Widget _nextStep(BuildContext context, ProjectInfo? info) {
    final services = Services.of(context);
    final readiness = services.readiness;
    final (String title, String message, Widget action) = readiness.needsSetup
        ? (
            'Fix setup',
            'Some prerequisites failed their checks, so nothing can be built '
                'yet. The setup wizard walks you through them.',
            XButton(
              label: 'Fix Setup',
              icon: Icons.build_circle_outlined,
              onPressed: () => services.app.openWizard?.call(),
            ),
          )
        : services.settings.projectPath == null
        ? (
            'Open a Flutter project',
            'Pick the app you want to build for iPhone.',
            XButton(
              label: 'Open Project',
              icon: Icons.folder_open,
              onPressed: _openProject,
            ),
          )
        : (
            'Ready when you are',
            readiness.checks.isEmpty
                ? 'Run the checks, or go straight to Build & Run.'
                : 'The checks passed. Build and run your app on the iPhone.',
            XButton(
              label: 'Build & Run',
              icon: Icons.play_arrow,
              onPressed: () => services.app.go(Destination.build),
            ),
          );
    return XCard(
      variant: XCardVariant.elevated,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Next step',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: XSpace.s1),
                XNote(message),
              ],
            ),
          ),
          action,
        ],
      ),
    );
  }

  Widget _projectCard(BuildContext context, ProjectInfo? info) {
    final services = Services.of(context);
    if (info == null) {
      return const XCard(child: XNote('Reading the project…'));
    }
    if (!info.isFlutterProject) {
      return XCard(
        title: p.basename(info.path),
        subtitle: info.path,
        trailing: XButton(
          label: 'Choose another',
          variant: XButtonVariant.secondary,
          onPressed: _openProject,
        ),
        child: const XCheckRow(
          status: XStatus.failed,
          label: 'Not a Flutter project with an ios/ folder',
        ),
      );
    }
    final push = info.entitlements.contains('aps-environment');
    final domains = info.entitlements.contains(
      'com.apple.developer.associated-domains',
    );
    return XCard(
      title: info.name ?? p.basename(info.path),
      subtitle: info.path,
      trailing: XButton(
        label: 'Change',
        variant: XButtonVariant.text,
        onPressed: _openProject,
      ),
      child: Wrap(
        spacing: XSpace.s6,
        runSpacing: XSpace.s1,
        children: [
          XCheckRow(
            status: XStatus.ready,
            label: 'Version',
            detail: info.version ?? '-',
          ),
          XCheckRow(
            status: info.bundleId == null ? XStatus.failed : XStatus.ready,
            label: 'Bundle ID',
            detail: info.bundleId ?? 'not found in project.pbxproj',
          ),
          XCheckRow(
            status: push ? XStatus.ready : XStatus.idle,
            label: 'Push',
            detail: push ? 'aps-environment declared' : 'not declared',
          ),
          XCheckRow(
            status: domains ? XStatus.ready : XStatus.idle,
            label: 'Associated domains',
          ),
          XCheckRow(
            status: info.hasAppIcon ? XStatus.ready : XStatus.warning,
            label: 'App icon',
          ),
          XCheckRow(
            status: info.hasLaunchScreen ? XStatus.ready : XStatus.warning,
            label: 'Launch screen',
          ),
          if (Directory(info.outputDirectory).existsSync())
            TextButton.icon(
              onPressed: () =>
                  services.launcher.openFolder(info.outputDirectory),
              icon: const Icon(Icons.folder_outlined, size: 16),
              label: const Text('Open build output'),
            ),
        ],
      ),
    );
  }

  Widget _deviceSummary(BuildContext context) {
    final services = Services.of(context);
    final devices = services.devices;
    final device = devices.selected;
    return XCard(
      title: 'iPhone',
      trailing: XButton(
        label: 'Devices',
        variant: XButtonVariant.text,
        onPressed: () => services.app.go(Destination.devices),
      ),
      child: device == null
          ? XNote(
              devices.devices == null
                  ? 'Looking for iPhones…'
                  : 'No iPhone selected. Connect it by USB, unlock it and '
                        'tap Trust.',
            )
          : XCheckRow(
              status: XStatus.ready,
              label: device.name,
              detail:
                  'iOS ${device.osVersion ?? '?'} · '
                  '${device.connection.toUpperCase()}'
                  '${device.legacy ? ' · release/profile only' : ''}',
            ),
    );
  }

  Widget _buildRow(BuildContext context, Job job) {
    final services = Services.of(context);
    final artifact = job.artifact('ipa') ?? job.artifact('app');
    return Padding(
      padding: const EdgeInsets.only(bottom: XSpace.s2),
      child: XCard(
        onTap: () => services.app.showJob(job),
        padding: const EdgeInsets.symmetric(
          horizontal: XSpace.s4,
          vertical: XSpace.s3,
        ),
        child: Row(
          children: [
            XStatusBadge(status: statusOf(job)),
            const SizedBox(width: XSpace.s3),
            Expanded(
              child: Text(
                '${job.title} · ${elapsedOf(job)}'
                '${artifact == null ? '' : '  →  $artifact'}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
