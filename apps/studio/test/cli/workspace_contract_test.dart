import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xcross_studio/src/cli/xcross_commands.dart';
import 'package:xcross_studio/src/cli/xcross_events.dart';
import 'package:xcross_studio/src/cli/secret_redactor.dart';
import 'package:xcross_studio/src/cli/process_launcher.dart';
import 'package:xcross_studio/src/cli/cli_capabilities.dart';
import 'package:xcross_studio/src/state/job.dart';

import '../support/fake_launcher.dart';

void main() {
  test(
    'AC-029-9 input sent to a job is not retained in console lines',
    () async {
      final launcher = FakeLauncher();
      final job = Job(
        title: 'Authentication',
        command: const ['auth', 'login'],
        invocation: const XcrossInvocation.binary(),
        launcher: launcher,
      );
      final starting = job.start();
      await Future<void>.delayed(Duration.zero);
      job.send('123456-secret');
      expect(launcher.processes.single.stdinLines, contains('123456-secret'));
      expect(
        job.lines.map((line) => line.text).join('\n'),
        isNot(contains('123456-secret')),
      );
      await launcher.processes.single.exit(0);
      await starting;
    },
  );

  test('AC-029-7 stdin secret echoed on both streams is sanitized', () async {
    final launcher = FakeLauncher();
    final job = Job(
      title: 'Authentication',
      command: const ['auth', 'login'],
      invocation: const XcrossInvocation.binary(),
      launcher: launcher,
    );
    final starting = job.start();
    await Future<void>.delayed(Duration.zero);
    job.send('one-time-secret-029');
    final process = launcher.processes.single;
    process.out('echo: one-time-secret-029');
    process.err('error: one-time-secret-029');
    await process.exit(1);
    await starting;
    expect(
      job.lines.map((line) => line.text).join('\n'),
      isNot(contains('one-time-secret-029')),
    );
  });

  test(
    'AC-029-7 password is redacted before lines and event callbacks',
    () async {
      final launcher = FakeLauncher();
      final events = <String>[];
      final job = Job(
        title: 'Authentication',
        command: const ['auth', 'login', '--password', 'unique-pass-123'],
        invocation: const XcrossInvocation.binary(),
        launcher: launcher,
        structured: true,
        onEvent: (event) {
          if (event is BuildLog) events.add(event.message);
        },
      );
      final starting = job.start();
      await Future<void>.delayed(Duration.zero);
      final process = launcher.processes.single;
      process.out('error: unique-pass-123');
      process.err('warning: unique-pass-123');
      process.out(
        '{"v":1,"type":"log","level":"info","message":"unique-pass-123"}',
      );
      await process.exit(1);
      await starting;
      final retained = job.lines.map((line) => line.text).join('\n');
      expect(retained, isNot(contains('unique-pass-123')));
      expect(events.join('\n'), isNot(contains('unique-pass-123')));
    },
  );

  test('AC-029-7 labelled secret values in text and JSON are hidden', () {
    final redactor = SecretRedactor(const []);
    expect(
      redactor.redact('token: bearer-value'),
      isNot(contains('bearer-value')),
    );
    expect(
      redactor.redact('{"password":"json-value"}'),
      isNot(contains('json-value')),
    );
  });

  test('AC-029-7 startup errors cannot retain a command secret', () async {
    final launcher = FakeLauncher(
      startError: const FormatException('startup-secret-029'),
    );
    final job = Job(
      title: 'Authentication',
      command: const ['auth', '--password', 'startup-secret-029'],
      invocation: const XcrossInvocation.binary(),
      launcher: launcher,
    );
    await job.start();
    expect(job.lines.map((line) => line.text).join('\n'),
        isNot(contains('startup-secret-029')));
  });

  test(
    'AC-029-7 PEM private key blocks are removed from retained output',
    () async {
      final launcher = FakeLauncher(
        onStart: (process, _) {
          process.out('-----BEGIN PRIVATE KEY-----');
          process.out('pem-secret-line');
          process.out('-----END PRIVATE KEY-----');
          Future<void>.delayed(Duration.zero, () => process.exit(0));
        },
      );
      final job = Job(
        title: 'Diagnostics',
        command: const ['doctor'],
        invocation: const XcrossInvocation.binary(),
        launcher: launcher,
      );
      await job.start();
      expect(
        job.lines.map((line) => line.text).join('\n'),
        isNot(contains('pem-secret-line')),
      );
    },
  );

  test('AC-029-7 inline secret arguments are hidden in command previews', () {
    expect(
      XcrossCommands.display(const ['auth', '--password=inline-value']),
      isNot(contains('inline-value')),
    );
  });

  test('AC-029-8 Windows batch shim is rejected before dispatch', () {
    expect(
      () => IoProcessLauncher.validateWindowsExecutable(r'C:\tools\xcross.cmd'),
      throwsUnsupportedError,
    );
  });

  test('AC-029-8 Windows executable resolution chooses only an exe', () {
    final directory = Directory.systemTemp.createTempSync('xcross-path-');
    try {
      final native = File('${directory.path}\\xcross.exe')
        ..writeAsStringSync('');
      File('${directory.path}\\xcross.cmd').writeAsStringSync('');
      expect(
        IoProcessLauncher.resolveWindowsExecutable('xcross', {
          'Path': directory.path,
        }),
        native.absolute.path,
      );
    } finally {
      directory.deleteSync(recursive: true);
    }
  });

  test('AC-029-8 capabilities require explicit command evidence and invalidate on change', () async {
    final launcher = FakeLauncher(
      onStart: (process, args) {
        if (args.single == '--version') {
          process.out('xcross 2.0.9');
        } else {
          process.out('''Usage: xcross <command>
Available commands:
  flutter      Flutter commands
  devices      List devices
Run "xcross help <command>" for more information.''');
        }
        Future<void>.delayed(Duration.zero, () => process.exit(0));
      },
    );
    final caps = CliCapabilities(
      launcher: launcher,
      invocation: const XcrossInvocation.binary(),
    );
    expect(caps.command('devices'), CapabilitySupport.unknown);
    await caps.refresh();
    expect(caps.probeError, isNull, reason: '${caps.probeError}');
    expect(caps.version, '2.0.9');
    expect(caps.command('devices'), CapabilitySupport.supported);
    expect(caps.command('sign'), CapabilitySupport.unsupported);
    expect(caps.structuredEvents, CapabilitySupport.unknown);
    caps.updateInvocation(const XcrossInvocation('other-xcross'));
    expect(caps.version, isNull);
    expect(caps.command('devices'), CapabilitySupport.unknown);
    caps.dispose();
  });
}
