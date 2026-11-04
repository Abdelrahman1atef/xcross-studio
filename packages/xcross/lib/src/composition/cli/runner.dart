import 'dart:io'; // studio: 010
import 'package:apple_developer_kit/shared/errors/errors.dart';
import 'package:args/args.dart'; // studio: 010
import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:cli_kit/shared/logging/logging.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:cli_kit/shared/tui/tui.dart';
import 'package:completion/completion.dart';
import 'package:dart_mobile_device/host/shared/usbmux_listen.dart'; // studio: 017
import 'package:dart_mobile_device/shared/device/models/device.dart'; // studio: 005
import 'package:dart_mobile_device/shared/errors/errors.dart';
import 'package:dart_mobile_device/target/iphone/device/device_prepare.dart';
import 'package:dart_mobile_device/target/iphone/device/pymd/pymd_devices.dart'; // studio: 011
import 'package:dart_mobile_device/target/iphone/diagnostics/pymd_device_diagnostics.dart';
import 'package:darwin_sdk_kit/shared/errors/errors.dart';
import 'package:meta/meta.dart';
import 'package:studio_ext/shared/appstore/command_exit.dart'; // studio: 019
import 'package:studio_ext/shared/icons/icons_command.dart'; // studio: 023
import 'package:studio_ext/shared/inspect/inspect_command.dart'; // studio:
import 'package:studio_ext/shared/plugins/plugin_command.dart'; // studio: 006
import 'package:studio_ext/shared/release/release_check_command.dart'; // studio: 018
import 'package:studio_ext/shared/splash/splash_command.dart'; // studio: 024
import 'package:studio_ext/target/iphone/device/app_command.dart'; // studio: 010
import 'package:studio_ext/target/iphone/device/crashes_command.dart'; // studio: 010
import 'package:studio_ext/target/iphone/device/device_log_backend.dart'; // studio: 010
import 'package:studio_ext/target/iphone/device/devices_command.dart'; // studio: 008
import 'package:studio_ext/target/iphone/device/logs_command.dart'; // studio: 010
import 'package:xcross/src/composition/cli/appstore_commands.dart'; // studio: 021
import 'package:xcross/src/composition/cli/cache_command.dart';
import 'package:xcross/src/composition/cli/compose_command.dart';
import 'package:xcross/src/composition/cli/doctor_sections.dart';
import 'package:xcross/src/composition/cli/flutter_command.dart';
import 'package:xcross/src/composition/cli/install_command.dart'; // studio: 005
import 'package:xcross/src/composition/cli/publish_commands.dart'; // studio: 019
import 'package:xcross/src/composition/cli/sign_command.dart'; // studio: 011
import 'package:xcross/src/composition/cli/testflight_commands.dart'; // studio: 020
import 'package:xcross/src/composition/ios_target.dart';
import 'package:xcross/src/composition/xcross_application.dart';
import 'package:xcross/src/shared/cli/basic/auth_command.dart';
import 'package:xcross/src/shared/cli/basic/completion_command.dart';
import 'package:xcross/src/shared/cli/basic/config_command.dart';
import 'package:xcross/src/shared/cli/basic/doctor_command.dart';
import 'package:xcross/src/shared/cli/basic/doctor_environment_checks.dart';
import 'package:xcross/src/shared/cli/basic/sdk_command.dart';
import 'package:xcross/src/shared/cli/basic/setup_command.dart';
import 'package:xcross/src/shared/cli/basic/update_command.dart';
import 'package:xcross/src/shared/cli/ide/ide_command.dart';
import 'package:xcross/src/shared/cli/ide/xcross_executable.dart';
import 'package:xcross/src/shared/cli/internal/xcross_runner.dart';
import 'package:xcross/src/shared/config/config.dart';
import 'package:xcross/src/shared/config/config_store.dart';
import 'package:xcross/src/shared/errors/errors.dart';
import 'package:xcross/src/shared/flutter/build/ios_bundle_id.dart'; // studio: 016
import 'package:xcross/src/shared/flutter/errors.dart';
import 'package:xcross/src/shared/flutter/project/pbx_project_reader.dart'; // studio: 016
import 'package:xcross/src/shared/models/pack_result.dart'; // studio: 005
import 'package:xcross/src/shared/runtime/xcross_runtime.dart'; // studio: 016
import 'package:xcross/src/shared/update/install_layout.dart';
import 'package:xcross/src/shared/update/self_update.dart';
import 'package:xcross/src/shared/update/update_check.dart';
import 'package:xcross/src/target/iphone/cli/basic/project_command.dart'; // studio: 016
import 'package:xcross/src/target/iphone/cli/basic/tunnel_command.dart';
import 'package:xcross/src/target/iphone/device/core_device_launch_profile.dart'; // studio: 005
import 'package:xcross/src/target/iphone/device/device_backend.dart'; // studio: 011
import 'package:xcross/src/target/iphone/device/device_run_operation.dart'; // studio: 005

