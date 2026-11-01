import 'package:flutter/foundation.dart';

import '../cli/xcross_commands.dart';
import '../cli/xcross_events.dart';
import 'job.dart';
import 'settings.dart';

/// The connected iPhones from `xcross devices --json`, shared by the top
/// bar, Build & Run and Devices (feature 013).
class DeviceController extends ChangeNotifier {
  DeviceController(this.jobs, this.settings);

  final JobCenter jobs;
  final Settings settings;

  /// `null` until the first listing finishes.
  List<ConnectedDevice>? devices;

  /// The last listing job (its issues explain an empty list).
  Job? listing;
  bool refreshing = false;

  /// The device chosen in settings, when it is connected.
  ConnectedDevice? get selected {
    for (final device in devices ?? const <ConnectedDevice>[]) {
      if (device.udid == settings.udid) return device;
    }
    return null;
  }

  Future<void> refresh() async {
    if (refreshing) return;
    refreshing = true;
    notifyListeners();
    final (job, events) = await jobs.collect(
      'List devices',
      XcrossCommands.devices(),
    );
    listing = job;
    devices = events.whereType<ConnectedDevice>().toList();
    refreshing = false;
    notifyListeners();
    final found = devices!;
    if (found.length == 1 && settings.udid != found.single.udid) {
      await settings.update((s) => s.udid = found.single.udid);
    }
  }

  Future<void> select(String udid) => settings.update((s) => s.udid = udid);
}
