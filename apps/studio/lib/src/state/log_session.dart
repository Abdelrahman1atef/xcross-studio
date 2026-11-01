import 'dart:async';

import 'package:flutter/foundation.dart';

import '../cli/xcross_commands.dart';
import '../cli/xcross_events.dart';
import 'job.dart';

/// A live `xcross logs --json` stream with client-side filters.
class LogSession extends ChangeNotifier {
  LogSession(
    this.jobs, {
    this.capacity = 20000,
    this.notifyEvery = const Duration(milliseconds: 100),
  });

  final JobCenter jobs;

  /// Log lines are shown in batches at most this often (devices emit
  /// hundreds of lines per second). [Duration.zero] notifies per line.
  final Duration notifyEvery;
  Timer? _notifyTimer;

  /// Oldest lines are dropped beyond this many.
  final int capacity;

  final List<DeviceLogLine> _all = [];
  final List<DeviceLogLine> _pending = [];
  Job? job;
  PushDiagnosis? diagnosis;
  String? notice;
  bool paused = false;

  // Client-side filters (applied to what is already received).
  String textFilter = '';
  String processFilter = '';
  LogLevel minimumLevel = LogLevel.debug;

  bool get running => job?.isRunning ?? false;
  int get received => _all.length;

  /// Starts streaming with the server-side options (app, preset, …).
  void start({
    String? app,
    LogPreset? preset,
    String? udid,
    List<String> processes = const [],
    String? grep,
  }) {
    if (running) return;
    _all.clear();
    _pending.clear();
    diagnosis = null;
    notice = null;
    paused = false;
    job = jobs.run(
      preset == null ? 'Device logs' : 'Device logs (${preset.name})',
      XcrossCommands.logs(
        app: app,
        preset: preset,
        udid: udid,
        processes: processes,
        grep: grep,
      ),
      onEvent: _onEvent,
    )..addListener(notifyListeners);
    notifyListeners();
  }

  Future<void> stop() async => job?.cancel();

  void togglePause() {
    paused = !paused;
    if (!paused) {
      _all.addAll(_pending);
      _pending.clear();
      _trim();
    }
    notifyListeners();
  }

  void clear() {
    _all.clear();
    _pending.clear();
    notifyListeners();
  }

  void setFilters({String? text, String? process, LogLevel? level}) {
    textFilter = text ?? textFilter;
    processFilter = process ?? processFilter;
    minimumLevel = level ?? minimumLevel;
    notifyListeners();
  }

  /// The received lines that pass the filters, oldest first.
  List<DeviceLogLine> get visible {
    final text = textFilter.trim().toLowerCase();
    final process = processFilter.trim().toLowerCase();
    final minimum = minimumLevel.index;
    return [
      for (final line in _all)
        if (_levelIndex(line.level) >= minimum &&
            (process.isEmpty || line.process.toLowerCase().contains(process)) &&
            (text.isEmpty || line.message.toLowerCase().contains(text)))
          line,
    ];
  }

  /// The visible lines as text, for "Save" and "Copy".
  String visibleText() =>
      [for (final line in visible) line.toText()].join('\n');

  static int _levelIndex(String level) {
    for (final value in LogLevel.values) {
      if (value.name == level) return value.index;
    }
    return LogLevel.notice.index;
  }

  void _onEvent(XcrossEvent event) {
    switch (event) {
      case DeviceLogLine():
        (paused ? _pending : _all).add(event);
        if (paused && _pending.length > capacity) _pending.removeAt(0);
        _trim();
        if (paused) return;
        if (notifyEvery == Duration.zero) break;
        _notifyTimer ??= Timer(notifyEvery, () {
          _notifyTimer = null;
          notifyListeners();
        });
        return;
      case PushDiagnosis():
        diagnosis = event;
      case Notice(:final message):
        notice = message;
      default:
        return;
    }
    notifyListeners();
  }

  void _trim() {
    if (_all.length > capacity) _all.removeRange(0, _all.length - capacity);
  }

  @override
  void dispose() {
    _notifyTimer?.cancel();
    job?.removeListener(notifyListeners);
    super.dispose();
  }
}
