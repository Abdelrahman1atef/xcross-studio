import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import '../design_system/theme/x_theme.dart';
import '../src/state/settings.dart';
import 'services.dart';
import 'shell.dart';

/// The XCross Studio application (feature 013 design system).
class StudioApp extends StatefulWidget {
  const StudioApp({
    super.key,
    required this.services,
    this.startupChecks = true,
  });

  final StudioServices services;

  /// Run the doctor, version and device listing on start (off in tests).
  final bool startupChecks;

  @override
  State<StudioApp> createState() => _StudioAppState();
}

class _StudioAppState extends State<StudioApp> {
  // Closing the window ends every job first: a background `devices --watch`
  // would otherwise keep running, and keep the app's CLI file locked.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: _stopJobs);
  }

  Future<AppExitResponse> _stopJobs() async {
    await widget.services.jobs.stopAll().timeout(
      const Duration(seconds: 3),
      onTimeout: () => <void>[],
    );
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  StudioServices get services => widget.services;

  bool get startupChecks => widget.startupChecks;

  @override
  Widget build(BuildContext context) => Services(
    services: services,
    child: ListenableBuilder(
      listenable: services.settings,
      builder: (context, _) => MaterialApp(
        title: 'XCross Studio',
        debugShowCheckedModeBanner: false,
        theme: xLightTheme(),
        darkTheme: xDarkTheme(),
        themeMode: switch (services.settings.theme) {
          ThemePreference.dark => ThemeMode.dark,
          ThemePreference.light => ThemeMode.light,
          ThemePreference.system => ThemeMode.system,
        },
        home: StudioShell(startupChecks: startupChecks),
      ),
    ),
  );
}
