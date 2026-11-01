import 'package:flutter/material.dart';

import '../cli/output_line.dart';
import '../cli/xcross_commands.dart';
import '../state/job.dart';
import 'services.dart';
import 'widgets.dart';

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
}

/// Project page section: how each iOS plugin is built, and a button that
/// drafts a Package.swift override for podspec-only plugins.
class PluginsSection extends StatefulWidget {
  const PluginsSection({super.key, required this.project});

  final String? project;

  @override
  State<PluginsSection> createState() => _PluginsSectionState();
}

class _PluginsSectionState extends State<PluginsSection> {
  Job? _list;
  Job? _shim;
  List<PluginStatus> _plugins = const [];

  Future<void> _check() async {
    final project = widget.project;
    if (project == null) return;
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

  Future<void> _draft(PluginStatus plugin) async {
    final project = widget.project;
    if (project == null) return;
    final job = Services.of(context).jobs.run(
      'Draft override (${plugin.name})',
      XcrossCommands.pluginShim(plugin.name, project: project),
    );
    setState(() => _shim = job);
    await job.done;
    if (mounted) await _check();
  }

  @override
  Widget build(BuildContext context) {
    final running = (_list?.isRunning ?? false) || (_shim?.isRunning ?? false);
    return Section(
      title: 'Plugins',
      trailing: OutlinedButton.icon(
        onPressed: widget.project == null || running ? null : _check,
        icon: const Icon(Icons.extension),
        label: const Text('Check plugins'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_list == null)
            const Text(
              'Shows which plugins build as Swift packages. Plugins that only '
              'ship a CocoaPods podspec need a Package.swift override.',
            ),
          for (final plugin in _plugins)
            Row(
              children: [
                Expanded(
                  child: CheckRow(
                    ok: !plugin.needsOverride,
                    label: plugin.name,
                    detail: '${plugin.version ?? ''}  ${plugin.kind}'.trim(),
                  ),
                ),
                if (plugin.needsOverride)
                  TextButton.icon(
                    onPressed: running ? null : () => _draft(plugin),
                    icon: const Icon(Icons.auto_fix_high, size: 18),
                    label: const Text('Draft override'),
                  ),
              ],
            ),
          if (_list != null && _plugins.isEmpty && !_list!.isRunning)
            for (final line in _list!.lines.where(
              (l) => l.kind != LineKind.command,
            ))
              Text(line.text),
          if (_shim != null) ...[
            const SizedBox(height: 8),
            JobOutputView(job: _shim!, height: 180, showInput: false),
          ],
        ],
      ),
    );
  }
}