/// Namespace for building and running the xcross CLI.
@internal
abstract final class XcrossCli {
  static CommandRunner<void> buildRunner<T extends PlatformHostInterface>(
    XcrossApplication<T> application, {
    required TuiTerminal configTerminal,
    Iterable<String> excludedCommands = const [],
  }) {
    final runtime = application.runtime;
    final pymd = application.pymd;
    final excluded = excludedCommands
        .map((command) => command.trim().toLowerCase())
        .toSet();
    final runner = XcrossRunner(
      runtime.log,
      'xcross',
      'Build and run Flutter and Compose Multiplatform iOS apps without Xcode.',
    );
    final physical = composePhysicalFeatures(runtime);
    final environmentChecks = DoctorEnvironmentChecks(
      createAppleHttpClient: runtime.createAppleHttpClient,
      hostPlatform: runtime.host,
      runner: runtime.runner,
      repository: runtime.sdkRepository,
      toolchain: runtime.darwinToolchain,
      deviceDiagnostics: PymdDeviceDiagnostics(pymd),
      buildPlatform: physical.target.buildPlatform,
      appleHostServices: runtime.appleHostServices,
      sdkMismatch: runtime.sdkInstall.hostToolchainMismatch,
      sdkToolchainIdentity: runtime.sdkInstall.hostToolchainIdentity,
      minimumSwift: runtime.operations.minimumSwift,
      swiftInstallGuidance: runtime.operations.swiftInstallGuidance,
      swiftEnvironmentChecks: runtime.operations.swiftEnvironment.doctorChecks,
      // studio: 002
      deviceServiceProblem: () =>
          pymd.hostPolicy.deviceServiceProblem(pymd.resolvedUsbmuxAddress()),
      configuredPath: runtime.config.configuredPath,
    );
    final doctor = DoctorSections(runtime, environment: environmentChecks);
    final ideLauncher = XcrossIdeLauncher(
      host: runtime.host,
      log: runtime.log,
      executable: runtime.executable,
      configPath: runtime.config.configPath,
      flutterRoot:
          runtime.config.roots?.flutterSdk ??
          runtime.config.config?.environment['FLUTTER_ROOT'] as String?,
      declarative: runtime.config.isConfigured,
    );
    final commands = <Command<void>>[
      FlutterCommand(
        runtime,
        pymd,
        application.sockets,
        doctorCommand: DoctorCommand(
          framework: 'Flutter',
          sections: doctor.flutter,
          log: runtime.log,
        ),
      ),
      ComposeCommand(
        runtime,
        pymd,
        application.sockets,
        doctorCommand: DoctorCommand(
          framework: 'Compose',
          sections: doctor.compose,
          log: runtime.log,
        ),
      ),
      TunnelCommand(DevicePrepare(pymd)),
      ConfigCommand(
        terminal: configTerminal,
        writeLine: runtime.log.output.stdout,
        store: XcrossConfigStore(runtime.host, policy: runtime.configPolicy),
      ),
      SetupCommand(
        host: runtime.host,
        runner: runtime.runner,
        requirements: runtime.operations.setupRequirements,
        scriptPolicy: runtime.operations.setupScript,
        createHttpClient: runtime.createHttpClient,
        swiftInstallGuidance: runtime.operations.swiftInstallGuidance,
        commandPrompt: runtime.commandPrompt,
        minimumSwift: runtime.operations.minimumSwift,
        setupSource: runtime.config.config?.setup,
      ),
      AuthCommand(
        commandPrompt: runtime.commandPrompt,
        createAdiHttpClient: runtime.createHttpClient,
        createHttpClient: runtime.createAppleHttpClient,
        log: runtime.log,
        hostServices: runtime.appleHostServices,
        createNativeLibraryLoader: runtime.createNativeLibraryLoader,
      ),
      SdkCommand(runtime.sdkInstall),
      composeCacheCommand(runtime),
      IdeCommand(ideLauncher),
      UpdateCommand(runtime),
      CompletionCommand(write: runtime.log.output.write),
      // studio: XCross Studio feature 001 (specs/001-inspect).
      InspectCommand(
        fileSystem: runtime.host.fileSystem,
        write: runtime.log.output.write,
      ),
      // studio: 018 — `xcross release check`.
      ReleaseCommand(
        fileSystem: runtime.host.fileSystem,
        paths: runtime.host.paths.context,
        currentDirectory: () => runtime.host.paths.context.current,
        write: runtime.log.output.write,
        // studio: 022 — `release gate` runs the Flutter iOS builds use.
        flutter: (projectRoot) async => runtime.host.paths.context.join(
          await physical.flutterRuntime.resolveFlutterRoot(
            projectRoot: projectRoot,
          ),
          'bin',
          runtime.runner.hostExecutableName('flutter', extension: '.bat'),
        ),
        runTool: (executable, arguments, {required workingDirectory}) async {
          final result = await runtime.runner.run(
            executable,
            arguments,
            workingDirectory: workingDirectory,
          );
          return (
            exitCode: result.exitCode,
            output: '${result.stdout}\n${result.stderr}',
          );
        },
      ),
      // studio: 023 — `xcross icons check|generate`.
      IconsCommand(
        fileSystem: runtime.host.fileSystem,
        currentDirectory: () => runtime.host.paths.context.current,
        write: runtime.log.output.write,
      ),
      // studio: 024 — `xcross splash check|generate`.
      SplashCommand(
        fileSystem: runtime.host.fileSystem,
        currentDirectory: () => runtime.host.paths.context.current,
        write: runtime.log.output.write,
      ),
      // studio: 019–021 — App Store Connect: upload, TestFlight, App Store.
      ...publishCommands(runtime),
      ...testflightCommands(runtime),
      ...appStoreCommands(runtime),
      // studio: 016 — `xcross project bundle-id`.
      ProjectCommand(
        fileSystem: runtime.host.fileSystem,
        paths: runtime.host.paths.context,
        projectRoot: () => runtime.host.paths.context.current,
        environment: runtime.runner.effectiveEnvironment,
        write: runtime.log.output.write,
      ),
      // studio: 006 — `xcross plugin list|shim`.
      PluginCommand(
        fileSystem: runtime.host.fileSystem,
        paths: runtime.host.paths.context,
        write: runtime.log.output.write,
        home:
            runtime.runner.effectiveEnvironment['HOME'] ??
            runtime.runner.effectiveEnvironment['USERPROFILE'],
      ),
      // studio: XCross Studio feature 005 (specs/005-ios16-install-launch).
      InstallCommand(
        fileSystem: runtime.host.fileSystem,
        paths: runtime.host.paths.context,
        temporaryRoot: runtime.host.paths.temporaryRoot,
        installOnDevice:
            ({
              required appPath,
              required bundleId,
              required udid,
              required ddiDirectory,
              required launch,
              required resign,
            }) async {
              final operation = await DeviceRunOperation.resolve(
                pymd,
                sockets: application.sockets,
                httpClients: runtime.signingHttpClients,
                connector: runtime.vmConnector,
                vmOutput: runtime.vmOutput,
                hostServices: runtime.appleHostServices,
                createNativeLibraryLoader: runtime.createNativeLibraryLoader,
                prompt: runtime.commandPrompt,
              );
              final prechecked = await operation.precheck(
                selector: udid,
                mode: DeviceSearchMode.usb,
              );
              // studio: 016 — run inside the project, the App ID choice saved
              // with it applies to its own IPA (XCross Studio's Install).
              final projectRoot = _projectRootFor(runtime, bundleId);
              final pack = PackResult(
                outputPath: appPath,
                bundleId: bundleId,
                projectRoot: projectRoot,
              );
              // studio: 011 — install as signed (an IPA from `xcross sign`).
              if (!resign) {
                final device = prechecked.device;
                await PymdDevices(pymd).install(
                  appPath,
                  udid: device.udid,
                  overTunnel: device.source == DeviceSource.tunneld,
                );
                runtime.log.logInfo(
                  'Installed',
                  '$bundleId (open it from its icon)',
                );
                return;
              }
              if (!launch) {
                await operation.backend.install(
                  appPath,
                  device: prechecked.device,
                  bundleId: bundleId,
                  projectRoot: projectRoot,
                );
                return;
              }
              await operation.run(
                pack: pack,
                selector: udid,
                mode: DeviceSearchMode.usb,
                launchProfile: const CoreDeviceLaunchProfile.native(),
                prechecked: prechecked,
                ddiDirectory: ddiDirectory,
              );
            },
      ),
      // studio: 011 — `xcross sign` writes a signed IPA, installs nothing.
      SignCommand(
        fileSystem: runtime.host.fileSystem,
        paths: runtime.host.paths.context,
        temporaryRoot: runtime.host.paths.temporaryRoot,
        write: runtime.log.output.write,
        connectedDevices: () async {
          try {
            return [
              for (final device in await PymdDevices(
                pymd,
              ).devices(mode: DeviceSearchMode.usb))
                device.udid,
            ];
          } on Object {
            return const [];
          }
        },
        signApp:
            ({required appPath, required bundleId, required deviceUdids}) =>
                NativeBackend(
                  pymd,
                  hostServices: runtime.appleHostServices,
                  createNativeLibraryLoader: runtime.createNativeLibraryLoader,
                  httpClients: runtime.signingHttpClients,
                  prompt: runtime.commandPrompt,
                ).sign(appPath, bundleId: bundleId, deviceUdids: deviceUdids),
      ),
      // studio: XCross Studio feature 010 (specs/010-device-logs).
      LogsCommand(
        backend: PymdDeviceLogBackend(pymd),
        fileSystem: runtime.host.fileSystem,
        writeBytes: stdout.add,
        interrupts: () => ProcessSignal.sigint.watch().map((_) {}),
      ),
      AppCommand(backend: PymdDeviceLogBackend(pymd), writeBytes: stdout.add),
      // studio: 008 — device picker for the GUI.
      DevicesCommand(
        backend: PymdDeviceLogBackend(pymd),
        writeBytes: stdout.add,
        // studio: 017 — `devices --watch` follows usbmuxd's Listen events.
        listen: () =>
            UsbmuxListener(address: pymd.usbmuxListenAddress()).listen(),
      ),
      CrashesCommand(
        backend: PymdDeviceLogBackend(pymd),
        fileSystem: runtime.host.fileSystem,
        paths: runtime.host.paths.context,
        cacheRoot: runtime.host.paths.temporaryRoot,
        writeBytes: stdout.add,
      ),
    ];
    for (final command in commands) {
      if (!excluded.contains(command.name.toLowerCase())) {
        runner.addCommand(command);
      }
    }
    return runner;
  }

