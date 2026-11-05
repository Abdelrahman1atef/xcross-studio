import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/cli/xcross_commands.dart';
import '../../src/cli/xcross_events.dart';
import '../../src/state/job.dart';
import '../common/job_views.dart';

/// Capabilities (feature 027): the switches of Xcode's "Signing &
/// Capabilities" tab, written to the entitlements file (and Info.plist for
/// background modes).
class CapabilitiesTab extends StatefulWidget {
  const CapabilitiesTab({super.key});

  @override
  State<CapabilitiesTab> createState() => _CapabilitiesTabState();
}

class _CapabilitiesTabState extends State<CapabilitiesTab> {
  CapabilitiesReport? _report;
  bool _busy = false;
  List<String> _notes = const [];
  Job? _failed;
  String? _loadedFor;

  Future<void> _run(String title, List<String> command) async {
    final services = Services.of(context);
    final project = services.settings.projectPath;
    if (project == null) return;
    setState(() {
      _busy = true;
      _failed = null;
      if (command.length > 1 && command[1] != 'list') _notes = const [];
    });
    final (job, events) = await services.jobs.collect(
      title,
      command,
      workingDirectory: project,
    );
    if (!mounted) return;
    final report = events.whereType<CapabilitiesReport>().firstOrNull;
    final change = events.whereType<ProjectChange>().firstOrNull;
    setState(() {
      _busy = false;
      if (report != null) _report = report;
      // The list read that follows a change must not erase its notes.
      if (change != null) _notes = change.notes;
      if (job.status == JobStatus.failed) _failed = job;
    });
    if (change != null) await _load();
  }

  Future<void> _load() =>
      _run('Capabilities', XcrossCommands.capabilitiesList());

  void _ensureLoaded(String? project) {
    if (project == _loadedFor) return;
    _loadedFor = project;
    if (project != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return ListenableBuilder(
      listenable: services.settings,
      builder: (context, _) {
        final project = services.settings.projectPath;
        _ensureLoaded(project);
        final report = _report;
        if (project == null) {
          return const XCard(
            child: XEmptyState(
              icon: Icons.verified_outlined,
              title: 'No project open',
              message: 'Open a Flutter project on Overview first.',
            ),
          );
        }
        if (report == null) {
          return XCard(
            child: _failed == null
                ? const XNote('Reading the capabilities…')
                : JobPanel(job: _failed!, consoleHeight: 140),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            XCard(
              title: 'Capabilities',
              subtitle:
                  '${report.entitlementsPath}'
                  '${report.entitlementsExist ? '' : ' (made when you turn one on)'}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const XNote(
                    'A capability goes into the entitlements file; xcross '
                    'switches it on for the App ID when it signs. Push and '
                    'background modes also need their key in Info.plist, which '
                    'Background Modes below writes.',
                  ),
                  if (report.entitlementsExist && !report.xcodeKnowsFile) ...[
                    const SizedBox(height: XSpace.s2),
                    const XNote(
                      'Xcode does not know this entitlements file yet (the '
                      'Runner target has no CODE_SIGN_ENTITLEMENTS). xcross '
                      'builds use it as it is.',
                    ),
                  ],
                  const SizedBox(height: XSpace.s3),
                  for (final item in report.capabilities)
                    Padding(
                      padding: const EdgeInsets.only(bottom: XSpace.s3),
                      child: _CapabilityRow(
                        key: ValueKey('capability-${item.id}'),
                        item: item,
                        busy: _busy,
                        onAdd: (values) => _run(
                          'Turn on ${item.name}',
                          XcrossCommands.capabilityAdd(item.id, values),
                        ),
                        onRemove: ([values = const []]) => _run(
                          'Turn off ${item.name}',
                          XcrossCommands.capabilityRemove(item.id, values),
                        ),
                      ),
                    ),
                  for (final key in report.unknownEntitlements)
                    Text('Also in the file (not managed here): $key'),
                ],
              ),
            ),
            if (_notes.isNotEmpty) ...[
              const SizedBox(height: XSpace.s3),
              XCallout(
                title: 'Good to know',
                children: [for (final note in _notes) XNote(note)],
              ),
            ],
            if (_failed != null) ...[
              const SizedBox(height: XSpace.s3),
              JobPanel(job: _failed!, consoleHeight: 140),
            ],
          ],
        );
      },
    );
  }
}

