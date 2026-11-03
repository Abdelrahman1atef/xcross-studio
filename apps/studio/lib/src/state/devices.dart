import 'dart:async';

import 'package:flutter/foundation.dart';

import '../cli/xcross_commands.dart';
import '../cli/xcross_events.dart';
import 'job.dart';
import 'settings.dart';

/// The connected iPhones from `xcross devices --json`, shared by the top
/// bar, Build & Run and Devices (feature 013), kept live by
/// `xcross devices --watch --json` (feature 017).
class DeviceController extends ChangeNotifier {
  DeviceController(
    this.jobs,
    this.settings, {
    this.restartDelay = const Duration(seconds: 3),
    this.minimumWatchRun = const Duration(seconds: 10),
    this.clock = DateTime.now,
  });

  final JobCenter jobs;
  final Settings settings;

  /// Wait before restarting a watch that ended.
  final Duration restartDelay;

  /// A watch that ends sooner than this is an older CLI without `--watch`
  /// (or one that cannot run it): Refresh stays the only way, no restart.
  final Duration minimumWatchRun;

  /// Injected in tests.
  final DateTime Function() clock;

  /// `null` until the first listing finishes.
  List<ConnectedDevice>? devices;

  /// The last listing job (its issues explain an empty list).
  Job? listing;
  bool refreshing = false;

  /// The watch reported that the device service is not reachable.
  bool serviceDown = false;

  Job? _watch;
  Timer? _restart;
  bool _disposed = false;

  /// Whether a live watch is running.
  bool get watching => _watch?.isRunning ?? false;

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
    _apply(events.whereType<ConnectedDevice>().toList());
    refreshing = false;
    notifyListeners();
  }

  /// Starts `xcross devices --watch --json` in the background (feature 017).
  void watch() {
    if (_disposed || watching) return;
    _restart?.cancel();
    final started = clock();
    final job = jobs.background(
      'Watch devices',
      XcrossCommands.devicesWatch(),
      onEvent: (event) {
        switch (event) {
          case DeviceSnapshot(:final devices):
            serviceDown = false;
            _apply(devices);
            notifyListeners();
          case Notice(:final message) when message.contains('not reachable'):
            serviceDown = true;
            notifyListeners();
          default:
        }
      },
    );
    _watch = job;
    unawaited(
      job.done.then((_) {
        if (_disposed) return;
        notifyListeners();
        if (clock().difference(started) >= minimumWatchRun) {
          _restart = Timer(restartDelay, watch);
        }
      }),
    );
  }

  void _apply(List<ConnectedDevice> found) {
    devices = found;
    if (found.length == 1 && settings.udid != found.single.udid) {
      unawaited(settings.update((s) => s.udid = found.single.udid));
    }
  }

  Future<void> select(String udid) => settings.update((s) => s.udid = udid);

  @override
  void dispose() {
    _disposed = true;
    _restart?.cancel();
    unawaited(_watch?.cancel());
    super.dispose();
  }
}
