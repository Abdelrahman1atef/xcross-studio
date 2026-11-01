import 'package:flutter/material.dart';

import '../theme/x_theme.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// Operational states shared by badges and cards (design system §3.2, §10).
enum XStatus { ready, running, warning, failed, idle }

/// The icon, colour and default label of each [XStatus]; never colour alone.
extension XStatusLook on XStatus {
  IconData get icon => switch (this) {
    XStatus.ready => Icons.check_circle,
    XStatus.running => Icons.autorenew,
    XStatus.warning => Icons.error_outline,
    XStatus.failed => Icons.cancel,
    XStatus.idle => Icons.radio_button_unchecked,
  };

  /// The glyph used in text form (`✓ Ready`, `! Needs attention`, …).
  String get glyph => switch (this) {
    XStatus.ready => '✓',
    XStatus.running => '…',
    XStatus.warning => '!',
    XStatus.failed => '×',
    XStatus.idle => '○',
  };

  String get defaultLabel => switch (this) {
    XStatus.ready => 'Ready',
    XStatus.running => 'Running',
    XStatus.warning => 'Needs attention',
    XStatus.failed => 'Failed',
    XStatus.idle => 'Not checked',
  };

  Color color(BuildContext context) {
    final c = XTheme.of(context).colors;
    return switch (this) {
      XStatus.ready => c.success,
      XStatus.running => c.primary,
      XStatus.warning => c.warning,
      XStatus.failed => c.error,
      XStatus.idle => c.textMuted,
    };
  }
}

/// A status label with icon and text (`XStatusBadge` in §8): readable
/// without colour, and announced to screen readers.
class XStatusBadge extends StatelessWidget {
  const XStatusBadge({
    super.key,
    required this.status,
    this.label,
    this.compact = false,
  });

  final XStatus status;

  /// Overrides the default label (`Ready`, `Failed`, …).
  final String? label;

  /// Icon + label without the pill background (status bar).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = status.color(context);
    final text = label ?? status.defaultLabel;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (status == XStatus.running)
          SizedBox.square(
            dimension: 12,
            child: CircularProgressIndicator(strokeWidth: 1.6, color: color),
          )
        else
          Icon(status.icon, size: 14, color: color),
        const SizedBox(width: XSpace.s1 + 2),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: XType.support.copyWith(
              color: compact ? XTheme.of(context).colors.textSecondary : color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
    return Semantics(
      label: '${status.defaultLabel}: $text',
      excludeSemantics: true,
      child: compact
          ? content
          : Container(
              padding: const EdgeInsets.symmetric(
                horizontal: XSpace.s2,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(XRadius.sm),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: content,
            ),
    );
  }
}
