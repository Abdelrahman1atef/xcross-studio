import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../cli/output_line.dart';
import '../cli/process_launcher.dart';
import '../cli/xcross_commands.dart';
import '../cli/xcross_events.dart';

enum JobStatus { running, succeeded, failed, cancelled }

/// One run of an xcross command: its output lines, NDJSON events and exit
/// status.
class Job extends ChangeNotifier {
  Job({
    required this.title,
    required this.command,
    required this.invocation,
    required this.launcher,
    this.workingDirectory,
    this.onEvent,
    this.maxLines = 5000,
    this.structured = false,
    DateTime Function() clock = DateTime.now,
  }) : _clock = clock,
       started = clock();

  final String title;
  final List<String> command;
  final XcrossInvocation invocation;
  final ProcessLauncher launcher;
  final String? workingDirectory;

  /// Receives every NDJSON event on stdout. Event lines are not added to
  /// [lines].
  final void Function(XcrossEvent event)? onEvent;

  /// Older lines are dropped beyond this many.
  final int maxLines;

  /// Run with `XCROSS_EVENTS=ndjson` (build, run, install, doctor): steps,
  /// progress, issues and artifacts arrive as events (feature 012). An older
  /// CLI ignores the variable and its text output is shown as before.
  final bool structured;

  /// Steps reported by the CLI, in order; a finished step replaces its start.
  final List<BuildStep> steps = [];

  /// The latest download/extraction progress.
  BuildProgress? progress;

  /// Built bundles and archives, in order.
  final List<BuildArtifact> artifacts = [];

  /// Doctor checks, in order.
  final List<DoctorCheckResult> checks = [];

  /// The device the CLI chose.
  ConnectedDevice? device;

  /// The exit code from the `done` event.
  int? reportedExitCode;

  /// The step running now.
  BuildStep? get currentStep {
    for (final step in steps.reversed) {
      if (step.status == 'start') return step;
    }
    return null;
  }

  /// The path of the last artifact of [kind] (`app` or `ipa`).
  String? artifact(String kind) {
    for (final artifact in artifacts.reversed) {
      if (artifact.kind == kind) return artifact.path;
    }
    return null;
  }

  final DateTime Function() _clock;
  final DateTime started;
  DateTime? finished;

  final List<OutputLine> lines = [];
  JobStatus status = JobStatus.running;
  int? exitCode;
  RunningProcess? _process;
  final _done = Completer<JobStatus>();
  bool _cancelRequested = false;

  /// Completes with the final status.
  Future<JobStatus> get done => _done.future;

  bool get isRunning => status == JobStatus.running;

  /// Error and warning lines (with their codes), for the issue summary.
  List<OutputLine> get issues => [
    for (final line in lines)
      if (line.isIssue) line,
  ];

  Duration get elapsed => (finished ?? _clock()).difference(started);

  /// The command as shown to the user (secrets masked).
  String get displayCommand => XcrossCommands.display(command);

  /// Starts the process. Output arrives through [lines] and [onEvent].
  Future<void> start() async {
    _add(OutputLine('\$ $displayCommand', LineKind.command));
    try {
      final process = await launcher.start(
        invocation.executable,
        invocation.argumentsFor(command),
        workingDirectory: workingDirectory,
        environment: {
          'XCROSS_OUTPUT_ENCODING': 'utf-8',
          'PYTHONIOENCODING': 'utf-8',
          'NO_COLOR': '1',
          if (structured) 'XCROSS_EVENTS': 'ndjson',
        },
      );
      _process = process;
      // Completion is captured at subscription time: the streams can end
      // before the exit code arrives.
      final outDone = Completer<void>();
      final errDone = Completer<void>();
      final out = _lines(process.stdout)
          .listen(_stdoutLine, onDone: outDone.complete);
      final err = _lines(process.stderr).listen(
        (line) => _add(OutputLine.classify(line, fromStderr: true)),
        onDone: errDone.complete,
      );
      final code = await process.exitCode;
      await Future.wait([outDone.future, errDone.future])
          .timeout(const Duration(seconds: 2), onTimeout: () => const []);
      await out.cancel();
      await err.cancel();
      _finish(
        code,
        _cancelRequested
            ? JobStatus.cancelled
            : code == 0
            ? JobStatus.succeeded
            : JobStatus.failed,
      );
    } on Exception catch (error) {
      _add(
        OutputLine(
          'error: could not start ${invocation.executable}: $error',
          LineKind.error,
        ),
      );
      _add(
        const OutputLine(
          'hint: set the xcross executable in Setup (an installed xcross, '
          'or "Run from source" with this repository).',
          LineKind.hint,
        ),
      );
      _finish(null, JobStatus.failed);
    }
  }

  /// Sends [input] to the command's stdin (2FA codes, `q`, …).
  void send(String input) {
    final process = _process;
    if (process == null || !isRunning) return;
    process.writeLine(input);
    _add(OutputLine('> ${input.isEmpty ? '⏎' : input}', LineKind.command));
  }

