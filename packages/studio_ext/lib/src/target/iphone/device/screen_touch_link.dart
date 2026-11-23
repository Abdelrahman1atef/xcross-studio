// studio: 048 — a running touch helper (WebDriverAgent started with XCTest,
// its port forwarded to 127.0.0.1) and the processes behind it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:studio_ext/target/iphone/device/screen_touch.dart';

/// The XCTest runner and the port forward; either one ending ends touch.
@internal
final class WdaTouchLink implements ScreenTouchLink {
  WdaTouchLink({
    required this.url,
    required TouchProcess runner,
    required TouchProcess forward,
  }) : _runner = runner,
       _forward = forward {
    // Always read both outputs, so a full pipe never blocks them.
    runner.output.listen(_remember);
    forward.output.listen(_remember);
    ended = Future.any([
      runner.exitCode,
      forward.exitCode,
    ]).then((_) => lastProblem(_tail));
  }

  @override
  final String url;

  final TouchProcess _runner;
  final TouchProcess _forward;
  final _tail = <String>[];

  @override
  late final Future<String> ended;

  void _remember(String line) {
    if (line.trim().isEmpty) return;
    _tail.add(line.trim());
    if (_tail.length > 40) _tail.removeAt(0);
  }

  @override
  Future<void> close() async {
    await Future.wait([_runner.kill(), _forward.kill()]);
  }

  /// The most telling recent line: the last error, else the last line, without
  /// pymobiledevice3's time stamp and process prefix.
  static String lastProblem(List<String> lines) {
    final pick = lines.lastWhere(
      (l) => l.contains('ERROR') || l.contains('Error'),
      orElse: () => lines.isEmpty ? '' : lines.last,
    );
    final cut = pick.indexOf(RegExp(r'\b(ERROR|WARNING|INFO)\b'));
    final text = cut < 0
        ? pick
        : pick
              .substring(cut)
              .replaceFirst(RegExp(r'^(ERROR|WARNING|INFO)\s*'), '');
    return text.length > 200 ? '${text.substring(0, 200)}…' : text;
  }
}

/// A started tool process as a [TouchProcess].
@internal
final class HostTouchProcess implements TouchProcess {
  HostTouchProcess(this._process, this._processes)
    : output = StreamGroupLines.merge(_process.stdout, _process.stderr);

  final Process _process;
  final HostProcessInterface _processes;

  @override
  final Stream<String> output;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<void> kill() async {
    try {
      await _processes.killTree(_process);
    } on Object {
      _process.kill();
    }
  }
}

/// stdout and stderr as one stream of lines.
@internal
abstract final class StreamGroupLines {
  static Stream<String> merge(Stream<List<int>> a, Stream<List<int>> b) {
    final out = StreamController<String>();
    var open = 2;
    void add(Stream<List<int>> s) => s
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          out.add,
          onDone: () {
            if (--open == 0) unawaited(out.close());
          },
        );
    add(a);
    add(b);
    return out.stream;
  }
}
