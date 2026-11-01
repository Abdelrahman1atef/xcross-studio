import 'package:flutter/material.dart';

import '../theme/x_theme.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// The application frame (design system §5.1): top bar, sidebar, main
/// workspace with a docked console, status bar. Pure layout.
class XAppShell extends StatelessWidget {
  const XAppShell({
    super.key,
    required this.topBar,
    required this.sidebar,
    required this.body,
    required this.statusBar,
    this.dock,
  });

  final Widget topBar;
  final Widget sidebar;
  final Widget body;
  final Widget? dock;
  final Widget statusBar;

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    return Column(
      children: [
        topBar,
        Divider(height: 1, color: c.border),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sidebar,
              VerticalDivider(width: 1, color: c.border),
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: body),
                    ?dock,
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: c.border),
        statusBar,
      ],
    );
  }
}

/// A collapsible, resizable bottom pane (drag the top edge).
class XConsoleDock extends StatelessWidget {
  const XConsoleDock({
    super.key,
    required this.title,
    required this.open,
    required this.height,
    required this.onToggle,
    required this.onResize,
    required this.child,
    this.actions = const [],
    this.maxHeight = 600,
  });

  final Widget title;
  final bool open;
  final double height;
  final VoidCallback onToggle;
  final ValueChanged<double> onResize;
  final Widget child;
  final List<Widget> actions;
  final double maxHeight;

  static const headerHeight = 36.0;

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedContainer(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      height: open ? height.clamp(120, maxHeight) : headerHeight,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            cursor: open
                ? SystemMouseCursors.resizeRow
                : SystemMouseCursors.basic,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: open
                  ? (d) => onResize((height - d.delta.dy).clamp(120, maxHeight))
                  : null,
              child: SizedBox(
                height: headerHeight - 1,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: open ? 'Collapse console' : 'Open console',
                      iconSize: 18,
                      color: c.textSecondary,
                      onPressed: onToggle,
                      icon: Icon(open ? Icons.expand_more : Icons.expand_less),
                    ),
                    Expanded(
                      child: DefaultTextStyle(
                        style: XType.support.copyWith(color: c.textSecondary),
                        child: title,
                      ),
                    ),
                    ...actions,
                    const SizedBox(width: XSpace.s2),
                  ],
                ),
              ),
            ),
          ),
          if (open)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  XSpace.s3,
                  0,
                  XSpace.s3,
                  XSpace.s2,
                ),
                child: child,
              ),
            ),
        ],
      ),
    );
  }
}
