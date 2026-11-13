import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// The few things that differ between a Windows and a Linux host. Everything
/// else in the GUI is shared.
abstract class HostPlatform {
  const HostPlatform();

  /// The host this GUI runs on.
  factory HostPlatform.current() =>
      Platform.isWindows ? const WindowsHost() : const LinuxHost();

  String get name;

  /// Folder for the GUI's settings file.
  String configDirectory(Map<String, String> environment);

  /// The command that ends process [pid] and all of its children.
  List<String> killTreeCommand(int pid);

  /// The command that opens [path] in the file manager.
  List<String> openFolderCommand(String path);

  /// Opens [target] (folder or URL) through the app's own runner so that what
  /// it opens is not ended with the app; `false` when the runner cannot, and
  /// [openFolderCommand] is used instead.
  Future<bool> openOutsideApp(String target);

  /// [executable] + [arguments], wrapped so the child leads its own process
  /// group when the OS needs that for [killTreeCommand] to reach the whole
  /// tree.
  (String, List<String>) groupLeader(String executable, List<String> arguments);

  /// Variables to give every child on top of [inherited]: the OS's saved
  /// environment as it is now. A running app keeps the environment it was
  /// started with, so without this a stale parent, or a PATH edited after the
  /// app started, decides which Flutter and Swift `xcross` finds.
  Future<Map<String, String>> currentEnvironment(Map<String, String> inherited);
}

/// Windows: `taskkill /T` follows the parent chain; Explorer opens folders.
class WindowsHost extends HostPlatform {
  const WindowsHost();

  @override
  String get name => 'Windows';

  @override
  String configDirectory(Map<String, String> environment) {
    final base =
        environment['APPDATA'] ??
        p.windows.join(environment['USERPROFILE'] ?? '.', 'AppData', 'Roaming');
    // A fixed folder name, deliberately not productName: renaming the product
    // must not move or orphan existing settings (runbook S13).
    return p.windows.join(base, 'XCross Studio');
  }

  @override
  List<String> killTreeCommand(int pid) => [
    'taskkill',
    '/PID',
    '$pid',
    '/T',
    '/F',
  ];

  @override
  List<String> openFolderCommand(String path) => ['explorer', path];

  /// The runner (windows/runner/child_processes.h) ends every child with the
  /// app, so Explorer, and a browser it starts, run outside that job.
  static const shellChannel = MethodChannel('xcross_studio/shell');

  @override
  Future<bool> openOutsideApp(String target) async {
    try {
      return await shellChannel.invokeMethod<bool>('open', target) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  (String, List<String>) groupLeader(
    String executable,
    List<String> arguments,
  ) => (executable, arguments);

  static const _machineKey =
      r'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment';
  static const _userKey = r'HKCU\Environment';

  /// The variables saved in System settings (machine, then user), read from
  /// the registry for each child.
  @override
  Future<Map<String, String>> currentEnvironment(
    Map<String, String> inherited,
  ) async {
    Future<String> query(String key) async {
      try {
        final result = await Process.run('reg', ['query', key]);
        return result.exitCode == 0 ? '${result.stdout}' : '';
      } on ProcessException {
        return '';
      }
    }

    return mergeSaved(
      machine: await query(_machineKey),
      user: await query(_userKey),
      inherited: inherited,
    );
  }

  /// Windows composes a new process's environment from the machine variables,
  /// then the user variables (user wins), with `Path` as machine `Path`
  /// followed by user `Path`; `%NAME%` references are expanded. [machine]
  /// and [user] are `reg query` outputs. Keys keep [inherited]'s spelling
  /// (`Path`), since names are case-insensitive.
  static Map<String, String> mergeSaved({
    required String machine,
    required String user,
    required Map<String, String> inherited,
  }) {
    final machineValues = _parseRegQuery(machine);
    final userValues = _parseRegQuery(user);
    if (machineValues.isEmpty && userValues.isEmpty) return const {};
    String upper(String name) => name.toUpperCase();
    final saved = <String, String>{
      for (final MapEntry(:key, :value) in machineValues.entries)
        upper(key): value,
      for (final MapEntry(:key, :value) in userValues.entries)
        upper(key): value,
    };
    final machinePath = _valueOf(machineValues, 'PATH');
    final userPath = _valueOf(userValues, 'PATH');
    if (machinePath != null || userPath != null) {
      saved['PATH'] = [
        ?machinePath,
        ?userPath,
      ].where((part) => part.isNotEmpty).join(';');
    }
    final lookup = <String, String>{
      for (final MapEntry(:key, :value) in inherited.entries) upper(key): value,
      ...saved,
    };
    String expand(String value) => value.replaceAllMapped(
      RegExp('%([^%]+)%'),
      (match) => lookup[upper(match.group(1)!)] ?? match.group(0)!,
    );
    final spelling = {for (final key in inherited.keys) upper(key): key};
    final namesOf = {
      for (final key in [...machineValues.keys, ...userValues.keys])
        upper(key): key,
    };
    return {
      for (final MapEntry(:key, :value) in saved.entries)
        spelling[key] ?? namesOf[key] ?? key: expand(value),
    };
  }

  static String? _valueOf(Map<String, String> values, String name) {
    for (final MapEntry(:key, :value) in values.entries) {
      if (key.toUpperCase() == name) return value;
    }
    return null;
  }

  /// `    Name    REG_SZ    value` lines of a `reg query` output.
  static Map<String, String> _parseRegQuery(String output) {
    final values = <String, String>{};
    for (final line in const LineSplitter().convert(output)) {
      final match = RegExp(r'^\s{4}(.+?)\s{4}REG_(?:EXPAND_)?SZ(?:\s{4}(.*))?$')
          .firstMatch(line);
      if (match != null) values[match.group(1)!] = match.group(2) ?? '';
    }
    return values;
  }
}

/// Linux: the child is started through `setsid` (same pid, new process
/// group), so `kill -- -pid` ends xcross and the tools it started.
class LinuxHost extends HostPlatform {
  const LinuxHost();

  @override
  String get name => 'Linux';

  @override
  String configDirectory(Map<String, String> environment) {
    final xdg = environment['XDG_CONFIG_HOME'];
    final base = xdg != null && xdg.isNotEmpty
        ? xdg
        : p.posix.join(environment['HOME'] ?? '.', '.config');
    return p.posix.join(base, 'xcross-studio');
  }

  @override
  List<String> killTreeCommand(int pid) => ['kill', '-TERM', '--', '-$pid'];

  @override
  List<String> openFolderCommand(String path) => ['xdg-open', path];

  /// `xdg-open` already hands off to the desktop.
  @override
  Future<bool> openOutsideApp(String target) async => false;

  @override
  (String, List<String>) groupLeader(
    String executable,
    List<String> arguments,
  ) => ('setsid', [executable, ...arguments]);

  /// The login session's environment is the saved one: nothing to add.
  @override
  Future<Map<String, String>> currentEnvironment(
    Map<String, String> inherited,
  ) async => const {};
}
