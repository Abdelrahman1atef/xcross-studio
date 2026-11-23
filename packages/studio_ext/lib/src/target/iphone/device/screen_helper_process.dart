// studio: 048 — a started `xcross-screen` helper process.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:studio_ext/target/iphone/device/screen_helper.dart';

/// A started helper process (stdout/stderr as lines, stdin close = stop).
@internal
final class HostScreenHelperProcess implements ScreenHelperProcess {
  HostScreenHelperProcess(this._process)
    : lines = _process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream(),
      errors = _process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();

  final Process _process;

  @override
  final Stream<String> lines;

  @override
  final Stream<String> errors;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void send(String line) {
    try {
      _process.stdin.writeln(line);
    } on Object {
      // Already gone.
    }
  }

  @override
  Future<void> stop({Duration grace = const Duration(seconds: 5)}) async {
    try {
      await _process.stdin.close();
    } on Object {
      // Already gone.
    }
    await _process.exitCode.timeout(
      grace,
      onTimeout: () {
        _process.kill();
        return -1;
      },
    );
  }
}
