import 'dart:io';

import 'package:flutter/material.dart';

import 'src/cli/process_launcher.dart';
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
