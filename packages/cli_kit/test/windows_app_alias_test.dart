// studio: 009 — Windows app execution aliases (WindowsApps\winget.exe) are
// links Dart cannot follow; `which` must still find them.
import 'dart:io';

import 'package:cli_kit/host/linux/linux_host.dart';
import 'package:cli_kit/host/windows/windows_host.dart';
import 'package:cli_kit/host/windows/windows_paths.dart';
import 'package:cli_kit/shared/logging/logging.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:cli_kit/shared/process/process.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/test_log_output.dart';
import 'support/test_process_io.dart';

const _apps = r'C:\Users\u\AppData\Local\Microsoft\WindowsApps';
const _other = r'C:\Tools\broken';

void main() {
  final io = TestProcessIo();
  tearDownAll(io.close);
  final log = Log(output: TestLogOutput(emit: print));

  ProcessRunner<PlatformHostInterface> runnerFor(PlatformHostInterface host) =>
      ProcessRunner(
        host,
        log: log,
        stdinStream: io.input,
        stdoutSink: io.output,
        stderrSink: io.error,
      );

  const aliases = AliasFileSystem({
    '$_apps\\winget.exe',
    '$_apps\\python.exe',
    '$_other\\tool.exe',
  });
  const env = {'PATH': '$_other;$_apps', 'PATHEXT': '.EXE'};

  test('AC-009-6 winget in WindowsApps is found through its alias', () async {
    final runner = runnerFor(
      WindowsHost(
        environment: env,
        paths: WindowsPaths(context: p.windows),
        fileSystem: aliases,
      ),
    );
    final found = await runner.which('winget', environment: env);
    expect(found?.toLowerCase(), '$_apps\\winget.exe'.toLowerCase());
  });

  test('AC-009-6 python Store stubs and links elsewhere are ignored', () async {
    final runner = runnerFor(
      WindowsHost(
        environment: env,
        paths: WindowsPaths(context: p.windows),
        fileSystem: aliases,
      ),
    );
    expect(await runner.which('python', environment: env), isNull);
    expect(await runner.which('tool', environment: env), isNull);
  });

  test('AC-009-6 links outside a WindowsApps folder are never tools', () async {
    final runner = runnerFor(
      LinuxHost(
        environment: const {'PATH': '/apps/broken'},
        fileSystem: aliases,
      ),
    );
    expect(
      await runner.which('winget', environment: const {'PATH': '/apps/broken'}),
      isNull,
    );
  });
}

/// Case-insensitive (like NTFS) file system where [aliases] exist only as
/// unresolvable links (like app execution aliases) and nothing exists as a file.
@internal
final class AliasFileSystem implements HostFileSystemInterface {
  const AliasFileSystem(this.aliases);

  final Set<String> aliases;

  @override
  File file(String path) => File('${Directory.systemTemp.path}/missing-$path');

  @override
  Directory directory(String path) => Directory(path);

  @override
  Link link(String path) => AliasLink(
    path,
    present: aliases.any((a) => a.toLowerCase() == path.toLowerCase()),
  );

  @override
  void makeExecutable(String path) {}

  @override
  void setPermissions(String path, int mode) {}

  @override
  Future<void> createArchiveLink(String destination, String target) async {}
}

/// A [Link] that only answers [existsSync].
@internal
final class AliasLink implements Link {
  AliasLink(this.path, {required this.present});

  @override
  final String path;
  final bool present;

  @override
  bool existsSync() => present;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
