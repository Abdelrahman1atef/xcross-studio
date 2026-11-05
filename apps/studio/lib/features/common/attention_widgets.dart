import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/cli/xcross_commands.dart';
import '../../src/state/project_health.dart';

/// Runs the fix of [item] (features 027 and 028): the xcross command in the
/// project folder, after a confirmation when it replaces files, then reads the
/// project again so the item goes away.
Future<void> runAttentionFix(BuildContext context, AttentionItem item) async {
  final command = item.fixCommand;
  if (command == null) return;
  final services = Services.of(context);
  final project = services.settings.projectPath;
  if (project == null) return;
  if (item.overwrites) {
    final confirmed = await showXConfirmDialog(
      context,
      title: item.fixLabel ?? 'Fix',
      message:
          '${item.title}. xcross writes the files again from the plugin. The '
          'files that are there now are copied to '
          '.xcross/plugin-backups/ in the project first, so edits you made '
          'are kept there.',
      confirmLabel: item.fixLabel ?? 'Fix',
      details: [
        XCommandPreview(
          arguments: command,
          label: 'Runs',
          initiallyExpanded: true,
        ),
      ],
    );
    if (!confirmed || !context.mounted) return;
  }
  final job = services.jobs.run(
    '${item.fixLabel ?? 'Fix'}: ${item.title}',
    command,
    workingDirectory: project,
  );
  await job.done;
  await services.projectHealth.refresh();
}

/// The things to do in the open project, each with its one-click fix.
/// [only] limits the list to some items (a plugin, a page); nothing is shown
/// when there is nothing to do.
class AttentionList extends StatelessWidget {
  const AttentionList({super.key, this.only, this.title});

  /// Which items to show; all when null.
  final bool Function(AttentionItem item)? only;

  /// A heading above the list.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return ListenableBuilder(
      listenable: services.projectHealth,
      builder: (context, _) {
        final items = [
          for (final item in services.projectHealth.items)
            if (only?.call(item) ?? true) item,
        ];
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: XSpace.s2),
                child: Text(
                  title!,
                  style: XType.card.copyWith(
                    color: XTheme.of(context).colors.textPrimary,
                  ),
                ),
              ),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: XSpace.s2),
                child: AttentionRow(item: item),
              ),
          ],
        );
      },
    );
  }
}

/// One [AttentionItem] as a card with its buttons.
class AttentionRow extends StatelessWidget {
  const AttentionRow({super.key, required this.item});

  final AttentionItem item;

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return XDiagnosticCard(
      key: ValueKey('attention-${item.id}'),
      severity: item.severity == AttentionSeverity.warning
          ? XDiagnosticSeverity.warning
          : XDiagnosticSeverity.info,
      title: item.title,
      message: item.detail,
      command: item.fixCommand == null
          ? null
          : XcrossCommands.display(item.fixCommand!),
      actions: [
        if (item.fixLabel != null && item.fixCommand != null)
          XButton(
            label: item.fixLabel!,
            icon: item.overwrites ? Icons.auto_fix_high : Icons.check,
            onPressed: () => runAttentionFix(context, item),
          ),
        XButton(
          label: 'Open',
          icon: Icons.open_in_new,
          variant: XButtonVariant.text,
          onPressed: () => services.app.goProject(item.tab),
        ),
      ],
    );
  }
}
