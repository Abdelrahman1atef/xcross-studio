// studio: 025 — a tool that hangs after an error, with a real process.
import 'dart:io';

import 'package:cli_kit/host/linux/linux_host.dart';
import 'package:cli_kit/host/macos/macos_host.dart';
import 'package:cli_kit/host/windows/windows_host.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:cli_kit/shared/logging/logging.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:cli_kit/shared/process/process.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/test_log_output.dart';
import 'support/test_process_io.dart';

void main() {
  late Directory temp;
  late TestProcessIo io;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('xcross_stall_');
    io = TestProcessIo();
  });
  tearDown(() async {
    await io.close();
    temp.deleteSync(recursive: true);
  });

  PlatformHostInterface host() => Platform.isWindows
      ? WindowsHost()
      : Platform.isMacOS
      ? MacOSHost()
      : LinuxHost();

  ProcessRunner<PlatformHostInterface> runner() => ProcessRunner(
    host(),
    log: Log(output: TestLogOutput(emit: (_) {})),
    stdinStream: io.input,
    stdoutSink: io.output,
    stderrSink: io.error,
  );

  /// A Dart script with [body] in `main`.
  String script(String body) {
    final file = File(p.join(temp.path, 'tool.dart'))
      ..writeAsStringSync("import 'dart:io';\nvoid main() async {\n$body\n}\n");
    return file.path;
  }

  test('AC-025-5 a tool silent after an error is ended, and says so', () async {
    final tool = script('''
  stderr.writeln('a.m:1:1: error: nope');
  await stderr.flush();
  await Future<void>.delayed(const Duration(minutes: 5));
''');
    final started = DateTime.now();
    await expectLater(
      runner().runChecked(
        Platform.resolvedExecutable,
        [tool],
        workingDirectory: temp.path,
        environment: Platform.environment,
        captureAndEcho: true,
        stallAfterError: const Duration(seconds: 2),
      ),
      throwsA(
        isA<CliError>().having(
          (error) => error.toString(),
          'message',
          allOf(contains('error: nope'), contains('so it was ended')),
        ),
      ),
    );
    expect(DateTime.now().difference(started).inSeconds, lessThan(60));
  });

  test('AC-025-5 a tool that keeps working is not ended', () async {
    final tool = script('''
  stderr.writeln('a.m:1:1: error: nope');
  await stderr.flush();
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    stdout.writeln('still compiling');
    await stdout.flush();
  }
''');
    await runner().runChecked(
      Platform.resolvedExecutable,
      [tool],
      workingDirectory: temp.path,
      environment: Platform.environment,
      captureAndEcho: true,
      stallAfterError: const Duration(seconds: 2),
    );
  });
}
