import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cli/output_line.dart';
import '../cli/xcross_events.dart';
import '../state/job.dart';

/// Monospace style for output and logs.
const mono = TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.35);

/// Colour of an output line.
Color lineColor(LineKind kind, ColorScheme scheme) => switch (kind) {
  LineKind.error || LineKind.failure => scheme.error,
  LineKind.warning => Colors.orange.shade700,
  LineKind.hint => scheme.tertiary,
  LineKind.success => Colors.green.shade700,
  LineKind.command => scheme.primary,
  LineKind.stderr => scheme.onSurfaceVariant,
  LineKind.plain => scheme.onSurface,
};

/// A page section with a title.
class Section extends StatelessWidget {
  const Section({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

/// A text field with a "Browse…" button for a folder or a file.
class PathField extends StatefulWidget {
  const PathField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.directory = true,
    this.extensions = const [],
    this.hint,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool directory;
  final List<String> extensions;
  final String? hint;

  @override
  State<PathField> createState() => _PathFieldState();
}

class _PathFieldState extends State<PathField> {
  late final _controller = TextEditingController(text: widget.value ?? '');

  @override
  void didUpdateWidget(PathField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.value ?? '') != _controller.text) {
      _controller.text = widget.value ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    String? picked;
    if (widget.directory) {
      picked = await getDirectoryPath(initialDirectory: widget.value);
    } else {
      final file = await openFile(
        acceptedTypeGroups: [
          if (widget.extensions.isNotEmpty)
            XTypeGroup(
              label: widget.extensions.join(', '),
              extensions: widget.extensions,
            ),
        ],
      );
      picked = file?.path;
    }
    if (picked != null) widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: widget.hint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (text) =>
              widget.onChanged(text.trim().isEmpty ? null : text.trim()),
          onTapOutside: (_) {
            final text = _controller.text.trim();
            if (text != (widget.value ?? '')) {
              widget.onChanged(text.isEmpty ? null : text);
            }
          },
        ),
      ),
      const SizedBox(width: 8),
      OutlinedButton.icon(
        onPressed: _browse,
        icon: Icon(widget.directory ? Icons.folder_open : Icons.file_open),
        label: const Text('Browse…'),
      ),
    ],
  );
}

/// A ✔/✖ row.
class CheckRow extends StatelessWidget {
  const CheckRow({
    super.key,
    required this.ok,
    required this.label,
    this.detail,
  });

  final bool? ok;
  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (ok) {
      true => (Icons.check_circle, Colors.green.shade700),
      false => (Icons.cancel, scheme.error),
      null => (Icons.radio_button_unchecked, scheme.outline),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: label,
                children: [
                  if (detail != null)
                    TextSpan(
                      text: '  $detail',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A job's live output with status, cancel, copy and an input box.
class JobOutputView extends StatefulWidget {
  const JobOutputView({
    super.key,
    required this.job,
    this.height = 320,
    this.showInput = true,
  });

  final Job job;
  final double? height;
  final bool showInput;

  @override
  State<JobOutputView> createState() => _JobOutputViewState();
}

class _JobOutputViewState extends State<JobOutputView> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    widget.job.addListener(_changed);
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      final atEnd = _scroll.offset >= _scroll.position.maxScrollExtent - 24;
      if (atEnd != _follow) _follow = atEnd;
    });
  }

  @override
  void didUpdateWidget(JobOutputView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.job != widget.job) {
      oldWidget.job.removeListener(_changed);
      widget.job.addListener(_changed);
      _follow = true;
    }
  }

  @override
  void dispose() {
    widget.job.removeListener(_changed);
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final scheme = Theme.of(context).colorScheme;
    final output = Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SelectionArea(
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.all(8),
          itemCount: job.lines.length,
          itemBuilder: (context, index) {
            final line = job.lines[index];
            return Text(
              line.text,
              style: mono.copyWith(color: lineColor(line.kind, scheme)),
            );
          },
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: widget.height == null ? MainAxisSize.max : MainAxisSize.min,
      children: [
        _StatusBar(job: job),
        // studio: 012 — steps, progress and issues from build events.
        if (job.steps.isNotEmpty || job.progress != null) ...[
          const SizedBox(height: 6),
          StepsPanel(job: job),
        ],
        if (job.issues.isNotEmpty) ...[
          const SizedBox(height: 6),
          IssueList(job: job),
        ],
        const SizedBox(height: 6),
        if (widget.height == null)
          Expanded(child: output)
        else
          SizedBox(height: widget.height, child: output),
        if (widget.showInput && job.isRunning) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  style: mono,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText:
                        'Type input for the command (2FA code, r, q, …) '
                        'and press Enter',
                  ),
                  onSubmitted: (text) {
                    job.send(text);
                    _input.clear();
                  },
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final seconds = job.elapsed.inSeconds;
    final elapsed =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    final (Widget icon, String label) = switch (job.status) {
      JobStatus.running => (
        const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        'Running · $elapsed',
      ),
      JobStatus.succeeded => (
        Icon(Icons.check_circle, size: 18, color: Colors.green.shade700),
        'Done · $elapsed',
      ),
      JobStatus.failed => (
        Icon(Icons.error, size: 18, color: scheme.error),
        'Failed (exit ${job.exitCode ?? '-'}) · $elapsed',
      ),
      JobStatus.cancelled => (
        Icon(Icons.stop_circle, size: 18, color: scheme.outline),
        'Stopped · $elapsed',
      ),
    };
    final issues = job.issues;
    return Row(
      children: [
        icon,
        const SizedBox(width: 8),
        Text(label),
        if (issues.isNotEmpty) ...[
          const SizedBox(width: 12),
          Chip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(Icons.warning_amber, size: 16, color: scheme.error),
            label: Text(
              '${issues.length} issue${issues.length == 1 ? '' : 's'}',
            ),
          ),
        ],
        const Spacer(),
        IconButton(
          tooltip: 'Copy output',
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () => Clipboard.setData(
            ClipboardData(text: [for (final l in job.lines) l.text].join('\n')),
          ),
        ),
        if (job.isRunning)
          FilledButton.tonalIcon(
            onPressed: job.cancel,
            icon: const Icon(Icons.stop, size: 18),
            label: const Text('Stop'),
          ),
      ],
    );
  }
}

