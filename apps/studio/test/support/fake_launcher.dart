import 'dart:async';
import 'dart:convert';

import 'package:xcross_studio/src/cli/process_launcher.dart';

/// A scripted child process.
class FakeProcess implements RunningProcess {
  FakeProcess({this.pid = 4242});

  @override
  final int pid;
  final _stdout = StreamController<List<int>>();
  final _stderr = StreamController<List<int>>();
  final _exit = Completer<int>();
  final List<String> stdinLines = [];

  void out(String line) => _stdout.add(utf8.encode('$line\n'));
  void err(String line) => _stderr.add(utf8.encode('$line\n'));

  Future<void> exit(int code) async {
    await _stdout.close();
    await _stderr.close();
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void writeLine(String line) => stdinLines.add(line);
}

/// Records starts and hands out [FakeProcess]es.
class FakeLauncher implements ProcessLauncher {
  FakeLauncher({this.startError, this.onStart});

  final Exception? startError;

  /// Scripts the process for a start (`arguments` without the prefix).
  final void Function(FakeProcess process, List<String> arguments)? onStart;

  final List<
    ({
      String executable,
      List<String> arguments,
      String? workingDirectory,
      Map<String, String> environment,
    })
  >
  starts = [];
  final List<FakeProcess> processes = [];
  final List<int> killed = [];
  final List<String> opened = [];

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String> environment = const {},
  }) async {
    starts.add((
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    ));
    if (startError case final error?) throw error;
    final process = FakeProcess(pid: 4242 + processes.length);
    processes.add(process);
    onStart?.call(process, arguments);
    return process;
  }

  @override
  Future<void> killTree(RunningProcess process) async {
    killed.add(process.pid);
    if (process is FakeProcess) await process.exit(-15);
  }

  @override
  Future<void> openFolder(String path) async => opened.add(path);

  @override
  Future<void> openUrl(String url) async => opened.add(url);
}
