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
