import 'package:flutter/foundation.dart';

import '../src/state/job.dart';

/// The destinations of the sidebar (design system §4).
enum Destination {
  overview,
  build,
  devices,
  signing,
  logs,
  plugins,

  /// Feature 023: the app icon set, checked and previewed.
  icons,

  /// Feature 022: the App Store release in order.
  release,

  /// Feature 022: the archives xcross built.
  archives,
  settings,
}

/// Navigation and console-dock state of the shell (feature 013).
class AppController extends ChangeNotifier {
  Destination destination = Destination.overview;

  /// The job the console dock shows; `null` follows the newest job.
  Job? consoleJob;

  /// Set by the shell: opens the first-run wizard.
  VoidCallback? openWizard;

  /// Set by the shell: opens the console dock.
  VoidCallback? openConsole;

  void go(Destination to) {
    if (destination == to) return;
    destination = to;
    notifyListeners();
  }

  /// Shows [job] in the console dock and opens it.
  void showJob(Job job) {
    consoleJob = job;
    openConsole?.call();
    notifyListeners();
  }
}
