import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/cli/xcross_commands.dart';
import '../../src/cli/xcross_events.dart';
import '../../src/state/job.dart';
import '../common/job_views.dart';

/// Plugins (feature 028, formerly the Plugins page): how each iOS plugin of
/// the project is built, with what it needs from the developer above.
class PluginsTab extends StatefulWidget {
  const PluginsTab({super.key});

  @override
  State<PluginsTab> createState() => _PluginsTabState();
}

class _PluginsTabState extends State<PluginsTab> {
  Job? _shim;

  /// Feature 032: the last "Prepare iOS project" run and what it reported.
  Job? _prepare;
  IosPrepareReport? _prepared;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Services.of(context).projectHealth.ensureLoaded();
    });
  }

  Future<void> _draft(String project, PluginItem plugin) async {
    final services = Services.of(context);
    final job = services.jobs.run(
      'Make buildable (${plugin.name})',
      XcrossCommands.pluginShim(plugin.name, project: project),
    );
    setState(() => _shim = job);
    await job.done;
    await services.projectHealth.refresh();
  }

  Future<void> _prepareProject(String project) async {
    final services = Services.of(context);
    IosPrepareReport? report;
    final job = services.jobs.run(
      'Prepare iOS project',
      XcrossCommands.iosPrepare(project: project),
      onEvent: (event) {
        if (event is IosPrepareReport) report = event;
      },
    );
    setState(() {
      _prepare = job;
      _prepared = null;
    });
    await job.done;
    if (!mounted) return;
    setState(() => _prepared = report);
    await services.projectHealth.refresh();
  }

  static XStatus _stepStatus(String state) => switch (state) {
    'failed' => XStatus.failed,
    'warning' => XStatus.warning,
    _ => XStatus.ready,
  };

  Widget _prepareCard(String project) {
    final running = _prepare?.isRunning ?? false;
    final report = _prepared;
    final colors = XTheme.of(context).colors;
    return XCard(
      title: 'Get this project ready for iOS',
      subtitle:
          'No pod install and no Mac needed: plugins are built as Swift '
          'packages. This runs flutter pub get, writes a draft package for '
          'each plugin that only has a podspec, and lists what a build would '
          'leave out, before the long build.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: XButton(
              label: 'Prepare iOS project',
              icon: Icons.build_circle_outlined,
              loading: running,
              loadingLabel: 'Preparing…',
              onPressed: running ? null : () => _prepareProject(project),
            ),
          ),
          if (report != null) ...[
            const SizedBox(height: XSpace.s3),
            for (final step in report.steps)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    XStatusBadge(
                      status: _stepStatus(step.state),
                      label: step.title,
                      compact: true,
                    ),
                    const SizedBox(width: XSpace.s2),
                    Expanded(
                      child: Text(
                        step.hint == null
                            ? step.detail
                            : '${step.detail} ${step.hint}',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            if (report.leftOut.isNotEmpty) ...[
              const SizedBox(height: XSpace.s2),
              XCallout(
                status: XStatus.warning,
                title:
                    'A build leaves out the native code of '
                    '${report.leftOut.map((plugin) => plugin.name).join(', ')}',
                children: [
                  for (final plugin in report.leftOut)
                    XNote('${plugin.name}: ${plugin.detail}'),
                ],
              ),
            ],
          ] else if (!running && _prepare?.status == JobStatus.failed) ...[
            const SizedBox(height: XSpace.s3),
            XCallout(
              status: XStatus.failed,
              title: 'Could not prepare the project',
              children: [JobDiagnostics(job: _prepare!, limit: 2)],
            ),
          ],
        ],
      ),
    );
  }

  /// Badge for the integration mode.
  (XStatus, String) _badge(PluginItem plugin) {
    if (plugin.needsAction) return (XStatus.warning, 'Needs action');
    return switch (plugin.kind) {
      'swiftpm' => (XStatus.ready, 'SwiftPM supported'),
      'draft' => (XStatus.ready, 'Draft override'),
      'hand_written' => (XStatus.ready, 'Your override'),
      'podspec_only' => (XStatus.warning, 'Podspec only'),
      'no_ios_code' => (XStatus.idle, 'No iOS code'),
      _ => (XStatus.idle, plugin.kind),
    };
  }

  String _explain(PluginItem plugin) => switch (plugin.kind) {
    'swiftpm' =>
      'The plugin ships a Swift package (Package.swift); xcross builds it.',
    'draft' =>
      'xcross wrote ${plugin.overridePath ?? 'xcross_overrides'}/Package.swift '
          'from the plugin\'s podspec; a build uses it.',
    'hand_written' =>
      'Your own ${plugin.overridePath ?? 'xcross_overrides'}/Package.swift; '
          'xcross never rewrites it by itself.',
    'podspec_only' =>
      'The plugin describes its iOS code only for CocoaPods, which xcross does '
          'not use. The next build drafts a Package.swift for it; "Make '
          'buildable" does it now.',
    'no_ios_code' => 'Pure Dart on iOS; nothing native to build.',
    _ => 'xcross could not tell how this plugin is built.',
  };

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([services.settings, services.projectHealth]),
      builder: (context, _) {
        final project = services.settings.projectPath;
        final health = services.projectHealth;
        final report = health.plugins;
        if (project == null) {
          return const XCard(
            child: XEmptyState(
              icon: Icons.extension_off_outlined,
              title: 'No project open',
              message: 'Open a Flutter project on Overview first.',
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _prepareCard(project), // feature 032
            const SizedBox(height: XSpace.s3),
            const XCallout(
              title: 'How plugins are built',
              children: [
                XNote(
                  'xcross builds plugins as Swift packages. A plugin that '
                  'describes its iOS code only for CocoaPods gets a draft '
                  'Package.swift in xcross_overrides/<plugin>/<version>/ (look '
                  'it over once; commit it). When a plugin is upgraded, or an '
                  'older draft misses something, it shows under "To do" above '
                  'with a button that rewrites it after copying the old files '
                  'to .xcross/plugin-backups/. A file you wrote yourself is '
                  'never rewritten without asking.',
                ),
              ],
            ),
            const SizedBox(height: XSpace.s3),
            if (report == null)
              XCard(
                child: XNote(
                  health.refreshing
                      ? 'Reading the plugins…'
                      : 'Could not read the plugins. Run "flutter pub get" in '
                            'the project, then check again.',
                ),
              )
            else
              XCard(
                title: 'Plugins',
                subtitle: project,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (report.plugins.isEmpty)
                      const XNote('This project has no iOS plugins.'),
                    for (final plugin in report.plugins)
                      Padding(
                        key: ValueKey('plugin-${plugin.name}'),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${plugin.name} ${plugin.version ?? ''}'.trim(),
                              ),
                            ),
                            Tooltip(
                              message: _explain(plugin),
                              child: XStatusBadge(
                                status: _badge(plugin).$1,
                                label: _badge(plugin).$2,
                              ),
                            ),
                            const SizedBox(width: XSpace.s2),
                            SizedBox(
                              width: 190,
                              child:
                                  plugin.kind == 'podspec_only' &&
                                      plugin.problems.isEmpty
                                  ? XButton(
                                      label: 'Make buildable',
                                      icon: Icons.auto_fix_high,
                                      variant: XButtonVariant.secondary,
                                      onPressed: () => _draft(project, plugin),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            if (_shim != null) ...[
              const SizedBox(height: XSpace.s3),
              XCard(
                title: 'Package.swift written: review the notes',
                child: JobConsole(job: _shim!, height: 200),
              ),
            ],
          ],
        );
      },
    );
  }
}
