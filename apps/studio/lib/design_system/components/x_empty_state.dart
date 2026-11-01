import 'package:flutter/material.dart';

import '../theme/x_theme.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// A helpful zero state: what is missing, why, and the next step.
class XEmptyState extends StatelessWidget {
  const XEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;

  /// Usually one primary [XButton].
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: XSpace.s6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(XSpace.s3),
            decoration: BoxDecoration(
              color: c.surfaceElevated,
              borderRadius: BorderRadius.circular(XRadius.lg),
            ),
            child: Icon(icon, size: 28, color: c.textSecondary),
          ),
          const SizedBox(height: XSpace.s3),
          Text(
            title,
            textAlign: TextAlign.center,
            style: XType.card.copyWith(color: c.textPrimary),
          ),
          const SizedBox(height: XSpace.s1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: XType.body.copyWith(color: c.textSecondary),
            ),
          ),
          if (action != null) ...[const SizedBox(height: XSpace.s4), action!],
        ],
      ),
    );
  }
}
