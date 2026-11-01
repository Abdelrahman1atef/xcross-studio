import 'dart:io';

import 'package:flutter/material.dart';

import 'src/cli/process_launcher.dart';
import 'src/cli/xcross_commands.dart';
import 'src/host/host_platform.dart';
import 'src/state/job.dart';
import 'src/state/log_session.dart';
import 'src/state/settings.dart';
import 'src/ui/services.dart';
import 'src/ui/studio_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final host = HostPlatform.current();
  final settings = await Settings.load(
    host.configDirectory(Platform.environment),
  );
  // A release bundle ships xcross next to the GUI; use it unless the user
  // chose another one.
  final bundled = XcrossInvocation.bundledNextTo(
    Platform.resolvedExecutable,
    windows: Platform.isWindows,
    exists: (path) => File(path).existsSync(),
  );
  if (bundled != null && settings.invocation.isDefault) {
    settings.invocation = XcrossInvocation.binary(bundled);
  }
  final launcher = IoProcessLauncher(host);
  final jobs = JobCenter(
    launcher: launcher,
    invocation: () => settings.invocation,
  );
  final logs = LogSession(jobs);
  runApp(
    StudioApp(
      services: (child) => Services(
        host: host,
        launcher: launcher,
        settings: settings,
        jobs: jobs,
        logs: logs,
        child: child,
      ),
    ),
  );
}
