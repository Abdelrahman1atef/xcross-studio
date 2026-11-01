import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../cli/xcross_commands.dart';
import '../state/job.dart';
import '../state/project_info.dart';
import 'plugins_section.dart';
import 'services.dart';
import 'widgets.dart';

/// Project & Build: open a Flutter project, check it, build an IPA.
class ProjectPage extends StatefulWidget {
  const ProjectPage({super.key, this.onInstall});

  /// Called with a built `.ipa` when the user wants to install it.
  final ValueChanged<String>? onInstall;

  @override
  State<ProjectPage> createState() => _ProjectPageState();
}

class _ProjectPageState extends State<ProjectPage> {
  ProjectInfo? _info;
  Job? _check;
  Job? _build;
  BuildMode _mode = BuildMode.release;
  bool _ipa = true;
  final _buildName = TextEditingController();
  final _buildNumber = TextEditingController();
  String? _loadedFor;

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

  String? _builtIpa() {
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

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final settings = services.settings;
    return Watch(
      listenable: settings,
      builder: (context) {
        if (_loadedFor != settings.projectPath) _load(settings.projectPath);
        final info = _info;
        final project = settings.projectPath;
        final ready = info?.isFlutterProject ?? false;
        // studio: 012 — the `artifact` event names the IPA; older CLIs fall
        // back to the newest .ipa in the output folder.
        final ipa = _build?.status == JobStatus.succeeded
            ? (_build!.artifact('ipa') ?? _builtIpa())
            : null;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Section(
              title: 'Flutter project',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PathField(
                    label: 'Project folder',
                    value: project,
                    onChanged: (path) =>
                        settings.update((s) => s.projectPath = path),
                  ),
                  if (info != null) ...[
                    const SizedBox(height: 12),
                    if (!info.isFlutterProject)
                      const CheckRow(
                        ok: false,
                        label: 'Not a Flutter project with an ios/ folder',
                      )
                    else ...[
                      CheckRow(
                        ok: true,
                        label: info.name ?? p.basename(info.path),
                        detail: 'version ${info.version ?? '-'}',
                      ),
                      CheckRow(
                        ok: info.bundleId != null,
                        label: 'Bundle ID',
                        detail: info.bundleId ?? 'not found in project.pbxproj',
                      ),
                      CheckRow(
                        ok: info.entitlements.contains('aps-environment')
                            ? true
                            : null,
                        label: 'Push notifications',
                        detail: info.entitlements.contains('aps-environment')
                            ? 'aps-environment declared'
                            : 'not declared in Runner.entitlements',
                      ),
                      CheckRow(
                        ok:
                            info.entitlements.contains(
                              'com.apple.developer.associated-domains',
                            )
                            ? true
                            : null,
                        label: 'Associated domains (universal links)',
                      ),
                      CheckRow(ok: info.hasAppIcon, label: 'App icon set'),
                      CheckRow(
                        ok: info.hasLaunchScreen,
                        label: 'Launch screen storyboard',
                      ),
                    ],
                  ],
                ],
              ),
            ),
            PluginsSection(project: ready ? project : null),
            Section(
              title: 'Check the project',
              trailing: OutlinedButton.icon(
                onPressed: !ready || (_check?.isRunning ?? false)
                    ? null
                    : () => setState(
                        () => _check = services.jobs.run(
                          'Flutter doctor',
                          XcrossCommands.flutterDoctor(),
                          workingDirectory: project,
                          structured: true,
                        ),
                      ),
                icon: const Icon(Icons.fact_check),
                label: const Text('Check'),
              ),
              child: _check == null
                  ? const Text(
                      'Lists plugins that cannot be built (CocoaPods-only), '
                      'missing SDK pieces and signing problems, without '
                      'building.',
                    )
                  : JobOutputView(job: _check!, showInput: false),
            ),
            Section(
              title: 'Build',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SegmentedButton<BuildMode>(
                        segments: const [
                          ButtonSegment(
                            value: BuildMode.debug,
                            label: Text('Debug'),
                          ),
                          ButtonSegment(
                            value: BuildMode.profile,
                            label: Text('Profile'),
                          ),
                          ButtonSegment(
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
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: _buildName,
                          decoration: const InputDecoration(
                            labelText: 'Version (optional)',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: TextField(
                          controller: _buildNumber,
                          decoration: const InputDecoration(
                            labelText: 'Build no. (optional)',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: !ready || (_build?.isRunning ?? false)
                            ? null
                            : () => setState(
                                () => _build = services.jobs.run(
                                  'Build (${_mode.name})',
                                  XcrossCommands.build(
                                    mode: _mode,
                                    ipa: _ipa,
                                    buildName: _buildName.text,
                                    buildNumber: _buildNumber.text,
                                  ),
                                  workingDirectory: project,
                                  structured: true,
                                ),
                              ),
                        icon: const Icon(Icons.build),
                        label: const Text('Build'),
                      ),
                      const SizedBox(width: 8),
                      if (info != null && info.isFlutterProject)
                        OutlinedButton.icon(
                          onPressed:
                              Directory(info.outputDirectory).existsSync()
                              ? () => services.launcher.openFolder(
                                  info.outputDirectory,
                                )
                              : null,
                          icon: const Icon(Icons.folder),
                          label: const Text('Open output folder'),
                        ),
                      const SizedBox(width: 8),
                      if (ipa != null)
                        FilledButton.tonalIcon(
                          onPressed: () => widget.onInstall?.call(ipa),
                          icon: const Icon(Icons.install_mobile),
                          label: Text('Install ${p.basename(ipa)}'),
                        ),
                    ],
                  ),
                  if (_build != null) ...[
                    const SizedBox(height: 12),
                    JobOutputView(job: _build!, height: 360),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
