import 'dart:io';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/services.dart';
import 'src/cli/process_launcher.dart';
import 'src/cli/xcross_commands.dart';
import 'src/host/host_platform.dart';
import 'src/state/job.dart';
import 'src/state/settings.dart';
import 'src/state/signing_accounts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final host = HostPlatform.current();
  final settings = await Settings.load(
    host.configDirectory(Platform.environment),
  );
  // A release bundle ships xcross next to the GUI; the default choice uses
  // it, resolved for each job and never saved as a path.
  bool exists(String path) => File(path).existsSync();
  settings.bundledXcross = XcrossInvocation.bundledNextTo(
    Platform.resolvedExecutable,
    windows: Platform.isWindows,
    exists: exists,
  );
  // Older versions saved the bundled CLI's absolute path as the choice.
  if (XcrossInvocation.isStudioBundled(
    settings.invocation.executable,
    windows: Platform.isWindows,
    exists: exists,
  )) {
    settings.invocation = const XcrossInvocation.binary();
  }
  // studio: 030 — the first run also reads the profiles the `xcross-key`
  // script saved, so the accounts used before are already listed.
  final appData = Platform.environment['APPDATA'];
  final signingAccounts = await SigningAccounts.load(
    host.configDirectory(Platform.environment),
    importFrom: appData == null
        ? null
        : File(
            '$appData${Platform.pathSeparator}xcross'
            '${Platform.pathSeparator}key-profiles.json',
          ),
  );
  final launcher = IoProcessLauncher(host);
  final jobs = JobCenter(
    launcher: launcher,
    invocation: () => settings.effectiveInvocation,
  );
  runApp(
    StudioApp(
      services: StudioServices(
        host: host,
        launcher: launcher,
        settings: settings,
        jobs: jobs,
        signingAccounts: signingAccounts,
      ),
    ),
  );
}
