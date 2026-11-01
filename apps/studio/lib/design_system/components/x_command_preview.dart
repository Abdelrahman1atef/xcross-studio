import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/x_theme.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// Shows the CLI command an action runs (design system §2.7, §8). Secret
/// values (after `--password`, or `--password=`) are masked in the view and
/// in the copied text.
class XCommandPreview extends StatefulWidget {
  const XCommandPreview({
    super.key,
    required this.arguments,
    this.program = 'xcross',
    this.label = 'Command',
    this.initiallyExpanded = false,
    this.workingDirectory,
  });

  final List<String> arguments;
  final String program;
  final String label;
  final bool initiallyExpanded;

  /// Shown when expanded (`in <folder>`).
  final String? workingDirectory;

  /// Flags whose following value is secret.
  static const secretFlags = {'--password'};

  /// [program] + [arguments] as one shell-like line, secrets masked.
  static String render(String program, List<String> arguments) {
    final shown = <String>[];
    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];
      final eq = argument.indexOf('=');
      if (eq > 0 && secretFlags.contains(argument.substring(0, eq))) {
        shown.add('${argument.substring(0, eq)}=••••');
        continue;
      }
      shown.add(argument);
      if (secretFlags.contains(argument) && i + 1 < arguments.length) {
        shown.add('••••');
        i++;
      }
    }
    return [
      program,
      for (final part in shown)
        part.contains(' ') || part.isEmpty ? '"$part"' : part,
    ].join(' ');
  }

  @override
  State<XCommandPreview> createState() => _XCommandPreviewState();
}

class _XCommandPreviewState extends State<XCommandPreview> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    final line = XCommandPreview.render(widget.program, widget.arguments);
    return Container(
      decoration: BoxDecoration(
        color: c.console,
        borderRadius: BorderRadius.circular(XRadius.md),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: _expanded ? 'Collapse' : 'Expand',
                iconSize: 18,
                color: c.textSecondary,
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(_expanded ? Icons.expand_more : Icons.chevron_right),
              ),
              Text(
                widget.label,
                style: XType.support.copyWith(color: c.textMuted),
              ),
              const SizedBox(width: XSpace.s2),
              Expanded(
                child: _expanded
                    ? const SizedBox.shrink()
                    : Text(
                        line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: XType.mono.copyWith(color: c.textPrimary),
                      ),
              ),
              IconButton(
                tooltip: 'Copy command',
                iconSize: 16,
                color: c.textSecondary,
                onPressed: () => Clipboard.setData(ClipboardData(text: line)),
                icon: const Icon(Icons.copy),
              ),
            ],
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                XSpace.s4,
                0,
                XSpace.s4,
                XSpace.s3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    line,
                    style: XType.mono.copyWith(color: c.textPrimary),
                  ),
                  if (widget.workingDirectory != null)
                    Text(
                      'in ${widget.workingDirectory}',
                      style: XType.support.copyWith(color: c.textMuted),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
