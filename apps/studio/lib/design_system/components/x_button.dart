import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/x_theme.dart';
import '../tokens/spacing.dart';

/// Button variants (design system §8.1).
enum XButtonVariant { primary, secondary, text, danger }

/// The standard action button. While [loading], it stays labelled with the
/// running operation ([loadingLabel], e.g. "Signing…") and ignores taps.
/// A disabled button should come with [disabledReason], shown as a tooltip.
class XButton extends StatelessWidget {
  const XButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = XButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.loadingLabel,
    this.disabledReason,
  });

  final String label;
  final VoidCallback? onPressed;
  final XButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final String? loadingLabel;

  /// Why the button is disabled (tooltip), when that is not obvious.
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    final enabled = onPressed != null && !loading;
    final text = Text(loading ? (loadingLabel ?? label) : label);
    final Widget? leading = loading
        ? const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : (icon == null ? null : Icon(icon, size: 18));
    final callback = enabled ? onPressed : null;
    final Widget button = switch (variant) {
      XButtonVariant.primary =>
        leading == null
            ? FilledButton(onPressed: callback, child: text)
            : FilledButton.icon(
                onPressed: callback,
                icon: leading,
                label: text,
              ),
      XButtonVariant.secondary =>
        leading == null
            ? OutlinedButton(onPressed: callback, child: text)
            : OutlinedButton.icon(
                onPressed: callback,
                icon: leading,
                label: text,
              ),
      XButtonVariant.text =>
        leading == null
            ? TextButton(onPressed: callback, child: text)
            : TextButton.icon(onPressed: callback, icon: leading, label: text),
      XButtonVariant.danger => OutlinedButton.icon(
        onPressed: callback,
        style: OutlinedButton.styleFrom(
          foregroundColor: c.error,
          side: BorderSide(color: c.error.withValues(alpha: 0.6)),
        ),
        icon: leading ?? const Icon(Icons.warning_amber_rounded, size: 18),
        label: text,
      ),
    };
    final reason = !enabled && !loading ? disabledReason : null;
    // Page text can be selected; a button's label is for clicking.
    return SelectionContainer.disabled(
      child: Semantics(
        button: true,
        enabled: enabled,
        label: loading ? (loadingLabel ?? label) : label,
        child: reason == null
            ? button
            : Tooltip(message: reason, child: button),
      ),
    );
  }
}

/// A compact toolbar button with a required tooltip.
class XIconButton extends StatelessWidget {
  const XIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.destructive = false,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool destructive;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      isSelected: selected,
      constraints: const BoxConstraints.tightFor(
        width: XSpace.control - 4,
        height: XSpace.control - 4,
      ),
      iconSize: 18,
      color: destructive ? c.error : (selected ? c.primary : c.textSecondary),
      icon: Icon(icon),
    );
  }
}

/// Copies [text], and shows that it did for a moment.
class XCopyButton extends StatefulWidget {
  const XCopyButton({super.key, required this.text, this.tooltip = 'Copy'});

  final String text;
  final String tooltip;

  @override
  State<XCopyButton> createState() => _XCopyButtonState();
}

class _XCopyButtonState extends State<XCopyButton> {
  Timer? _reset;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    _reset?.cancel();
    setState(() {
      _reset = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _reset = null);
      });
    });
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => XIconButton(
    icon: _reset == null ? Icons.copy : Icons.check,
    tooltip: _reset == null ? widget.tooltip : 'Copied',
    onPressed: _copy,
  );
}
