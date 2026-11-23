// studio: 048 — the bundled iPhone screen helper (`xcross-screen`, Rust).
import 'dart:async';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:studio_ext/src/target/iphone/device/screen_helper_process.dart';

/// Finds and starts the `xcross-screen` helper that ships with the engine.
abstract interface class ScreenHelper {
  /// Absolute path of the helper, or null when this engine has none.
  String? locate();

  /// Starts the helper with [args]; null when [locate] finds nothing.
  Future<ScreenHelperProcess?> start(List<String> args);
}

/// A running helper: its stdout/stderr lines, its exit code, and a way to stop it.
abstract interface class ScreenHelperProcess {
  Stream<String> get lines;
  Stream<String> get errors;
  Future<int> get exitCode;

  /// Asks the helper to stop (closes its stdin); kills it if it has not ended
  /// after [grace].
  Future<void> stop({Duration grace = const Duration(seconds: 5)});
}

/// The real helper: `XCROSS_SCREEN_HELPER`, else next to the xcross
/// executable, else `../libexec/` of the engine.
final class HostScreenHelper implements ScreenHelper {
  HostScreenHelper({
    required PlatformHostInterface host,
    required String xcrossExecutable,
  }) : _host = host,
       _xcrossExecutable = xcrossExecutable;

  final PlatformHostInterface _host;
  final String _xcrossExecutable;

  @override
  String? locate() {
    final files = _host.fileSystem;
    final override = _host.environment.values['XCROSS_SCREEN_HELPER'];
    if (override != null && override.isNotEmpty) {
      return files.file(override).existsSync() ? override : null;
    }
    final paths = _host.paths.context;
    final name = _host.paths.executableName('xcross-screen');
    final binDir = paths.dirname(_xcrossExecutable);
    for (final candidate in [
      paths.join(binDir, name),
      paths.join(paths.dirname(binDir), 'libexec', name),
    ]) {
      if (files.file(candidate).existsSync()) return candidate;
    }
    return null;
  }

  @override
  Future<ScreenHelperProcess?> start(List<String> args) async {
    final path = locate();
    if (path == null) return null;
    return HostScreenHelperProcess(await _host.processes.start(path, args));
  }
}
