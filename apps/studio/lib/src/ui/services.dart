import 'package:flutter/widgets.dart';

import '../cli/process_launcher.dart';
import '../host/host_platform.dart';
import '../state/job.dart';
import '../state/log_session.dart';
import '../state/settings.dart';

/// The app's long-lived objects, handed down the widget tree.
class Services extends InheritedWidget {
  const Services({
    super.key,
    required this.host,
    required this.launcher,
    required this.settings,
    required this.jobs,
    required this.logs,
    required super.child,
  });

  final HostPlatform host;
  final ProcessLauncher launcher;
  final Settings settings;
  final JobCenter jobs;
  final LogSession logs;

  static Services of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Services>()!;

  @override
  bool updateShouldNotify(Services oldWidget) => false;
}
