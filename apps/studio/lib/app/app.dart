import 'package:flutter/material.dart';

import '../design_system/theme/x_theme.dart';
import '../src/state/settings.dart';
import 'services.dart';
import 'shell.dart';

/// The XCross Studio application (feature 013 design system).
class StudioApp extends StatelessWidget {
  const StudioApp({
    super.key,
    required this.services,
    this.startupChecks = true,
  });

  final StudioServices services;

  /// Run the doctor, version and device listing on start (off in tests).
  final bool startupChecks;

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
