// Feature 024: the live preview. One `xcross icons preview --serve` keeps
// running and draws each design, so the page shows what the CLI really makes
// without starting a process per change.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../src/cli/xcross_commands.dart';
import '../../src/cli/xcross_events.dart';
import '../../src/state/job.dart';

class PreviewServer extends ChangeNotifier {
  PreviewServer(this._jobs, {this.debounce = const Duration(milliseconds: 90)});

  final JobCenter _jobs;
  final Duration debounce;

  Directory? _folder;
  Job? _job;
  Timer? _timer;
  Map<String, Object?>? _pending;
  int _seq = 0;
  int? _waitingFor;
  bool _disposed = false;

  /// Images of the latest design by variant name, read into memory since the
  /// files are replaced by the next request.
  Map<String, Uint8List> images = const {};

  /// Why the latest design could not be drawn.
  String? error;

  /// The folder for previews and for rendered text and clipart.
  Directory get folder =>
      _folder ??= Directory.systemTemp.createTempSync('xcross-preview-');

  /// Draws [design] soon; a newer call replaces it.
  void request(Map<String, Object?> design) {
    _pending = design;
    _timer?.cancel();
    _timer = Timer(debounce, _flush);
  }

  void _flush() {
    // One at a time: what arrives meanwhile is drawn when the reply comes.
    if (_disposed || _waitingFor != null) return;
    final design = _pending;
    if (design == null) return;
    _pending = null;
    final job = _job;
    final server = job != null && job.isRunning
        ? job
        : _job = _jobs.background(
            'Icon preview',
            XcrossCommands.iconsPreviewServe(folder.path),
            onEvent: _onEvent,
          );
    final seq = ++_seq;
    _waitingFor = seq;
    server.send(jsonEncode({...design, 'seq': seq}));
    // A CLI without `icons preview` ends at once: say so instead of waiting.
    unawaited(
      server.done.then((status) {
        if (_disposed || !identical(server, _job) || _waitingFor == null) {
          return;
        }
        _waitingFor = null;
        final lines = server.lines.map((l) => l.text.trim());
        error = lines.lastWhere(
          (line) => line.isNotEmpty && !line.startsWith('{'),
          orElse: () => 'The preview stopped.',
        );
        notifyListeners();
      }),
    );
  }

  void _onEvent(XcrossEvent event) {
    if (event is! IconsPreview || _disposed) return;
    _waitingFor = null;
    if (event.error != null) {
      error = event.error;
    } else {
      error = null;
      images = {
        for (final MapEntry(:key, :value) in event.paths.entries)
          if (File(value).existsSync()) key: File(value).readAsBytesSync(),
      };
    }
    notifyListeners();
    _flush();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_cleanUp());
    super.dispose();
  }

  Future<void> _cleanUp() async {
    await _job?.cancel();
    try {
      await _folder?.delete(recursive: true);
    } on FileSystemException {
      // Still in use: the system cleans its temp folder.
    }
  }
}
