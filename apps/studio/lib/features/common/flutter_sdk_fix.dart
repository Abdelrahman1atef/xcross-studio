import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/cli/xcross_commands.dart';
import '../../src/cli/xcross_events.dart';
import '../../src/product.dart';
import '../../src/state/job.dart';
import 'job_views.dart';

/// The "no iOS compiler for this Flutter" problem (feature 014), read from
/// the CLI's own output: the `build.gen_snapshot_unavailable` error of a
/// build, or the doctor's "AOT compiler (release)" check.
class GenSnapshotProblem {
  const GenSnapshotProblem({required this.raw, this.current, this.suggested});

  /// The stable code the CLI prints.
  static const code = 'build.gen_snapshot_unavailable';

  /// The CLI text behind the problem, for "Show details".
  final String raw;

  /// The active Flutter version, when the CLI named it.
  final String? current;

  /// The Flutter version `xcross flutter sdk auto` installs, when named.
  final String? suggested;

  /// The problem in a failed [job], or `null` when it failed for another
  /// reason.
  static GenSnapshotProblem? fromJob(Job job) {
    if (job.status != JobStatus.failed) return null;
    final start = job.lines.indexWhere((line) => line.code == code);
    if (start < 0) return null;
    final raw = [for (final line in job.lines.skip(start)) line.text]
        .join('\n')
        .trim();
    return fromText(raw);
  }

  /// The problem described by a failing doctor [check], or `null`.
  static GenSnapshotProblem? fromCheck(DoctorCheckResult check) {
    final name = check.name.toLowerCase();
    if (!name.contains('aot compiler') || check.status != 'failure') {
      return null;
    }
    return fromText('${check.name}: ${check.message}');
  }

  static GenSnapshotProblem fromText(String raw) {
    String? first(List<RegExp> patterns) {
      for (final pattern in patterns) {
        final match = pattern.firstMatch(raw);
        if (match != null) return match.group(1);
      }
      return null;
    }

    const version = r'(\d+\.\d+\.\d+)';
    return GenSnapshotProblem(
      raw: raw,
      current: first([
        RegExp('Flutter $version \\(engine'),
        RegExp('Flutter $version has no'),
      ]),
      suggested: first([
        RegExp('published compiler for [^:\\n]+: $version'),
        RegExp('newest with one: $version'),
        RegExp('install Flutter $version'),
      ]),
    );
  }

  /// One plain paragraph for people who never heard of gen_snapshot.
  String get explanation {
    final os = Platform.isWindows ? 'Windows' : 'Linux';
    final needed = suggested == null
        ? 'a Flutter version that has one'
        : 'Flutter $suggested';
    final yours = current == null ? 'Your Flutter' : 'Your Flutter ($current)';
    final newer =
        current != null && suggested != null && _newer(current!, suggested!);
    final what = newer
        ? '$yours is newer than the iOS compiler $productName can use on $os.'
        : '$yours has no iOS compiler that $productName can use on $os.';
    return '$what iPhone release builds need $needed. $productName can '
        'install it just for iPhone builds (one time, about 1 GB); your own '
        'Flutter is not changed.';
  }

  static bool _newer(String a, String b) {
    final x = a.split('.').map(int.parse).toList();
    final y = b.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      if (x[i] != y[i]) return x[i] > y[i];
    }
    return false;
  }
}

/// Explains [problem] in plain words and fixes it with one click
/// (`xcross flutter sdk auto --yes`), then offers to build again.
class FlutterSdkFixCard extends StatefulWidget {
  const FlutterSdkFixCard({
    super.key,
    required this.problem,
    this.onFixed,
    this.retryLabel = 'Build again',
  });

  final GenSnapshotProblem problem;

  /// Called by the button shown after a successful fix (rebuild, re-check).
  final VoidCallback? onFixed;
  final String retryLabel;

  @override
  State<FlutterSdkFixCard> createState() => _FlutterSdkFixCardState();
}

class _FlutterSdkFixCardState extends State<FlutterSdkFixCard> {
  Job? _fix;