  /// Entry point used by `bin/xcross.dart`.
  static Future<int> run<T extends PlatformHostInterface>(
    List<String> args,
    XcrossApplication<T> application, {
    required TuiTerminal configTerminal,
  }) async {
    final runtime = application.runtime;
    final excludedCommands =
        runtime.config.config?.excludedCommands ?? const <String>{};
    final runner = buildRunner(
      application,
      configTerminal: configTerminal,
      excludedCommands: excludedCommands,
    );
    _completeArgs(args, runner);
    final ownsStdout = ownsMachineStdout(args, runner);
    if (!ownsStdout) _printCredits(runtime.log);

    final updateCheck = UpdateCheck(
      runtime.host,
      log: runtime.log,
      releaseLookup: runtime.releaseLookup,
      outputHasTerminal: runtime.outputHasTerminal,
    );
    final checkUpdates = updateCheck.isEnabled(ownsStdout: ownsStdout);
    if (checkUpdates) updateCheck.printHintFromCache();

    var status = 1; // studio: 012 — reported as the `done` event
    try {
      await runner.run(args);
      status = 0;
      return 0;
    } on UsageException catch (e) {
      reportFailure(runtime.log, '$e');
      status = 64;
      return 64;
    } on CommandExit catch (e) {
      // studio: 019 — a failure that sets its own exit code.
      reportFailure(runtime.log, e.message);
      status = e.exitCode;
      return e.exitCode;
    } on Object catch (error, stackTrace) {
      reportFailure(runtime.log, formatFailure(error, stackTrace));
      return 1;
    } finally {
      // After the command, never before: neither of these is worth a millisecond
      // of startup latency, and the sweep is deliberately not tied to the
      // update-check opt-out, which says nothing about disk hygiene.
      try {
        if (!SelfUpdate.isVerificationProcess(
          runtime.runner.effectiveEnvironment,
        )) {
          SelfUpdate(
            host: runtime.host,
            runner: runtime.runner,
            policy: runtime.operations.update,
            downloader: runtime.downloader,
          ).sweepStaleBackups(
            InstallLayout.resolve(runtime.executable, host: runtime.host),
          );
        }
      } on Object {
        // Best effort cleanup. Update completion should not be blocked by stale backup cleanup.
      }
      if (checkUpdates) await updateCheck.refreshIfStale();
      runtime.log.events?.event('done', {'exitCode': status}); // studio: 012
    }
  }

