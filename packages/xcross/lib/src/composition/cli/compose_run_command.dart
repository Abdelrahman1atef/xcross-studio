@internal
library;

import 'package:build_cli_annotations/build_cli_annotations.dart';
import 'package:cli_kit/shared/logging/logging.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:dart_mobile_device/shared/device/models/device.dart';
import 'package:dart_mobile_device/shared/network/device_sockets.dart';
import 'package:dart_mobile_device/target/iphone/device/pymd/pymd.dart';
import 'package:meta/meta.dart';
import 'package:xcross/src/composition/cli/compose_build_command.dart';
import 'package:xcross/src/composition/ios_target.dart';
import 'package:xcross/src/shared/cli/device_selection.dart';
import 'package:xcross/src/shared/cli/internal/parsed_command.dart';
import 'package:xcross/src/shared/compose/models/compose_build_options.dart';
import 'package:xcross/src/shared/compose/watch/compose_watch_session.dart';
import 'package:xcross/src/shared/compose/watch/kotlin_source_watcher.dart';
import 'package:xcross/src/shared/models/pack_result.dart';
import 'package:xcross/src/shared/runtime/xcross_runtime.dart';
import 'package:xcross/src/target/iphone/device/core_device_launch_profile.dart';
import 'package:xcross/src/target/iphone/device/device_precheck.dart'; // studio: 002
import 'package:xcross/src/target/iphone/device/device_run_operation.dart';
import 'package:xcross/src/target/shared/runtime/build_features.dart';

part 'compose_run_command.g.dart';

@internal
typedef ComposeRunDevice =
    Future<void> Function({
      required PackResult pack,
      required String? selector,
      required DeviceSearchMode mode,
      required CoreDeviceLaunchProfile launchProfile,
      Future<bool> Function()? onRestartRequested,
    });

// studio: 002 — device precheck before the build (#147).
@internal
typedef ComposeRunPrecheck =
    Future<PrecheckedDevice?> Function({
      required DeviceSearchMode mode,
      String? selector,
    });

/// Shares one device operation and the prechecked device between the
/// precheck (before the build) and the device run (after it).
@internal
final class ComposeDeviceSession {
  Future<DeviceRunOperation>? operation;
  PrecheckedDevice? prechecked;
}

@internal
@CliOptions()
final class ComposeRunArgs {
  @CliOption(abbr: 'd', help: 'Target device id or name (flutter-style).')
  late String? deviceId;

  @CliOption(abbr: 'u', help: 'Target device UDID.')
  late String? udid;

  @CliOption(help: 'Search USB devices only.', negatable: false)
  late bool usb;

  @CliOption(help: 'Search Wi-Fi devices only.', negatable: false)
  late bool wifi;

  @CliOption(
    defaultsTo: DeviceConnection.both,
    help: 'Discovery: attached (USB), wireless (Wi-Fi), or both.',
  )
  late DeviceConnection deviceConnection;

  @CliOption(
    help:
        'Override CFBundleIdentifier. An App ID your team already owns is '
        'signed as-is, keeping Sign in with Apple, passkeys and push.',
  )
  late String? bundleId;

  @CliOption(abbr: 'a', help: 'Pass arguments to the app main() (repeatable).')
  late List<String> appArgument;

  @CliOption(
    help:
        'Watch Kotlin sources and rebuild, reinstall, and relaunch on "r". '
        'Kotlin/Native is AOT-compiled, so this is a fast restart, not an '
        'in-place hot reload.',
    negatable: false,
  )
  late bool watch;

  @CliOption(abbr: 'v', help: 'Verbose output.', negatable: false)
  late bool verbose;
}

