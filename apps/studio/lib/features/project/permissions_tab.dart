import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/cli/xcross_commands.dart';
import '../../src/cli/xcross_events.dart';
import '../../src/state/job.dart';
import '../common/job_views.dart';

/// Permissions (feature 027): the purpose strings of `Info.plist`, like
/// Xcode's "Privacy - … Usage Description" rows: see, add, change, remove.
class PermissionsTab extends StatefulWidget {
  const PermissionsTab({super.key});

  @override
  State<PermissionsTab> createState() => _PermissionsTabState();
}

class _PermissionsTabState extends State<PermissionsTab> {
  bool _busy = false;
  String? _message;
  Job? _failed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Services.of(context).projectHealth.ensureLoaded();
    });
  }

  /// Runs one permissions command in the project and reads the project again.
  Future<void> _apply(String title, List<String> command) async {
    final services = Services.of(context);
    final project = services.settings.projectPath;
    if (project == null || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _failed = null;
    });
    final (job, events) = await services.jobs.collect(
      title,
      command,
      workingDirectory: project,
    );
    await services.projectHealth.refresh();
    if (!mounted) return;
    final change = events.whereType<ProjectChange>().firstOrNull;
    setState(() {
      _busy = false;
      if (job.status == JobStatus.failed || change == null) {
        _failed = job;
      } else {
        _message = change.changed
            ? '${change.action == 'remove' ? 'Removed' : 'Saved'} '
                  '${change.target}.'
                  '${change.backup == null ? '' : ' The old file is kept in '
                            '${change.backup}.'}'
            : 'Nothing changed: ${change.target} was already like that.';
      }
    });
  }

  Future<void> _add(PermissionsReport report) async {
    final picked = await showDialog<(String, String)>(
      context: context,
      builder: (context) => _AddPermissionDialog(
        catalog: report.catalog,
        taken: {for (final item in report.permissions) item.key},
      ),
    );
    if (picked == null || !mounted) return;
    await _apply(
      'Add ${picked.$1}',
      XcrossCommands.permissionSet(picked.$1, picked.$2),
    );
  }

  Future<void> _remove(PermissionItem item) async {
    final confirmed = await showXConfirmDialog(
      context,
      title: 'Remove ${item.name}?',
      message:
          '${item.key} is taken out of ios/Runner/Info.plist. An app that '
          'still uses it is ended by iOS when it asks. The old file is kept '
          'in .xcross/permission-backups/.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _apply(
      'Remove ${item.key}',
      XcrossCommands.permissionRemove(item.key),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([services.settings, services.projectHealth]),
      builder: (context, _) {
        final project = services.settings.projectPath;
        final health = services.projectHealth;
        final report = health.permissions;
        if (project == null) {
          return const XCard(
            child: XEmptyState(
              icon: Icons.privacy_tip_outlined,
              title: 'No project open',
              message: 'Open a Flutter project on Overview first.',
            ),
          );
        }
        if (report == null) {
          return XCard(
            child: XNote(
              health.refreshing
                  ? 'Reading ios/Runner/Info.plist…'
                  : 'Could not read ios/Runner/Info.plist. Open a Flutter '
                        'project that has an ios folder, then check again.',
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            XCard(
              title: 'Permissions',
              subtitle:
                  'ios/Runner/Info.plist · what iOS shows when the app asks',
              trailing: XButton(
                label: 'Add permission',
                icon: Icons.add,
                loading: _busy,
                loadingLabel: 'Working…',
                onPressed: _busy ? null : () => _add(report),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const XNote(
                    'iOS asks the user with the sentence you write here. App '
                    'Review rejects an empty or placeholder sentence, and an '
                    'app that asks without one is ended by iOS.',
                  ),
                  const SizedBox(height: XSpace.s3),
                  if (report.permissions.isEmpty)
                    const XNote('No permission is set yet.'),
                  for (final item in report.permissions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: XSpace.s3),
                      child: _PermissionRow(
                        key: ValueKey('permission-${item.key}'),
                        item: item,
                        busy: _busy,
                        onSave: (sentence) => _apply(
                          'Save ${item.key}',
                          XcrossCommands.permissionSet(item.key, sentence),
                        ),
                        onRemove: () => _remove(item),
                      ),
                    ),
                ],
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: XSpace.s3),
              XCallout(
                status: XStatus.ready,
                title: _message!,
                children: const [],
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

/// One purpose string: its name, the sentence, Save and Remove.
class _PermissionRow extends StatefulWidget {
  const _PermissionRow({
    super.key,
    required this.item,
    required this.busy,
    required this.onSave,
    required this.onRemove,
  });

  final PermissionItem item;
  final bool busy;
  final ValueChanged<String> onSave;
  final VoidCallback onRemove;

  @override
  State<_PermissionRow> createState() => _PermissionRowState();
}

class _PermissionRowState extends State<_PermissionRow> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.item.value,
  );

  @override
  void didUpdateWidget(_PermissionRow old) {
    super.didUpdateWidget(old);
    // The file changed under the row (saved, or edited elsewhere): show it,
    // unless the user is in the middle of typing something else.
    if (old.item.value != widget.item.value &&
        _controller.text == old.item.value) {
      _controller.text = widget.item.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    final item = widget.item;
    final changed =
        _controller.text.trim() != item.value &&
        _controller.text.trim().isNotEmpty;
    final (status, label) = switch (item.status) {
      'placeholder' => (XStatus.warning, 'Needs a real sentence'),
      'unknown_key' => (XStatus.idle, 'Not in the catalog'),
      _ => (XStatus.ready, 'Set'),
    };
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
            Flexible(
              child: Text(
                item.key,
                overflow: TextOverflow.ellipsis,
                style: XType.mono.copyWith(color: c.textSecondary),
              ),
            ),
            const Spacer(),
            XStatusBadge(status: status, label: label),
          ],
        ),
        if (item.neededBy.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Used by ${item.neededBy.join(', ')}',
              style: XType.support.copyWith(color: c.textSecondary),
            ),
          ),
        const SizedBox(height: XSpace.s2),
        TextField(
          controller: _controller,
          minLines: 1,
          maxLines: 3,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: item.description ?? 'Why the app needs this',
          ),
        ),
        const SizedBox(height: XSpace.s2),
        Row(
          children: [
            XButton(
              label: 'Save',
              icon: Icons.check,
              disabledReason: 'Change the sentence first.',
              onPressed: changed && !widget.busy
                  ? () => widget.onSave(_controller.text.trim())
                  : null,
            ),
            const SizedBox(width: XSpace.s2),
            XButton(
              label: 'Remove',
              icon: Icons.delete_outline,
              variant: XButtonVariant.text,
              onPressed: widget.busy ? null : widget.onRemove,
            ),
          ],
        ),
      ],
    );
  }
}

