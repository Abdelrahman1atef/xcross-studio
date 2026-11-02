import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../design_system/components/x_build.dart';
import '../../design_system/components/x_button.dart';
import '../../design_system/components/x_console.dart';
import '../../design_system/components/x_status.dart';
import '../../design_system/tokens/spacing.dart';
import '../../src/cli/output_line.dart';
import '../../src/state/job.dart';

/// Console tone of an output line.
XConsoleTone toneOf(LineKind kind) => switch (kind) {
  LineKind.plain => XConsoleTone.plain,
  LineKind.command => XConsoleTone.command,
  LineKind.success => XConsoleTone.success,
  LineKind.failure => XConsoleTone.failure,
  LineKind.warning => XConsoleTone.warning,
  LineKind.error => XConsoleTone.error,
  LineKind.hint => XConsoleTone.hint,
  LineKind.stderr => XConsoleTone.muted,
};

List<XConsoleLine> consoleLines(Job job) => [
  for (final line in job.lines) XConsoleLine(line.text, toneOf(line.kind)),
];

XConsoleState consoleState(Job job) => switch (job.status) {
  JobStatus.running => XConsoleState.live,
  JobStatus.succeeded => XConsoleState.complete,
  JobStatus.failed => XConsoleState.failed,
  JobStatus.cancelled => XConsoleState.stopped,
};

XStatus statusOf(Job? job) => switch (job?.status) {
  null => XStatus.idle,
  JobStatus.running => XStatus.running,
  JobStatus.succeeded => XStatus.ready,
  JobStatus.failed => XStatus.failed,
  JobStatus.cancelled => XStatus.idle,
};

/// `m:ss` of a job's run time.
String elapsedOf(Job job) {
  final seconds = job.elapsed.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// The steps the command reported (`step` events), in order.
List<XStepItem> stepItems(Job job) => [
  for (final step in job.steps)
    XStepItem(
      step.name,
      switch (step.status) {
        'done' => XStepState.passed,
        'failed' => XStepState.failed,
        _ when job.isRunning => XStepState.active,
        _ when job.status == JobStatus.failed => XStepState.failed,
        _ when job.status == JobStatus.cancelled => XStepState.skipped,
        _ => XStepState.passed,
      },
      detail: step.status == 'failed'
          ? step.message
          : (step.elapsedMs == null
                ? null
                : '${(step.elapsedMs! / 1000).toStringAsFixed(1)}s'),
    ),
];

/// A problem the CLI reported: its code and hint exactly as printed.
class JobDiagnostic {
  const JobDiagnostic({
    required this.isError,
    required this.message,
    this.code,
    this.hint,
  });

  final bool isError;
  final String message;
  final String? code;
  final String? hint;
}

/// Errors and warnings of [job], each with the `hint:` line after it.
List<JobDiagnostic> diagnosticsOf(Job job) {
  final out = <JobDiagnostic>[];
  for (var i = 0; i < job.lines.length; i++) {
    final line = job.lines[i];
    if (!line.isIssue) continue;
    final next = i + 1 < job.lines.length ? job.lines[i + 1] : null;
    var text = line.text.trim();
    final colon = text.indexOf(':');
    if (colon > 0 && colon < 9) text = text.substring(colon + 1).trim();
    final code = line.code;
    if (code != null) text = text.replaceFirst('[$code]', '').trim();
    String? hint;
    if (next?.kind == LineKind.hint) {
      hint = next!.text.trim().replaceFirst(RegExp(r'^hint:\s*'), '');
    }
    out.add(
      JobDiagnostic(
        isError: line.kind == LineKind.error,
        message: text,
        code: code,
        hint: hint,
      ),
    );
  }
  return out;
}

/// The diagnostics of [job] as cards (at most [limit]).
class JobDiagnostics extends StatelessWidget {
  const JobDiagnostics({
    super.key,
    required this.job,
    this.limit = 4,
    this.skipCodes = const {},
  });

  final Job job;
  final int limit;

  /// Codes another card on the page already explains.
  final Set<String> skipCodes;

  @override
  Widget build(BuildContext context) {
    final app = Services.of(context).app;
    final all = [
      for (final d in diagnosticsOf(job))
        if (!skipCodes.contains(d.code)) d,
    ];
    if (all.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final d in all.take(limit)) ...[
          XDiagnosticCard(
            severity: d.isError
                ? XDiagnosticSeverity.error
                : XDiagnosticSeverity.warning,
            message: d.message,
            code: d.code,
            hint: d.hint,
            command: job.displayCommand,
            onViewLogs: () => app.showJob(job),
          ),
          const SizedBox(height: XSpace.s2),
        ],
        if (all.length > limit)
          Text('… ${all.length - limit} more in the console'),
      ],
    );
  }
}

/// A job's live console with Stop (only while it runs; it really ends the
/// process tree) and an input line when [input] is allowed.
class JobConsole extends StatelessWidget {
  const JobConsole({
    super.key,
    required this.job,
    this.height = 260,
    this.input = false,
    this.inputHint = 'Type input for the command (2FA code, r, q, …)',
    this.showTitle = true,
    this.showHeader = true,
  });

  final Job job;
  final double? height;
  final bool input;
  final String inputHint;
  final bool showTitle;

  /// Hide the state/copy/stop row (the console dock shows its own).
  final bool showHeader;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: job,
    builder: (context, _) => XConsole(
      title: showTitle ? '${job.title} · ${elapsedOf(job)}' : null,
      lines: consoleLines(job),
      state: consoleState(job),
      height: height,
      onInput: input && job.isRunning ? job.send : null,
      inputHint: inputHint,
      showHeader: showHeader,
      trailing: job.isRunning
          ? XButton(
              label: 'Stop',
              icon: Icons.stop,
              variant: XButtonVariant.secondary,
              onPressed: job.cancel,
            )
          : null,
    ),
  );
}

/// Progress, reported steps, diagnostics and console of a structured job.
class JobPanel extends StatelessWidget {
  const JobPanel({
    super.key,
    required this.job,
    this.consoleHeight = 260,
    this.input = false,
    this.skipCodes = const {},
  });

  final Job job;
  final double consoleHeight;
  final bool input;

  /// Diagnostic codes another card on the page already explains.
  final Set<String> skipCodes;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: job,
    builder: (context, _) {
      final progress = job.progress;
      final fraction = progress?.fraction;
      final downloading = job.isRunning && fraction != null && fraction < 1;
      final current = job.currentStep;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (job.isRunning) ...[
            XProgressIndicator(
              label: downloading
                  ? progress!.label
                  : (current == null ? 'Working…' : '${current.name}…'),
              fraction: downloading ? fraction : null,
            ),
            const SizedBox(height: XSpace.s3),
          ],
          if (job.steps.isNotEmpty) ...[
            XBuildStepper(steps: stepItems(job)),
            const SizedBox(height: XSpace.s3),
          ],
          JobDiagnostics(job: job, skipCodes: skipCodes),
          JobConsole(job: job, height: consoleHeight, input: input),
        ],
      );
    },
  );
}
