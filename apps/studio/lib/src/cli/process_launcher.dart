import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../host/host_platform.dart';

/// A started child process, as much of it as a job needs.
abstract class RunningProcess {
  int get pid;
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;

  /// Writes [line] plus a newline to the child's stdin.
  void writeLine(String line);
}

/// Starts processes and ends them with their children. Faked in tests.
abstract class ProcessLauncher {
  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String> environment = const {},
  });

  /// Ends [process] and every process it started.
  Future<void> killTree(RunningProcess process);

  /// Opens [path] in the file manager.
  Future<void> openFolder(String path);

  /// Opens [url] in the default browser.
  Future<void> openUrl(String url);
}

/// [ProcessLauncher] over `dart:io`.
class IoProcessLauncher implements ProcessLauncher {
  IoProcessLauncher(this.host);

  final HostPlatform host;

  /// Batch files are parsed by cmd.exe even when Dart's runInShell is false.
  /// Require a native executable for the CLI boundary on Windows.
  static void validateWindowsExecutable(String executable) {
    final lower = executable.toLowerCase();
    if (lower.endsWith('.bat') || lower.endsWith('.cmd')) {
      throw UnsupportedError(
        'Windows batch shims are not supported; select xcross.exe or dart.exe.',
      );
    }
  }

  static String resolveWindowsExecutable(
    String executable,
    Map<String, String> environment,
  ) {
    validateWindowsExecutable(executable);
    final name = executable.toLowerCase().endsWith('.exe')
        ? executable
        : '$executable.exe';
    if (p.windows.isAbsolute(name) ||
        name.contains('\\') ||
        name.contains('/')) {
      if (File(name).existsSync()) return File(name).absolute.path;
      throw UnsupportedError('Windows native executable not found: $name');
    }
    final path = environment.entries
        .where((entry) => entry.key.toLowerCase() == 'path')
        .map((entry) => entry.value)
        .firstOrNull;
    for (final directory in (path ?? '').split(';')) {
      if (directory.isEmpty) continue;
      final candidate = p.windows.join(directory, name);
      if (File(candidate).existsSync()) return File(candidate).absolute.path;
    }
    throw UnsupportedError(
      'Windows native executable $name was not found on PATH. '
      'Select an .exe binary in Setup.',
    );
  }

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String> environment = const {},
  }) async {
    final (command, args) = host.groupLeader(executable, arguments);
    // Every child gets the variables saved in the OS now (PATH, SDKROOT, …),
    // not the snapshot this app was started with.
    final saved = await host.currentEnvironment(Platform.environment);
    final nativeCommand = Platform.isWindows
        ? resolveWindowsExecutable(command, saved)
        : command;
    final process = await Process.start(
      nativeCommand,
      args,
      workingDirectory: workingDirectory,
      environment: {...saved, ...environment},
      runInShell: false,
    );
    return _IoRunningProcess(process);
  }

  @override
  Future<void> killTree(RunningProcess process) async {
    final command = host.killTreeCommand(process.pid);
    try {
      await Process.run(command.first, command.sublist(1));
    } on ProcessException {
      // Fall through to the direct kill below.
    }
    if (process is _IoRunningProcess) process.process.kill();
  }

  // explorer / xdg-open hand an http(s) URL to the default browser.
  @override
  Future<void> openUrl(String url) => openFolder(url);

  @override
  Future<void> openFolder(String path) async {
    if (await host.openOutsideApp(path)) return;
    final command = host.openFolderCommand(path);
    await Process.start(
      command.first,
      command.sublist(1),
      mode: ProcessStartMode.detached,
    );
  }
}

class _IoRunningProcess implements RunningProcess {
  _IoRunningProcess(this.process);

  final Process process;

  @override
  int get pid => process.pid;

  @override
  Stream<List<int>> get stdout => process.stdout;

  @override
  Stream<List<int>> get stderr => process.stderr;

  @override
  Future<int> get exitCode => process.exitCode;

  @override
  void writeLine(String line) {
    process.stdin.add(utf8.encode('$line\n'));
    unawaited(process.stdin.flush().catchError((Object _) {}));
  }
}
