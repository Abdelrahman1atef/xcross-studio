import 'package:flutter/widgets.dart';

import '../src/cli/process_launcher.dart';
import '../src/cli/cli_capabilities.dart';
import '../src/host/host_platform.dart';
import '../src/state/devices.dart';
import '../src/state/job.dart';
import '../src/state/log_session.dart';
import '../src/state/project_health.dart';
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
    ProjectHealthController? projectHealth,
    CliCapabilities? capabilities,
  }) : logs = logs ?? LogSession(jobs),
       readiness = readiness ?? ReadinessController(jobs, settings),
       devices = devices ?? DeviceController(jobs, settings),
       app = app ?? AppController(),
       projectHealth = projectHealth ?? ProjectHealthController(jobs, settings),
       capabilities =
           capabilities ??
           CliCapabilities(
             launcher: launcher,
             invocation: settings.effectiveInvocation,
           ) {
    settings.addListener(_invocationChanged);
  }

  void _invocationChanged() =>
      capabilities.updateInvocation(settings.effectiveInvocation);

  final HostPlatform host;
  final ProcessLauncher launcher;
  final Settings settings;
  final JobCenter jobs;
  final LogSession logs;
  final ReadinessController readiness;
  final DeviceController devices;
  final AppController app;

  /// What the open project needs (features 027 and 028).
  final ProjectHealthController projectHealth;
  final CliCapabilities capabilities;
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