  // studio: 012 — in NDJSON mode a failure is an `error` event (code, message,
  // hint) instead of stderr text.
  /// Prints [text] to stderr, or reports it as an `error` event.
  static void reportFailure(Log log, String text) {
    final events = log.events;
    if (events == null) {
      log.output.stderr(text);
    } else {
      events.message(LogEventLevel.error, text);
    }
  }

  /// Intercepts the shell-driven `xcross completion -- ...` hook and prints
  /// suggestions; calls `exit()` internally and never returns in that case.
  static void _completeArgs(List<String> args, CommandRunner<void> runner) {
    try {
      tryArgsCompletion(args, runner.argParser);
    } on FormatException {
      // Swallow so `runner.run` reports the bad flag as a UsageException
      // instead of a raw stack trace.
    }
  }

  // studio: 016
  /// The current folder when it is the project [bundleId] was built from
  /// (same bundle ID), so its saved App ID choice applies; otherwise `null`.
  static String? _projectRootFor<T extends PlatformHostInterface>(
    XcrossRuntime<T> runtime,
    String bundleId,
  ) {
    final paths = runtime.host.paths.context;
    final root = paths.current;
    try {
      final projectId = IosBundleId(
        runtime.host.fileSystem,
        paths,
        PbxProjectReader(runtime.host.fileSystem, paths),
      ).resolve(root);
      return projectId == bundleId ? root : null;
    } on Object {
      return null;
    }
  }

