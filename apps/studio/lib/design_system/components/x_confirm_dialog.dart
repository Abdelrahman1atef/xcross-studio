import 'package:flutter/material.dart';

import '../theme/x_theme.dart';
import '../tokens/spacing.dart';
import 'x_button.dart';

/// Confirms an impactful action. Returns `true` when confirmed. Focus goes
/// back to the invoking control when the dialog closes (Navigator default).
Future<bool> showXConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
  List<Widget> details = const [],
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => XConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: destructive,
      details: details,
    ),
  );
  return confirmed ?? false;
}

/// The standard or destructive confirmation dialog.
class XConfirmDialog extends StatelessWidget {
  const XConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.destructive = false,
    this.details = const [],
  });

  final String title;
  final String message;
  final String confirmLabel;
  final bool destructive;
  final List<Widget> details;

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            destructive ? Icons.warning_amber_rounded : Icons.help_outline,
            color: destructive ? c.error : c.primary,
          ),
          const SizedBox(width: XSpace.s2),
          Expanded(child: Text(title)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (details.isNotEmpty) ...[
              const SizedBox(height: XSpace.s3),
              ...details,
            ],
          ],
        ),
      ),
      actions: [
        XButton(
          label: 'Cancel',
          variant: XButtonVariant.text,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        XButton(
          label: confirmLabel,
          variant: destructive ? XButtonVariant.danger : XButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