class _CapabilityRow extends StatefulWidget {
  const _CapabilityRow({
    super.key,
    required this.item,
    required this.busy,
    required this.onAdd,
    required this.onRemove,
  });

  final CapabilityItem item;
  final bool busy;
  final void Function(List<String> values) onAdd;
  final void Function([List<String> values]) onRemove;

  @override
  State<_CapabilityRow> createState() => _CapabilityRowState();
}

class _CapabilityRowState extends State<_CapabilityRow> {
  final _value = TextEditingController();

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    final item = widget.item;
    // A list with a fixed set of values (background modes) is chips; a list
    // of things the developer names (domains, groups) is an input.
    final choiceList = item.kind == 'list' && item.choices.isNotEmpty;
    final namedList =
        item.kind == 'list' && item.choices.isEmpty && item.example != null;
    final Widget control;
    if (choiceList) {
      control = Wrap(
        spacing: XSpace.s2,
        runSpacing: XSpace.s1,
        children: [
          for (final choice in item.choices)
            FilterChip(
              key: ValueKey('mode-$choice'),
              label: Text(choice),
              selected: item.values.contains(choice),
              onSelected: widget.busy
                  ? null
                  : (on) =>
                        on ? widget.onAdd([choice]) : widget.onRemove([choice]),
            ),
        ],
      );
    } else if (namedList) {
      control = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (item.values.isNotEmpty)
            Wrap(
              spacing: XSpace.s2,
              children: [
                for (final value in item.values)
                  InputChip(
                    label: Text(value),
                    onDeleted: widget.busy
                        ? null
                        : () => widget.onRemove([value]),
                  ),
              ],
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _value,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    hintText: 'for example ${item.example}',
                  ),
                ),
              ),
              const SizedBox(width: XSpace.s2),
              XButton(
                label: 'Add',
                icon: Icons.add,
                onPressed: widget.busy || _value.text.trim().isEmpty
                    ? null
                    : () {
                        widget.onAdd([_value.text.trim()]);
                        _value.clear();
                      },
              ),
            ],
          ),
        ],
      );
    } else if (item.kind == 'choice') {
      control = Row(
        children: [
          Switch(
            value: item.enabled,
            onChanged: widget.busy
                ? null
                : (on) => on ? widget.onAdd(const []) : widget.onRemove(),
          ),
          if (item.enabled)
            DropdownButton<String>(
              value: item.choices.contains(item.value) ? '${item.value}' : null,
              items: [
                for (final choice in item.choices)
                  DropdownMenuItem(value: choice, child: Text(choice)),
              ],
              onChanged: widget.busy
                  ? null
                  : (choice) => choice == null ? null : widget.onAdd([choice]),
            ),
        ],
      );
    } else {
      control = Align(
        alignment: Alignment.centerLeft,
        child: Switch(
          value: item.enabled,
          onChanged: widget.busy
              ? null
              : (on) => on ? widget.onAdd(const []) : widget.onRemove(),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              item.name,
              style: XType.body.copyWith(
                color: c.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: XSpace.s2),
            if (item.enabled)
              const XStatusBadge(status: XStatus.ready, label: 'On'),
            const Spacer(),
            if (item.ascCapability != null)
              Tooltip(
                message:
                    'The App ID needs ${item.ascCapability}; xcross switches '
                    'it on when it signs.',
                child: Text(
                  item.ascCapability!,
                  style: XType.mono.copyWith(color: c.textSecondary),
                ),
              ),
          ],
        ),
        Text(
          item.description,
          style: XType.support.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: XSpace.s1),
        control,
      ],
    );
  }
}
