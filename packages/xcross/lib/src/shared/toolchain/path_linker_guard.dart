// studio: 002 — PATH guard against linkers that cannot link iOS (#148).
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:darwin_sdk_kit/shared/toolchain/darwin_toolchain_resolver.dart';
import 'package:meta/meta.dart';

/// Finds directories whose `ld64.lld` must not be used for iOS: it fails the
/// iOS link probe, or it is an lld older than 19 that miswires Objective-C
/// selector stubs. A Swift toolchain's bundled linker is the typical case.
@internal
final class PathLinkerGuard<T extends PlatformHostInterface> {
  PathLinkerGuard(this.toolchain);

  final DarwinToolchainResolver<T> toolchain;
  final Map<String, String?> _problems = {};

  T get _host => toolchain.host;

  /// Why `<directory>/ld64.lld` cannot be used, or null when the directory
  /// has no `ld64.lld` or a usable one. Cached per directory.
  Future<String?> directoryProblem(String directory) async {
    final key = _host.paths.pathKey(directory);
    if (_problems.containsKey(key)) return _problems[key];
    final linker = _host.paths.context.join(
      directory,
      _host.paths.executableName('ld64.lld'),
    );
    String? problem;
    if (_host.fileSystem.file(linker).existsSync()) {
      problem =
          await toolchain.probeIosSupport(linker) ??
          await toolchain.selectorStubDefect(linker);
    }
    return _problems[key] = problem;
  }

  /// The configured PATH [entries] with an unusable `ld64.lld`, with reasons.
  Future<List<(String entry, String problem)>> configuredProblems(
    Iterable<String> entries,
  ) async => [
    for (final entry in entries)
      if (await directoryProblem(entry) case final problem?) (entry, problem),
  ];
}
