// studio: 002 — PATH guard against linkers that cannot link iOS (#148).
import 'dart:io';

import 'package:cli_kit/host/linux/linux_host.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:cli_kit/shared/process/process.dart';
import 'package:cli_kit/shared/process/process_models.dart';
import 'package:cli_kit/shared/process/tool_lookup.dart';
import 'package:darwin_sdk_kit/host/linux/linux_darwin_toolchain_locations.dart';
import 'package:darwin_sdk_kit/shared/sdk/darwin_sdk.dart';
import 'package:darwin_sdk_kit/shared/sdk/darwin_sdk_repository.dart';
import 'package:darwin_sdk_kit/shared/toolchain/darwin_toolchain_resolver.dart';
import 'package:darwin_sdk_kit/target/iphone/iphone_build_platform.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart';
import 'package:xcross/src/shared/toolchain/path_linker_guard.dart';
import 'package:xcross/src/shared/xcrun/cross_xcrun.dart' as xcrun;

import '../cli/xcrun_test.dart' as xcrun_test;
import '../setup/host_ops_residual_fixtures.dart';

void main() {
  late Directory temp;
  late String bad;
  late String good;
  late String plain;

  late ResidualFileSystem files;

  // Logical POSIX paths under /fixture map onto a real temp directory, so the
  // simulated Linux host behaves the same on every OS.
  setUp(() {
    temp = Directory.systemTemp.createTempSync('xcross-path-guard-');
    files = ResidualFileSystem('/fixture', temp);
    bad = '/fixture/swift-toolchain/bin';
    good = '/fixture/shims';
    plain = '/fixture/plain';
    for (final file in [
      '$bad/ld64.lld',
      '$bad/clang',
      '$good/clang',
      '$plain/tool',
    ]) {
      files.file(file)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('');
    }
  });
  tearDown(() => temp.deleteSync(recursive: true));

  /// A host whose `ld64.lld` in [bad] rejects iOS links.
  LinuxHostInterface host() => ResidualHost(
    base: LinuxHost(),
    fileSystem: files,
    paths: LinuxHost().paths,
    processes: ResidualProcesses((tool, arguments, _) async {
      if (tool.contains('swift-toolchain') &&
          arguments.contains('-platform_version')) {
        return ResidualChild(
          code: 1,
          errors: 'ld64.lld: error: unknown platform: ios',
        );
      }
      return ResidualChild(
        output: arguments.contains('--version') ? 'LLD 19.1.0' : '',
      );
    }),
  );

  DarwinToolchainResolver<LinuxHostInterface> toolchain(
    ProcessRunner<LinuxHostInterface> runner,
  ) => DarwinToolchainResolver(
    runner,
    LinuxDarwinToolchainLocations(runner.host),
  );

  test('AC-002-9 an unusable ld64.lld in a directory is reported', () async {
    final processHost = host();
    final runner = ProcessRunner(
      processHost,
      log: residualRunner(processHost).log,
      stdinStream: const Stream.empty(),
      stdoutSink: stdout,
      stderrSink: stderr,
    );
    final guard = PathLinkerGuard(toolchain(runner));
    expect(await guard.directoryProblem(bad), contains('unknown platform'));
    expect(await guard.directoryProblem(good), isNull, reason: 'no linker');
    final problems = await guard.configuredProblems([good, bad, plain]);
    expect(problems.single.$1, bad);
  });

  test(
    'AC-002-10 xcrun skips clang from a directory with an unusable linker',
    () async {
      final processHost = host();
      final runner = ProcessRunner(
        processHost,
        log: residualRunner(processHost).log,
        stdinStream: const Stream.empty(),
        stdoutSink: stdout,
        stderrSink: stderr,
        toolLookup: ListLookup(processHost, {
          'clang': ['$bad/clang', '$good/clang'],
        }),
      );
      final output = xcrun_test.FixtureProbeOutput();
      addTearDown(output.close);
      final code = await xcrun.XcrunSdkCommand(
        runner: runner,
        output: output,
        errors: stderr,
        repository: DarwinSdkRepository(
          processHost,
          log: runner.log,
          installBundle: '/fixture/missing-sdk',
        ),
        toolchain: toolchain(runner),
        normalizeExecutable: (path) => path,
        target: const IPhoneBuildPlatform(),
        executable: '/fixture/xcrun',
      ).run(const ['--find', 'clang'], sdk: const DarwinSdk('/unused'));
      expect(code, 0);
      expect(output.buffer.toString().trim(), '$good/clang');
    },
  );
}

/// Tool lookup returning a fixed list of PATH candidates per tool name.
@internal
final class ListLookup
    implements ProcessToolLookupInterface<LinuxHostInterface> {
  ListLookup(this.host, this.candidates) : base = ProcessToolLookup(host);

  final ProcessToolLookup<LinuxHostInterface> base;
  final Map<String, List<String>> candidates;
  @override
  final LinuxHostInterface host;
  @override
  ProcessConfiguration? get configuration => null;
  @override
  Map<String, String> get effectiveEnvironment => base.effectiveEnvironment;
  @override
  String resolveExecutable(String executable) =>
      base.resolveExecutable(executable);
  @override
  String hostExecutableName(String name, {String extension = '.exe'}) =>
      base.hostExecutableName(name, extension: extension);
  @override
  String? environmentValue(Map<String, String> environment, String name) =>
      base.environmentValue(environment, name);
  @override
  bool isSwiftlyProxy(String path) => base.isSwiftlyProxy(path);
  @override
  Future<String?> which(
    String name, {
    Map<String, String>? environment,
    bool Function(String)? accept,
    Iterable<String> extraDirectories = const [],
    bool useConfiguration = true,
  }) async => candidates[name]?.firstOrNull;
  @override
  Future<List<String>> whichAll(
    String name, {
    Map<String, String>? environment,
    bool Function(String)? accept,
    Iterable<String> extraDirectories = const [],
    bool useConfiguration = true,
  }) async => candidates[name] ?? const [];
  @override
  Future<String> locateTool(
    String name, {
    Iterable<String> extraDirectories = const [],
  }) async => candidates[name]?.firstOrNull ?? (throw StateError(name));
}
