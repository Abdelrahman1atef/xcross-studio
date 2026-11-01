import 'package:flutter/material.dart';

import '../theme/x_theme.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'x_status.dart';

/// Card variants (design system §8).
enum XCardVariant { basic, elevated, interactive }

/// Content grouping with an optional title row and trailing actions.
class XCard extends StatelessWidget {
  const XCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.variant = XCardVariant.basic,
    this.onTap,
    this.selected = false,
    this.padding = const EdgeInsets.all(XSpace.s4),
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final XCardVariant variant;
  final VoidCallback? onTap;
  final bool selected;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    final body = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title!,
                        style: XType.card.copyWith(color: c.textPrimary),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: XType.support.copyWith(color: c.textSecondary),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: XSpace.s3),
          ],
          child,
        ],
      ),
    );
    // A Material (not a DecoratedBox) so list tiles inside keep their ink.
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(XRadius.lg),
      side: BorderSide(
        color: selected ? c.primary : c.border,
        width: selected ? 1.5 : 1,
      ),
    );
    final color = variant == XCardVariant.elevated
        ? c.surfaceElevated
        : c.surface;
    if (onTap == null && variant != XCardVariant.interactive) {
      return Material(color: color, shape: shape, child: body);
    }
    return Material(
      color: color,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        hoverColor: c.primary.withValues(alpha: 0.06),
        onTap: onTap,
        child: body,
      ),
    );
  }
}

/// A labelled check row (`✓ Bundle ID  com.example.app`): status icon plus
/// text, used in checklists.
class XCheckRow extends StatelessWidget {
  const XCheckRow({
    super.key,
    required this.status,
    required this.label,
    this.detail,
  });

  final XStatus status;
  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    return Semantics(
      label:
          '${status.defaultLabel}: $label${detail == null ? '' : ', $detail'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(status.icon, size: 16, color: status.color(context)),
            ),
            const SizedBox(width: XSpace.s2),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: label,
                  style: XType.body.copyWith(color: c.textPrimary),
                  children: [
                    if (detail != null)
                      TextSpan(
                        text: '  $detail',
                        style: XType.body.copyWith(color: c.textSecondary),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A short, muted explanation paragraph.
class XNote extends StatelessWidget {
  const XNote(this.text, {super.key, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    final paragraph = Text(
      text,
      style: XType.support.copyWith(color: c.textSecondary),
    );
    if (icon == null) return paragraph;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: c.textSecondary),
        const SizedBox(width: XSpace.s2),
        Expanded(child: paragraph),
      ],
    );
  }
}

/// A highlighted information or caution box.
class XCallout extends StatelessWidget {
  const XCallout({
    super.key,
    required this.title,
    required this.children,
    this.status = XStatus.idle,
  });

  final String title;
  final List<Widget> children;
  final XStatus status;

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    final color = status == XStatus.idle ? c.primary : status.color(context);
    return Container(
      padding: const EdgeInsets.all(XSpace.s3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(XRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                status == XStatus.idle ? Icons.info_outline : status.icon,
                size: 16,
                color: color,
              ),
              const SizedBox(width: XSpace.s2),
              Expanded(
                child: Text(
                  title,
                  style: XType.body.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: XSpace.s1),
          ...children,
        ],
      ),
    );
  }
}
