// Closing the app ends every job, background ones included: a leftover
// `devices --watch` kept the app's CLI file locked after the window closed.
import 'package:flutter_test/flutter_test.dart';
import 'package:xcross_studio/src/cli/xcross_commands.dart';
import 'package:xcross_studio/src/state/job.dart';

import '../support/fake_launcher.dart';

void main() {
  test(
    'stopAll ends running listed and background jobs, not finished ones',
    () async {
      final launcher = FakeLauncher(
        onStart: (process, arguments) async {
          // The watch and the long build never end on their own.
          if (arguments.contains('--watch') || arguments.contains('build')) {
            return;
          }
          await process.exit(0);
        },
      );
      final jobs = JobCenter(
        launcher: launcher,
        invocation: () => const XcrossInvocation.binary(),
      );
      final watch = jobs.background('Device watch', ['devices', '--watch']);
      final build = jobs.run('Build', ['flutter', 'build']);
      final done = jobs.run('Version', ['--version']);
      await done.done;
      await Future<void>.delayed(Duration.zero);
      expect(watch.isRunning, isTrue);

      expect(build.isRunning, isTrue);

      await jobs.stopAll();
      // The watch and the build; the finished job is left alone.
      expect(launcher.killed, hasLength(2));
    },
  );
}