  void _start() {
    final services = Services.of(context);
    final job = services.jobs.run(
      widget.problem.suggested == null
          ? 'Set up Flutter for iPhone builds'
          : 'Set up Flutter ${widget.problem.suggested} for iPhone builds',
      XcrossCommands.flutterSdkAuto(),
      structured: true,
    );
    setState(() => _fix = job);
    job.done.then((status) {
      if (status == JobStatus.succeeded && mounted) {
        services.readiness.runDoctor();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final problem = widget.problem;
    final fix = _fix;
    final label = problem.suggested == null
        ? 'Set up a compatible Flutter for iPhone builds'
        : 'Set up Flutter ${problem.suggested} for iPhone builds';
    return ListenableBuilder(
      listenable: Listenable.merge([?fix]),
      builder: (context, _) {
        final running = fix?.isRunning ?? false;
        final done = fix?.status == JobStatus.succeeded;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            XDiagnosticCard(
              severity: done
                  ? XDiagnosticSeverity.info
                  : XDiagnosticSeverity.error,
              title: 'This Flutter cannot build iPhone release apps here yet',
              message: problem.explanation,
              code: GenSnapshotProblem.code,
              command: XcrossCommands.display(XcrossCommands.flutterSdkAuto()),
              details: problem.raw,
              actions: [
                if (!done)
                  XButton(
                    label: label,
                    icon: Icons.auto_fix_high,
                    loading: running,
                    loadingLabel: problem.suggested == null
                        ? 'Setting up Flutter…'
                        : 'Setting up Flutter ${problem.suggested}…',
                    onPressed: running ? null : _start,
                  ),
              ],
            ),
            if (fix != null) ...[
              const SizedBox(height: XSpace.s3),
              if (done)
                XCallout(
                  status: XStatus.ready,
                  title: problem.suggested == null
                      ? 'Flutter is set up for iPhone builds'
                      : 'Flutter ${problem.suggested} is set up for iPhone '
                            'builds',
                  children: [
                    const Text(
                      'Your own Flutter is unchanged. Settings → Flutter for '
                      'iOS builds can switch back.',
                    ),
                    if (widget.onFixed != null) ...[
                      const SizedBox(height: XSpace.s2),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: XButton(
                          label: widget.retryLabel,
                          icon: Icons.replay,
                          onPressed: widget.onFixed,
                        ),
                      ),
                    ],
                  ],
                )
              else
                JobPanel(job: fix, consoleHeight: 180),
            ],
          ],
        );
      },
    );
  }
}

/// Settings card (feature 014): which Flutter iPhone builds use, with
/// "Use my own Flutter" (`xcross flutter sdk reset`) and the one-click fix.
class FlutterSdkSettingsCard extends StatefulWidget {
  const FlutterSdkSettingsCard({super.key});

  @override
  State<FlutterSdkSettingsCard> createState() => _FlutterSdkSettingsCardState();
}

class _FlutterSdkSettingsCardState extends State<FlutterSdkSettingsCard> {
  FlutterSdkStatus? _status;
  bool _loading = false;
  bool _started = false;
  Job? _action;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted || _loading) return;
    final jobs = Services.of(context).jobs;
    setState(() => _loading = true);
    final (_, events) = await jobs.collect(
      'Flutter for iOS builds',
      XcrossCommands.flutterSdkList(),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _status = events.whereType<FlutterSdkStatus>().firstOrNull ?? _status;
    });
  }

  void _run(String title, List<String> command) {
    final services = Services.of(context);
    final job = services.jobs.run(title, command, structured: true);
    setState(() => _action = job);
    job.done.then((status) {
      if (!mounted) return;
      _load();
      if (status == JobStatus.succeeded) services.readiness.runDoctor();
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final action = _action;
    final running = action?.isRunning ?? false;
    final suggested = status?.suggested;
    return XCard(
      title: 'Flutter for iOS builds',
      subtitle: 'From "xcross flutter sdk list".',
      trailing: XButton(
        label: 'Refresh',
        variant: XButtonVariant.text,
        loading: _loading,
        loadingLabel: 'Reading…',
        onPressed: _load,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (status == null)
            XNote(_loading ? 'Reading…' : 'Not read yet.')
          else ...[
            XCheckRow(
              status: XStatus.ready,
              label: 'iOS builds use Flutter ${status.activeVersion ?? '?'}',
              detail: status.activeManaged
                  ? 'Installed by $productName for iPhone builds · '
                        '${status.activeRoot ?? ''}'
                  : 'Your own Flutter · ${status.activeRoot ?? ''}',
            ),
            XCheckRow(
              status: switch (status.compiler) {
                'available' => XStatus.ready,
                'missing' => XStatus.failed,
                _ => XStatus.idle,
              },
              label: switch (status.compiler) {
                'available' => 'iOS release compiler available',
                'missing' => 'No iOS release compiler for this Flutter',
                _ => 'iOS release compiler not checked',
              },
              detail: status.compiler == 'missing' && suggested != null
                  ? 'iPhone release builds need Flutter $suggested.'
                  : status.detail,
            ),
            const SizedBox(height: XSpace.s3),
            Wrap(
              spacing: XSpace.s2,
              runSpacing: XSpace.s2,
              children: [
                if (status.compiler == 'missing' && suggested != null)
                  XButton(
                    label: 'Set up Flutter $suggested for iPhone builds',
                    icon: Icons.auto_fix_high,
                    loading: running,
                    loadingLabel: 'Working…',
                    onPressed: running
                        ? null
                        : () => _run(
                            'Set up Flutter $suggested for iPhone builds',
                            XcrossCommands.flutterSdkAuto(),
                          ),
                  ),
                if (status.activeManaged)
                  XButton(
                    label: 'Use my own Flutter',
                    icon: Icons.undo,
                    variant: XButtonVariant.secondary,
                    loading: running,
                    loadingLabel: 'Working…',
                    onPressed: running
                        ? null
                        : () => _run(
                            'Use my own Flutter',
                            XcrossCommands.flutterSdkReset(),
                          ),
                  ),
              ],
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: XSpace.s3),
            JobPanel(job: action, consoleHeight: 160),
          ],
        ],
      ),
    );
  }
}
