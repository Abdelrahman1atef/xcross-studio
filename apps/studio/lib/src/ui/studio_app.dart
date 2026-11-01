import 'package:flutter/material.dart';

import 'console_page.dart';
import 'device_page.dart';
import 'logs_page.dart';
import 'project_page.dart';
import 'services.dart';
import 'setup_page.dart';

/// The XCross Studio window: a navigation rail over the five pages.
class StudioApp extends StatelessWidget {
  const StudioApp({super.key, required this.services});

  final Services Function(Widget child) services;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'XCross Studio',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: const Color(0xFF5B4BDB),
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorSchemeSeed: const Color(0xFF5B4BDB),
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    home: services(const StudioShell()),
  );
}

/// The rail and the selected page.
class StudioShell extends StatefulWidget {
  const StudioShell({super.key});

  @override
  State<StudioShell> createState() => _StudioShellState();
}

class _StudioShellState extends State<StudioShell> {
  int _index = 0;

  static const _destinations = [
    NavigationRailDestination(
      icon: Icon(Icons.settings_suggest_outlined),
      selectedIcon: Icon(Icons.settings_suggest),
      label: Text('Setup'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.folder_outlined),
      selectedIcon: Icon(Icons.folder),
      label: Text('Project'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.phone_iphone_outlined),
      selectedIcon: Icon(Icons.phone_iphone),
      label: Text('Device'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long),
      label: Text('Device logs'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.terminal_outlined),
      selectedIcon: Icon(Icons.terminal),
      label: Text('Console'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final pages = [
      const SetupPage(),
      ProjectPage(
        onInstall: (ipa) {
          services.settings.update((s) => s.lastIpa = ipa);
          setState(() => _index = 2);
        },
      ),
      const DevicePage(),
      const LogsPage(),
      const ConsolePage(),
    ];
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Icon(
                    Icons.phone_iphone,
                    size: 32,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'XCross\nStudio',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
            destinations: _destinations,
          ),
          const VerticalDivider(width: 1),
          Expanded(
            // Pages stay alive so running jobs keep their views.
            child: IndexedStack(index: _index, children: pages),
          ),
        ],
      ),
    );
  }
}