// studio: 012 — views over the build events of a structured job.

/// The running step (or download progress) and the finished steps.
class StepsPanel extends StatelessWidget {
  const StepsPanel({super.key, required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = job.progress;
    final fraction = progress?.fraction;
    final downloading = job.isRunning && fraction != null && fraction < 1;
    final current = job.currentStep;
    final finished = job.steps.where((s) => s.status != 'start').length;
    final String headline;
    if (downloading) {
      headline = '${progress!.label}  ${(fraction * 100).round()}%';
    } else if (current != null && job.isRunning) {
      headline = '${current.name}…';
    } else if (job.isRunning) {
      headline = 'Working…';
    } else {
      headline = '$finished step${finished == 1 ? '' : 's'} finished';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (job.isRunning)
          LinearProgressIndicator(value: downloading ? fraction : null),
        const SizedBox(height: 4),
        Text(headline, style: Theme.of(context).textTheme.bodyMedium),
        if (job.steps.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final step in job.steps)
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: switch (step.status) {
                    'done' => Icon(
                      Icons.check_circle,
                      size: 16,
                      color: Colors.green.shade700,
                    ),
                    'failed' => Icon(
                      Icons.cancel,
                      size: 16,
                      color: scheme.error,
                    ),
                    _ => const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  },
                  label: Text(
                    step.elapsedMs == null
                        ? step.name
                        : '${step.name}  '
                              '${(step.elapsedMs! / 1000).toStringAsFixed(1)}s',
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Errors and warnings with their codes and fix hints.
class IssueList extends StatelessWidget {
  const IssueList({super.key, required this.job, this.limit = 6});

  final Job job;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final issues = <(OutputLine, String?)>[];
    for (var i = 0; i < job.lines.length; i++) {
      final line = job.lines[i];
      if (!line.isIssue) continue;
      final next = i + 1 < job.lines.length ? job.lines[i + 1] : null;
      issues.add((line, next?.kind == LineKind.hint ? next!.text : null));
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (issue, hint) in issues.take(limit))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    issue.text,
                    style: mono.copyWith(color: lineColor(issue.kind, scheme)),
                  ),
                  if (hint != null)
                    SelectableText(
                      '  $hint',
                      style: mono.copyWith(
                        color: lineColor(LineKind.hint, scheme),
                      ),
                    ),
                ],
              ),
            ),
          if (issues.length > limit)
            Text('… ${issues.length - limit} more in the output below'),
        ],
      ),
    );
  }
}

/// The doctor's checks as a checklist (from `check` events), above the
/// command output.
class DoctorReport extends StatelessWidget {
  const DoctorReport({super.key, required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) => Watch(
    listenable: job,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      final sections = <String, List<DoctorCheckResult>>{};
      for (final check in job.checks) {
        sections.putIfAbsent(check.section, () => []).add(check);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final MapEntry(key: section, value: checks)
              in sections.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Text(
                section,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final check in checks)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  switch (check.status) {
                    'success' => Icon(
                      Icons.check_circle,
                      size: 18,
                      color: Colors.green.shade700,
                    ),
                    'failure' => Icon(
                      Icons.cancel,
                      size: 18,
                      color: scheme.error,
                    ),
                    _ => Icon(
                      Icons.warning_amber,
                      size: 18,
                      color: Colors.orange.shade700,
                    ),
                  },
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${check.name}  ${check.message}'
                      '${check.path == null ? '' : '  (${check.path})'}',
                    ),
                  ),
                ],
              ),
          ],
          const SizedBox(height: 8),
          JobOutputView(job: job, showInput: false, height: 220),
        ],
      );
    },
  );
}

/// Rebuilds [builder] whenever [listenable] changes.
class Watch extends StatelessWidget {
  const Watch({super.key, required this.listenable, required this.builder});

  final Listenable listenable;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: listenable, builder: (c, _) => builder(c));
}
