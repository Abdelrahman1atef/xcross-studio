import 'package:flutter/widgets.dart';

import '../src/cli/process_launcher.dart';
import '../src/host/host_platform.dart';
import '../src/state/devices.dart';
import '../src/state/job.dart';
import '../src/state/log_session.dart';
import '../src/state/readiness.dart';
import '../src/state/settings.dart';
import 'app_controller.dart';

/// The app's long-lived objects, created once.
class StudioServices {
  StudioServices({
    required this.host,
    required this.launcher,
    required this.settings,
    required this.jobs,
    LogSession? logs,
    ReadinessController? readiness,
    DeviceController? devices,
    AppController? app,
  }) : logs = logs ?? LogSession(jobs),
       readiness = readiness ?? ReadinessController(jobs, settings),
       devices = devices ?? DeviceController(jobs, settings),
       app = app ?? AppController();

  final HostPlatform host;
  final ProcessLauncher launcher;
  final Settings settings;
  final JobCenter jobs;
  final LogSession logs;
  final ReadinessController readiness;
  final DeviceController devices;
  final AppController app;
}

/// Hands [StudioServices] down the widget tree.
class Services extends InheritedWidget {
  const Services({super.key, required this.services, required super.child});

  final StudioServices services;

  static StudioServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Services>()!.services;

  @override
  bool updateShouldNotify(Services oldWidget) => oldWidget.services != services;
}