@internal
final class ComposeRunCommand<T extends PlatformHostInterface>
    extends ParsedCommand<ComposeRunArgs, void> {
  ComposeRunCommand(
    XcrossRuntime<T> runtime,
    Pymd pymd, {
    required DeviceSockets sockets,
  }) : this._withRuntime(
         runtime,
         pymd,
         sockets,
         composePhysicalFeatures(runtime),
         ComposeDeviceSession(), // studio: 002
       );

  ComposeRunCommand._withRuntime(
    XcrossRuntime<T> runtime,
    Pymd pymd,
    DeviceSockets sockets,
    XcrossBuildFeatures<T> features,
    ComposeDeviceSession session,
  ) : this.withSeams(
        log: runtime.log,
        files: runtime.host.fileSystem,
        projectRoot: runtime.host.paths.context.current,
        packOperation:
            ({
              required options,
              required requireRunnableApp,
              required targetPlatform,
            }) => features.composeOperation.pack(
              options: options,
              requireRunnableApp: requireRunnableApp,
            ),
        runDevice:
            ({
              required pack,
              required selector,
              required mode,
              required launchProfile,
              onRestartRequested,
            }) async {
              final operation = await (session.operation ??= _resolveOperation(
                runtime,
                pymd,
                sockets,
              ));
              await operation.run(
                pack: pack,
                selector: selector,
                mode: mode,
                launchProfile: launchProfile,
                onRestartRequested: onRestartRequested,
                prechecked: session.prechecked, // studio: 002
              );
            },
        // studio: 002 — resolve and gate the device before the build.
        precheck: ({required mode, selector}) async {
          final operation = await (session.operation ??= _resolveOperation(
            runtime,
            pymd,
            sockets,
          ));
          return session.prechecked = await operation.precheck(
            selector: selector,
            mode: mode,
          );
        },
      );

  ComposeRunCommand.withSeams({
    required this.log,
    required this.files,
    required this.projectRoot,
    required ComposeCliPackOperation packOperation,
    required ComposeRunDevice runDevice,
    // studio: 002 — without it, a seamed command skips the device precheck.
    ComposeRunPrecheck? precheck,
  }) : _packOperation = packOperation,
       _runDevice = runDevice,
       _precheck = precheck;
  static Future<DeviceRunOperation>
  _resolveOperation<H extends PlatformHostInterface>(
    XcrossRuntime<H> runtime,
    Pymd pymd,
    DeviceSockets sockets,
  ) => DeviceRunOperation.resolve(
    pymd,
    sockets: sockets,
    httpClients: runtime.signingHttpClients,
    connector: runtime.vmConnector,
    vmOutput: runtime.vmOutput,
    hostServices: runtime.appleHostServices,
    createNativeLibraryLoader: runtime.createNativeLibraryLoader,
    prompt: runtime.commandPrompt,
  );

  @override
  ArgParser populateOptions(ArgParser parser) =>
      _$populateComposeRunArgsParser(parser);
  @override
  ComposeRunArgs parseOptions(ArgResults results) =>
      _$parseComposeRunArgsResult(results);

  final HostFileSystemInterface files;
  final String projectRoot;
  final Log log;
  final ComposeCliPackOperation _packOperation;
  final ComposeRunDevice _runDevice;
  final ComposeRunPrecheck? _precheck;

  @override
  String get name => 'run';

  @override
  String get description =>
      'Build, install, and run a Compose Multiplatform iOS app on a device.';

  String? get _deviceSelector => options.udid ?? options.deviceId;

  DeviceSearchMode get _searchMode => deviceSearchMode(
    usb: options.usb,
    wifi: options.wifi,
    deviceConnection: options.deviceConnection,
  );

  @override
  Future<void> run() async {
    if (options.verbose) log.setVerbose();
    // studio: 002 — fail before the build when the device cannot be used.
    await _precheck?.call(selector: _deviceSelector, mode: _searchMode);
    final pack = await _packOperation(
      options: ComposeBuildOptions(bundleId: options.bundleId),
      requireRunnableApp: true,
      targetPlatform: 'iphone',
    );
    log.logInfo(
      'App',
      '${pack.bundleId} ${log.dim('native, attached via CoreDevice')}',
    );
    final profile = CoreDeviceLaunchProfile.native(
      arguments: options.appArgument,
    );
    if (!options.watch) {
      await _runDevice(
        pack: pack,
        selector: _deviceSelector,
        mode: _searchMode,
        launchProfile: profile,
      );
      return;
    }

    log.logInfo(
      'Watching',
      'Kotlin sources '
          '${log.dim('press r to rebuild and restart, q to quit')}',
    );
    final session = ComposeWatchSession(
      log: log,
      watcher: KotlinSourceWatcher(
        pack.projectRoot ?? projectRoot,
        files: files,
      ),
      rebuild: () => _packOperation(
        options: ComposeBuildOptions(bundleId: options.bundleId),
        requireRunnableApp: true,
        targetPlatform: 'iphone',
      ),
      runSession: ({required pack, required onRestartRequested}) => _runDevice(
        pack: pack,
        selector: _deviceSelector,
        mode: _searchMode,
        launchProfile: profile,
        onRestartRequested: onRestartRequested,
      ),
    );
    await session.run(pack);
  }
}
