import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/cli/xcross_commands.dart';
import '../../src/state/job.dart';
import '../common/job_views.dart';

/// One line of `xcross plugin list`: `✖ name 1.2.3  (podspec only)`.
class PluginStatus {
  const PluginStatus(this.name, this.version, this.kind);

  /// Parses a `plugin list` line, or `null` for other lines.
  static PluginStatus? tryParse(String line) {
    final match = RegExp(r'^\s*[✔✖]\s+(\S+)(?:\s+(\S+))?\s+\(([^)]+)\)\s*$')
        .firstMatch(line);
    if (match == null) return null;
    return PluginStatus(match.group(1)!, match.group(2), match.group(3)!);
  }

  final String name;
  final String? version;

  /// `swiftpm`, `podspec only`, `override` or `no iOS code`.
  final String kind;

  bool get needsOverride => kind == 'podspec only';

  /// What the badge means, for its tooltip.
  String get explanation => switch (kind) {
    'swiftpm' =>
      'The plugin ships a Swift package (Package.swift); xcross builds it.',
    'override' =>
      'Your project has xcross_overrides/$name/…/Package.swift; xcross '
          'builds the plugin from it.',
    'podspec only' =>
      'The plugin describes its iOS code only for CocoaPods, which xcross '
          'does not use. Without an override its iOS part is left out and '
          'the app fails when it calls the plugin.',
    'no iOS code' => 'Pure Dart on iOS; nothing native to build.',
    _ => 'xcross could not tell how this plugin is built.',
  };

  /// Badge for the integration mode (§6.6).
  (XStatus, String) get badge => switch (kind) {
    'swiftpm' => (XStatus.ready, 'SwiftPM supported'),
    'override' => (XStatus.ready, 'Override active'),
    'podspec only' => (XStatus.warning, 'Podspec only'),
    _ => (XStatus.idle, kind == 'no iOS code' ? 'No iOS code' : 'Unknown'),
  };
}

/// Plugins (§6.6): native iOS plugin compatibility before a build fails.
class PluginsPage extends StatefulWidget {
  const PluginsPage({super.key});

  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  Job? _list;
  Job? _shim;
  List<PluginStatus> _plugins = const [];

  Future<void> _check(String project) async {
    final job = Services.of(context).jobs
        .run('Plugins', XcrossCommands.pluginList(project));
    setState(() => _list = job);
    await job.done;
    if (!mounted) return;
    setState(
      () => _plugins = [
        for (final line in job.lines) ?PluginStatus.tryParse(line.text),
      ],
    );
  }

  Future<void> _draft(String project, PluginStatus plugin) async {
    final job = Services.of(context).jobs.run(
      'Make buildable (${plugin.name})',
      XcrossCommands.pluginShim(plugin.name, project: project),
    );
    setState(() => _shim = job);
    await job.done;
    if (mounted) await _check(project);
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return ListenableBuilder(
      listenable: services.settings,
      builder: (context, _) {
        final project = services.settings.projectPath;
        final running =
            (_list?.isRunning ?? false) || (_shim?.isRunning ?? false);
        return WorkspaceLayout(
          title: 'Plugins',
          subtitle: 'How each iOS plugin of the project is built.',
          actions: [
            XButton(
              label: 'Check plugins',
              icon: Icons.extension_outlined,
              loading: _list?.isRunning ?? false,
              loadingLabel: 'Checking…',
              disabledReason: 'Open a Flutter project first.',
              onPressed: project == null || running
                  ? null
                  : () => _check(project),
            ),
          ],
          children: [
            const XCallout(
              title: 'Plugins marked "Podspec only"',
              children: [
                XNote(
                  'xcross builds plugins as Swift packages. Some plugins '
                  'describe their iOS code only for CocoaPods, which xcross '
                  'does not use, so their iOS part would be left out and the '
                  'app fails when it calls them. "Make buildable" writes a '
                  'Swift package recipe for the plugin (from its podspec) '
                  'into your project at '
                  'xcross_overrides/<plugin>/<version>/Package.swift; the '
                  'next build uses it. Read the notes it prints. Your pub '
                  'cache is never changed; delete the folder to undo.',
                ),
              ],
            ),
            if (project == null)
              const XCard(
                child: XEmptyState(
                  icon: Icons.extension_off_outlined,
                  title: 'No project open',
                  message: 'Open a Flutter project on Overview first.',
                ),
              )
            else if (_list == null)
              const XCard(
                child: XNote(
                  'Check plugins to list them (xcross plugin list).',
                ),
              )
            else
              XCard(
                title: 'Plugins',
                subtitle: project,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_plugins.isEmpty && !_list!.isRunning) ...[
                      JobDiagnostics(job: _list!),
                      for (final line in _list!.lines.skip(1)) Text(line.text),
                    ],
                    for (final plugin in _plugins)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${plugin.name} ${plugin.version ?? ''}'.trim(),
                              ),
                            ),
                            Tooltip(
                              message: plugin.explanation,
                              child: XStatusBadge(
                                status: plugin.badge.$1,
                                label: plugin.badge.$2,
                              ),
                            ),
                            const SizedBox(width: XSpace.s2),
                            SizedBox(
                              width: 190,
                              child: plugin.needsOverride
                                  ? Tooltip(
                                      message:
                                          'Writes xcross_overrides/'
                                          '${plugin.name}/'
                                          '${plugin.version ?? '<version>'}/'
                                          "Package.swift from the plugin's "
                                          'podspec so xcross can build it.',
                                      child: XButton(
                                        label: 'Make buildable',
                                        icon: Icons.auto_fix_high,
                                        variant: XButtonVariant.secondary,
                                        onPressed: running
                                            ? null
                                            : () => _draft(project, plugin),
                                      ),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            if (_shim != null)
              XCard(
                title: 'Package.swift written: review the notes',
                child: JobConsole(job: _shim!, height: 200),
              ),
          ],
        );
      },
    );
  }
}