  /// Both completion and DAP own stdout as a machine protocol; a credits line
  /// corrupts either stream.
  static bool ownsMachineStdout(List<String> args, CommandRunner<void> runner) {
    try {
      final command = runner.argParser.parse(args).command;
      return command?.name == 'completion' ||
          command?.name == 'flutter' && command?.command?.name == 'dap' ||
          // studio: `inspect --json` prints one machine-readable document.
          command?.name == 'inspect' && command?.flag('json') == true ||
          // studio: 010 — NDJSON from the device commands.
          _deviceJson(command) ||
          // studio: 014 — `flutter sdk list --json` prints one document.
          _flutterSdkJson(command) ||
          // studio: 019–021 — App Store Connect commands with --json.
          _ascJson(command) ||
          // studio: 016 — `project bundle-id --json` prints one object.
          command?.name == 'project' &&
              command?.command?.name == 'bundle-id' &&
              command?.command?.flag('json') == true ||
          // studio: 018 — `release check --json` prints one object.
          command?.name == 'release' &&
              command?.command?.name == 'check' &&
              command?.command?.flag('json') == true;
    } on FormatException {
      return false;
    }
  }

  // studio: 019–021
  static bool _ascJson(ArgResults? command) {
    if (!const {'publish', 'testflight', 'appstore'}.contains(command?.name)) {
      return false;
    }
    var leaf = command;
    while (leaf?.command != null) {
      leaf = leaf!.command;
    }
    return leaf != null && leaf.options.contains('json') && leaf.flag('json');
  }

  // studio: 014
  static bool _flutterSdkJson(ArgResults? command) {
    if (command?.name != 'flutter') return false;
    final sdk = command?.command;
    final list = sdk?.command;
    return sdk?.name == 'sdk' &&
        list?.name == 'list' &&
        list!.options.contains('json') &&
        list.flag('json');
  }

  // studio: 010 — `logs --json`, `app info --json`, `crashes list --json`;
  // 008 — `devices --json`, `app list --json`.
  static bool _deviceJson(ArgResults? command) {
    final leaf = command?.command ?? command;
    if (leaf == null) return false;
    final known =
        {'logs', 'info', 'list', 'devices'}.contains(leaf.name) &&
        {'logs', 'app', 'crashes', 'devices'}.contains(command?.name);
    return known && leaf.options.contains('json') && leaf.flag('json');
  }

  /// One-line credits banner printed before every command dispatch.
  static void _printCredits(Log log) {
    if (!log.ansi.useAnsi) return;
    final a = log.ansi;
    // log.dim (SGR 2) instead of Ansi.subtle: cli_util's gray (`1;30`) maps to
    // the background color on many dark palettes and rendered invisible.
    log.logStatus(
      '${a.bold}${a.magenta}xcross${a.none}'
      ' ${log.dim('· github.com/arxdeus/xcross')}'
      '\n',
    );
  }

  /// Formats errors consistently for the CLI entrypoint and command runner.
  /// User-facing errors omit a Dart stack trace; unexpected failures retain it.
  static String formatFailure(Object error, StackTrace stackTrace) {
    return switch (error) {
      CliError(:final message) ||
      AppleError(:final message) ||
      DarwinSdkError(:final message) ||
      TunnelError(:final message) ||
      FlutterBuildError(:final message) ||
      XcrossError(:final message) => 'error: $message',
      XcrossConfigException(:final message, :final path) =>
        'error: ${path == null ? message : '$path: $message'}',
      _ => 'error: $error\n$stackTrace',
    };
  }
}
