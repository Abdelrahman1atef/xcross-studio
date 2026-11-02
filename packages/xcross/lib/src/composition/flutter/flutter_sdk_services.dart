// studio: 014 — wires `xcross flutter sdk` and the compiler catalog to the
// real host: config store, git, the Flutter runtime and the network.
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:cli_kit/shared/process/process.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:xcross/src/composition/flutter/ios_gen_snapshot.dart';
import 'package:xcross/src/composition/ios_target.dart';
import 'package:xcross/src/shared/cli/flutter/subcommands/flutter_sdk_command.dart';
import 'package:xcross/src/shared/config/config_store.dart';
import 'package:xcross/src/shared/flutter/gen_snapshot/flutter_sdk_release.dart';
import 'package:xcross/src/shared/flutter/gen_snapshot/ios_gen_snapshot_mode.dart';
import 'package:xcross/src/shared/flutter/models/flutter/flutter_build_mode.dart';
import 'package:xcross/src/shared/flutter/sdk/ios_compiler_catalog.dart';
import 'package:xcross/src/shared/flutter/sdk/managed_flutter_sdks.dart';
import 'package:xcross/src/shared/runtime/xcross_runtime.dart';

/// The published-compiler catalog for [platform] (`windows-x64`, …).
@internal
IosCompilerCatalog composeIosCompilerCatalog<T extends PlatformHostInterface>({
  required ProcessRunner<T> runner,
  required http.Client Function() createHttpClient,
  required String platform,
}) {
  final host = runner.host;
  return IosCompilerCatalog(
    fileSystem: host.fileSystem,
    paths: host.paths.context,
    cacheRoot: genSnapshotCacheRoot(runner),
    platform: platform,
    createHttpClient: createHttpClient,
  );
}

/// The newest Flutter with a published compiler for [platform], as the
/// suggestion in the `build.gen_snapshot_unavailable` error.
@internal
Future<String?> Function(FlutterSdkRelease release, String platform)
composeFlutterSdkSuggestion<T extends PlatformHostInterface>({
  required ProcessRunner<T> runner,
  required http.Client Function() createHttpClient,
}) => (release, platform) async {
  final catalog = await composeIosCompilerCatalog(
    runner: runner,
    createHttpClient: createHttpClient,
    platform: platform,
  ).load();
  return suggestFlutterSdk(release.version, catalog.versions)?.version;
};

/// Where xcross keeps the Flutter SDKs it installs.
@internal
String managedFlutterSdksRoot(PlatformHostInterface host) =>
    host.paths.context.join(host.paths.configRoot, 'xcross', 'flutter-sdks');

/// The real [FlutterSdkServices] for [runtime].
@internal
FlutterSdkServices composeFlutterSdkServices<T extends PlatformHostInterface>(
  XcrossRuntime<T> runtime,
) {
  final host = runtime.host;
  final runner = runtime.runner;
  final paths = host.paths.context;
  final store = XcrossConfigStore(host, policy: runtime.configPolicy);
  String platform;
  try {
    platform = composeIosGenSnapshotHost(host).prebuiltPlatform;
  } on Object {
    platform = '${host.name}-${host.architecture}';
  }
  final catalog = composeIosCompilerCatalog(
    runner: runner,
    createHttpClient: runtime.createHttpClient,
    platform: platform,
  );
  final features = composePhysicalFeatures(runtime);
  return FlutterSdkServices(
    log: runtime.log,
    write: runtime.log.output.write,
    platform: platform,
    sdks: ManagedFlutterSdks(
      fileSystem: host.fileSystem,
      paths: paths,
      root: managedFlutterSdksRoot(host),
      flutterExecutableName: runner.hostExecutableName(
        'flutter',
        extension: '.bat',
      ),
      log: runtime.log,
      runTool: (executable, arguments, {required label, workingDirectory}) =>
          runner.runChecked(
            executable,
            arguments,
            label: label,
            workingDirectory: workingDirectory,
            inheritStdio: runtime.log.isVerbose,
          ),
    ),
    catalog: catalog.load,
    activeFlutter: () async {
      final String root;
      try {
        root = await features.flutterRuntime.resolveFlutterRoot(
          projectRoot: paths.current,
        );
      } on Object catch (error) {
        return ActiveFlutter(
          root: null,
          version: null,
          compiler: CompilerStatus.unknown,
          detail: '$error',
        );
      }
      String? version;
      try {
        version = FlutterSdkReleaseReader(host).read(root).version;
      } on Object {
        version = null;
      }
      try {
        final found =
            await composeIosGenSnapshotResolver(
              runner: runner,
              downloader: runtime.downloader,
              createHttpClient: runtime.createHttpClient,
              config: runtime.config,
            ).availability(
              flutterRoot: root,
              engineDirectory: features.flutterRuntime
                  .engineCache(root, mode: FlutterBuildMode.release)
                  .engineDirectory,
              mode: IosGenSnapshotMode.release,
            );
        return ActiveFlutter(
          root: root,
          version: version ?? found.release?.version,
          compiler: found.available
              ? CompilerStatus.available
              : (found.unknown
                    ? CompilerStatus.unknown
                    : CompilerStatus.missing),
          detail: found.detail,
        );
      } on Object catch (error) {
        return ActiveFlutter(
          root: root,
          version: version,
          compiler: CompilerStatus.unknown,
          detail: '$error',
        );
      }
    },
    loadConfig: () async =>
        (config: await store.load(), path: store.selectedFile()?.path),
    saveConfig: (config) async => (await store.save(config)).path,
    deleteConfig: (path) => host.fileSystem.file(path).delete(),
    locateGit: () => runner.which('git'),
    confirm: runtime.commandPrompt.isInteractive
        ? (question) async {
            final answer = runtime.commandPrompt.readLine('$question [y/N] ');
            return answer != null &&
                const {'y', 'yes'}.contains(answer.trim().toLowerCase());
          }
        : null,
    xcrunForConfig: () async {
      // Once a config file exists xcross no longer searches PATH for its
      // xcrun shim; record it unless it sits beside the xcross executable.
      final beside = paths.join(
        paths.dirname(runtime.executable),
        host.paths.executableName('xcrun'),
      );
      if (host.fileSystem.file(beside).existsSync()) return null;
      final located = await runner.which('xcrun');
      return located;
    },
  );
}
