import 'dart:async';

/// Notices a tool that printed an error and then went silent.
///
/// `swift build` can stop after a compile error with a compiler still running
/// behind it, and nothing then ends the build. Output that keeps coming means
/// the tool is still working, so only silence after an error counts.
final class ErrorStallWatchdog {
  ErrorStallWatchdog({required this.limit, required this.onStall});

  /// How long the tool may stay silent after an error.
  final Duration limit;
  final void Function() onStall;

  Timer? _timer;
  bool _armed = false;
  bool _stalled = false;

  /// Whether [onStall] has run.
  bool get stalled => _stalled;

  /// Records [output] from the tool.
  void saw(String output) {
    if (!_armed && output.contains('error:')) _armed = true;
    if (!_armed) return;
    _timer?.cancel();
    _timer = Timer(limit, () {
      _stalled = true;
      onStall();
    });
  }

  /// The tool has ended.
  void stop() => _timer?.cancel();
}
