import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/x_theme.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'x_status.dart';

/// Build step states (design system §8).
enum XStepState { waiting, active, passed, failed, skipped }

/// One step of a build, as reported by the CLI.
class XStepItem {
  const XStepItem(this.label, this.state, {this.detail});

  final String label;
  final XStepState state;

  /// Elapsed time or failure message.
  final String? detail;
}

/// The build lifecycle. Shows only the steps the command reported (§6.2):
/// never a made-up pipeline.
class XBuildStepper extends StatelessWidget {
  const XBuildStepper({super.key, required this.steps});

  final List<XStepItem> steps;

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, step) in steps.indexed)
          Semantics(
            label:
                '${_word(step.state)}: ${step.label}'
                '${step.detail == null ? '' : ', ${step.detail}'}',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Column(
                      children: [
                        _marker(context, step.state),
                        if (i < steps.length - 1)
                          Container(width: 1, height: 10, color: c.border),
                      ],
                    ),
                  ),
                  const SizedBox(width: XSpace.s2),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: step.label,
                        style: XType.body.copyWith(
                          color:
                              step.state == XStepState.waiting ||
                                  step.state == XStepState.skipped
                              ? c.textMuted
                              : c.textPrimary,
                          fontWeight: step.state == XStepState.active
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                        children: [
                          if (step.detail != null)
                            TextSpan(
                              text: '  ${step.detail}',
                              style: XType.support.copyWith(
                                color: step.state == XStepState.failed
                                    ? c.error
                                    : c.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static String _word(XStepState state) => switch (state) {
    XStepState.waiting => 'Waiting',
    XStepState.active => 'Running',
    XStepState.passed => 'Passed',
    XStepState.failed => 'Failed',
    XStepState.skipped => 'Skipped',
  };

  Widget _marker(BuildContext context, XStepState state) {
    final c = XTheme.of(context).colors;
    return switch (state) {
      XStepState.active => SizedBox.square(
        dimension: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: c.primary),
      ),
      XStepState.passed => Icon(XStatus.ready.icon, size: 18, color: c.success),
      XStepState.failed => Icon(XStatus.failed.icon, size: 18, color: c.error),
      XStepState.skipped => Icon(
        Icons.remove_circle_outline,
        size: 18,
        color: c.textMuted,
      ),
      XStepState.waiting => Icon(
        XStatus.idle.icon,
        size: 18,
        color: c.textMuted,
      ),
    };
  }
}

/// Task progress. Determinate only when [fraction] is real (§2.6);
/// otherwise an indeterminate bar.
class XProgressIndicator extends StatelessWidget {
  const XProgressIndicator({super.key, required this.label, this.fraction});

  final String label;
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    final value = fraction?.clamp(0.0, 1.0);
    return Semantics(
      label: label,
      value: value == null ? null : '${(value * 100).round()}%',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: XType.support.copyWith(color: c.textSecondary),
                ),
              ),
              if (value != null)
                Text(
                  '${(value * 100).round()}%',
                  style: XType.support.copyWith(color: c.textPrimary),
                ),
            ],
          ),
          const SizedBox(height: XSpace.s1),
          ClipRRect(
            borderRadius: BorderRadius.circular(XRadius.sm),
            child: LinearProgressIndicator(value: value, minHeight: 4),
          ),
        ],
      ),
    );
  }
}

/// Diagnostic severities.
enum XDiagnosticSeverity { info, warning, error }

/// An actionable problem (design system §8.2): what happened, the stable
/// code from the CLI (never invented), and the suggested fix.
class XDiagnosticCard extends StatelessWidget {
  const XDiagnosticCard({
    super.key,
    required this.severity,
    required this.message,
    this.title,
    this.code,
    this.hint,
    this.command,
    this.onViewLogs,
  });

  final XDiagnosticSeverity severity;
  final String message;

  /// A short headline; defaults to the [message].
  final String? title;

  /// The CLI's stable code (`device.not_found`), when it printed one.
  final String? code;

  /// The CLI's fix hint.
  final String? hint;

  /// The command to copy (already masked).
  final String? command;
  final VoidCallback? onViewLogs;

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    final (status, glyph) = switch (severity) {
      XDiagnosticSeverity.error => (XStatus.failed, '✕'),
      XDiagnosticSeverity.warning => (XStatus.warning, '!'),
      XDiagnosticSeverity.info => (XStatus.idle, 'i'),
    };
    final color = severity == XDiagnosticSeverity.info
        ? c.primary
        : status.color(context);
    return Container(
      padding: const EdgeInsets.all(XSpace.s3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(XRadius.md),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$glyph ${title ?? message}',
            style: XType.body.copyWith(
              color: c.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (title != null) ...[
            const SizedBox(height: XSpace.s1),
            SelectableText(
              message,
              style: XType.body.copyWith(color: c.textSecondary),
            ),
          ],
          if (code != null) ...[
            const SizedBox(height: XSpace.s1),
            SelectableText(
              'Code: $code',
              style: XType.mono.copyWith(color: c.textSecondary),
            ),
          ],
          if (hint != null && hint!.isNotEmpty) ...[
            const SizedBox(height: XSpace.s2),
            Text(
              'Suggested fix',
              style: XType.support.copyWith(
                color: c.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
            SelectableText(
              hint!,
              style: XType.body.copyWith(color: c.textPrimary),
            ),
          ],
          if (command != null || onViewLogs != null) ...[
            const SizedBox(height: XSpace.s2),
            Wrap(
              spacing: XSpace.s2,
              children: [
                if (command != null)
                  TextButton.icon(
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: command!)),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy command'),
                  ),
                if (onViewLogs != null)
                  TextButton.icon(
                    onPressed: onViewLogs,
                    icon: const Icon(Icons.terminal, size: 16),
                    label: const Text('View logs'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
