// studio: 048 — the engine's downloader, signer and installer for
// `xcross screen touch-setup`.
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:dart_mobile_device/target/iphone/device/pymd/pymd.dart';
import 'package:dart_mobile_device/target/iphone/device/pymd/pymd_devices.dart';
import 'package:darwin_sdk_kit/target/iphone/iphone_build_platform.dart';
import 'package:studio_ext/target/iphone/device/touch_helper_setup.dart';
import 'package:xcross/src/shared/runtime/xcross_runtime.dart';
import 'package:xcross/src/target/iphone/device/device_backend.dart';

/// [TouchHelperServices] from the engine runtime.
final class EngineTouchHelperServices implements TouchHelperServices {
  EngineTouchHelperServices(this._runtime, this._pymd);

  final XcrossRuntime<PlatformHostInterface> _runtime;
  final Pymd _pymd;

  @override
  Future<void> download(String url, String path) =>
      _runtime.downloader.downloadToFile(
        url,
        _runtime.host.fileSystem.file(path),
        label: 'Touch helper',
      );

  @override
  Future<String> sign(
    String appPath, {
    required String bundleId,
    required String udid,
  }) => NativeBackend(
    _pymd,
    hostServices: _runtime.appleHostServices,
    createNativeLibraryLoader: _runtime.createNativeLibraryLoader,
    httpClients: _runtime.signingHttpClients,
    prompt: _runtime.commandPrompt,
  ).sign(appPath, bundleId: bundleId, deviceUdids: [udid]);

  @override
  Future<void> install(String appPath, {required String udid}) =>
      PymdDevices(_pymd).install(appPath, udid: udid);

  /// Oldest iOS the touch runner is built for.
  static const minimumIos = '15.0';

  /// The SDK version told to the linker (as for plugin code on Windows).
  static const linkerSdkVersion = '26.5';

  @override
  Future<void> buildRunner(String sourcePath, String binaryPath) async {
    final repository = _runtime.sdkRepository;
    final sdk = repository.current();
    if (sdk == null) {
      throw CliError(
        '[touch_setup.build] No iOS SDK on this PC. Install it from XCross '
        'Studio Setup (the same one used to build iOS apps).',
      );
    }
    const platform = IPhoneBuildPlatform();
    final sysroot = repository.iosSdk(sdk, target: platform);
    final paths = _runtime.host.paths.context;
    // <platform>/Developer/SDKs/iPhoneOS.sdk -> <platform>/Developer/Library/Frameworks
    final frameworks = paths.join(
      paths.dirname(paths.dirname(sysroot)),
      'Library',
      'Frameworks',
    );
    final tools = _runtime.darwinToolchain;
    final clang = await tools.resolveDarwinClang(sysroot);
    final linker = await tools.resolveLd64Lld();
    final result = await _runtime.runner.run(clang, [
      '--target=${platform.buildTriple(minimumIos)}',
      '-isysroot',
      sysroot,
      platform.minimumVersionFlag(minimumIos),
      '-F',
      frameworks,
      '-fobjc-arc',
      '-O2',
      '-bundle',
      '-fuse-ld=lld',
      '--ld-path=$linker',
      '-Wl,-arch,arm64',
      '-Wl,-platform_version,${platform.linkerPlatform},$minimumIos,$linkerSdkVersion',
      '-o',
      binaryPath,
      sourcePath,
      '-framework',
      'XCTest',
      '-framework',
      'UIKit',
      '-framework',
      'Foundation',
    ], timeout: const Duration(minutes: 3));
    if (result.exitCode != 0 ||
        !_runtime.host.fileSystem.file(binaryPath).existsSync()) {
      final errors = result.stderr
          .split('\n')
          .where((l) => l.contains('error'))
          .take(3)
          .join(' ');
      throw CliError(
        '[touch_setup.build] clang exit ${result.exitCode}'
        '${errors.isEmpty ? '' : ': $errors'}',
      );
    }
  }
}
