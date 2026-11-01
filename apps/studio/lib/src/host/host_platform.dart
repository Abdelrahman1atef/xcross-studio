import 'dart:io';

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

  /// [executable] + [arguments], wrapped so the child leads its own process
  /// group when the OS needs that for [killTreeCommand] to reach the whole
  /// tree.
  (String, List<String>) groupLeader(String executable, List<String> arguments);
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

  @override
  (String, List<String>) groupLeader(
    String executable,
    List<String> arguments,
  ) => (executable, arguments);
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

  @override
  (String, List<String>) groupLeader(
    String executable,
    List<String> arguments,
  ) => ('setsid', [executable, ...arguments]);
}
