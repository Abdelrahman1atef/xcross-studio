import 'package:flutter/material.dart';

import '../theme/x_theme.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// A screen: title, optional subtitle and quick actions, then scrolling
/// content with the standard spacing. Its text can be selected and copied.
class WorkspaceLayout extends StatelessWidget {
  const WorkspaceLayout({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          XSpace.s6,
          XSpace.s6,
          XSpace.s6,
          XSpace.s8,
        ),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: XType.title.copyWith(color: c.textPrimary),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: XSpace.s1),
                      Text(
                        subtitle!,
                        style: XType.body.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              if (actions.isNotEmpty)
                Wrap(
                  spacing: XSpace.s2,
                  runSpacing: XSpace.s2,
                  children: actions,
                ),
            ],
          ),
          const SizedBox(height: XSpace.s6),
          for (final (i, child) in children.indexed) ...[
            if (i > 0) const SizedBox(height: XSpace.s4),
            child,
          ],
        ],
      ),
    );
  }
}

/// A section heading inside a screen.
class XSectionTitle extends StatelessWidget {
  const XSectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Semantics(
          header: true,
          child: Text(
            text,
            style: XType.section.copyWith(
              color: XTheme.of(context).colors.textPrimary,
            ),
          ),
        ),
      ),
      ?trailing,
    ],
  );
}