  /// Ends the command and the tools it started.
  Future<void> cancel() async {
    final process = _process;
    if (!isRunning || process == null) return;
    _cancelRequested = true;
    await launcher.killTree(process);
  }

  Stream<String> _lines(Stream<List<int>> bytes) => bytes
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter());

  void _stdoutLine(String line) {
    final (:text, :event) = XcrossEvent.split(line);
    if (event == null) {
      if (text.trim().isEmpty && lines.isNotEmpty && lines.last.text.isEmpty) {
        return;
      }
      _add(OutputLine.classify(text));
      return;
    }
    if (text.trim().isNotEmpty) _add(OutputLine.classify(text));
    _handle(event);
    onEvent?.call(event);
  }

  /// Folds a build event into the job's state and its output lines.
  void _handle(XcrossEvent event) {
    switch (event) {
      case BuildLog(:final level, :final message, :final stream):
        for (final part in message.split('\n')) {
          _add(
            level == 'trace' || stream == 'stderr'
                ? OutputLine(part, LineKind.stderr)
                : OutputLine.classify(part),
          );
        }
      case BuildIssue(:final isError, :final code, :final message, :final hint):
        _add(
          OutputLine(
            '${isError ? 'error' : 'warning'}: '
            '${code == null ? '' : '[$code] '}$message',
            isError ? LineKind.error : LineKind.warning,
            code: code,
          ),
        );
        if (hint != null && hint.isNotEmpty) {
          _add(OutputLine('hint: $hint', LineKind.hint));
        }
      case BuildStep(:final name, :final status):
        final start = steps.lastIndexWhere(
          (step) => step.name == name && step.status == 'start',
        );
        if (status != 'start' && start >= 0) {
          steps[start] = event;
        } else {
          steps.add(event);
        }
        _add(_stepLine(event));
      case BuildProgress():
        progress = event;
        notifyListeners();
      case BuildArtifact():
        artifacts.add(event);
        notifyListeners();
      case DoctorCheckResult():
        checks.add(event);
        notifyListeners();
      case ConnectedDevice():
        device = event;
        notifyListeners();
      case BuildDone(:final exitCode):
        reportedExitCode = exitCode;
        notifyListeners();
      default:
        return;
    }
  }

  static OutputLine _stepLine(BuildStep step) {
    final elapsed = step.elapsedMs == null
        ? ''
        : '  ${(step.elapsedMs! / 1000).toStringAsFixed(1)}s';
    return switch (step.status) {
      'done' => OutputLine('✔ ${step.name}$elapsed', LineKind.success),
      'failed' => OutputLine(
        '✖ ${step.message ?? step.name}',
        LineKind.failure,
      ),
      _ => OutputLine('${step.name}…', LineKind.plain),
    };
  }

  void _add(OutputLine line) {
    lines.add(line);
    if (lines.length > maxLines) lines.removeRange(0, lines.length - maxLines);
    notifyListeners();
  }

  void _finish(int? code, JobStatus result) {
    exitCode = code;
    status = result;
    finished = _clock();
    if (!_done.isCompleted) _done.complete(result);
    notifyListeners();
  }
}

/// All jobs of this session, newest last.
class JobCenter extends ChangeNotifier {
  JobCenter({required this.launcher, required this.invocation});

  final ProcessLauncher launcher;

  /// Read at start time, so a Setup change applies to the next job.
  XcrossInvocation Function() invocation;

  final List<Job> jobs = [];

  /// Starts [command] as a new job.
  Job run(
    String title,
    List<String> command, {
    String? workingDirectory,
    void Function(XcrossEvent event)? onEvent,
    bool structured = false,
  }) {
    final job = Job(
      title: title,
      command: command,
      invocation: invocation(),
      launcher: launcher,
      workingDirectory: workingDirectory,
      onEvent: onEvent,
      structured: structured,
    );
    jobs.add(job);
    job.addListener(notifyListeners);
    notifyListeners();
    unawaited(job.start());
    return job;
  }

  /// Starts [command] as a job that is not listed in the console or counted
  /// as running (feature 017's device watch runs for the whole session).
  Job background(
    String title,
    List<String> command, {
    void Function(XcrossEvent event)? onEvent,
  }) {
    final job = Job(
      title: title,
      command: command,
      invocation: invocation(),
      launcher: launcher,
      onEvent: onEvent,
      maxLines: 200,
    );
    unawaited(job.start());
    return job;
  }

  /// Runs [command] and returns its NDJSON events once it ends.
  Future<(Job, List<XcrossEvent>)> collect(
    String title,
    List<String> command, {
    String? workingDirectory,
  }) async {
    final events = <XcrossEvent>[];
    final job = run(
      title,
      command,
      workingDirectory: workingDirectory,
      onEvent: events.add,
    );
    await job.done;
    return (job, events);
  }

  bool get anyRunning => jobs.any((job) => job.isRunning);

  void clearFinished() {
    jobs.removeWhere((job) {
      if (job.isRunning) return false;
      job.removeListener(notifyListeners);
      return true;
    });
    notifyListeners();
  }
}
