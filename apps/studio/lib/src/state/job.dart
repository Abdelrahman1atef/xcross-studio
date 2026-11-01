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
        environment: const {
          'XCROSS_OUTPUT_ENCODING': 'utf-8',
          'PYTHONIOENCODING': 'utf-8',
          'NO_COLOR': '1',
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
    final event = XcrossEvent.tryParse(line);
    if (event != null) {
      onEvent?.call(event);
      return;
    }
    if (line.trim().isEmpty && lines.isNotEmpty && lines.last.text.isEmpty) {
      return;
    }
    _add(OutputLine.classify(line));
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
  }) {
    final job = Job(
      title: title,
      command: command,
      invocation: invocation(),
      launcher: launcher,
      workingDirectory: workingDirectory,
      onEvent: onEvent,
    );
    jobs.add(job);
    job.addListener(notifyListeners);
    notifyListeners();
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