/// Pick a permission from the catalog and write its sentence.
class _AddPermissionDialog extends StatefulWidget {
  const _AddPermissionDialog({required this.catalog, required this.taken});

  final List<PermissionCatalogItem> catalog;
  final Set<String> taken;

  @override
  State<_AddPermissionDialog> createState() => _AddPermissionDialogState();
}

class _AddPermissionDialogState extends State<_AddPermissionDialog> {
  final _filter = TextEditingController();
  final _sentence = TextEditingController();
  PermissionCatalogItem? _selected;

  @override
  void dispose() {
    _filter.dispose();
    _sentence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _filter.text.trim().toLowerCase();
    final options = [
      for (final item in widget.catalog)
        if (!widget.taken.contains(item.key) &&
            (query.isEmpty ||
                item.name.toLowerCase().contains(query) ||
                item.key.toLowerCase().contains(query)))
          item,
    ];
    return AlertDialog(
      title: const Text('Add a permission'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('permission-filter'),
              controller: _filter,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                hintText: 'Search: camera, location, microphone…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: XSpace.s2),
            SizedBox(
              height: 220,
              child: ListView(
                children: [
                  for (final item in options)
                    ListTile(
                      key: ValueKey('catalog-${item.key}'),
                      dense: true,
                      selected: _selected?.key == item.key,
                      title: Text(item.name),
                      subtitle: Text(item.description),
                      onTap: () => setState(() {
                        _selected = item;
                        _sentence.text = item.suggestion;
                      }),
                    ),
                  if (options.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(XSpace.s3),
                      child: Text('Nothing matches, or all are set.'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: XSpace.s2),
            TextField(
              key: const ValueKey('permission-sentence'),
              controller: _sentence,
              enabled: _selected != null,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: _selected == null
                    ? 'Pick a permission first'
                    : 'What iOS shows for ${_selected!.name} (write your own reason)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('permission-add'),
          onPressed: _selected == null || _sentence.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, (
                  _selected!.key,
                  _sentence.text.trim(),
                )),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
