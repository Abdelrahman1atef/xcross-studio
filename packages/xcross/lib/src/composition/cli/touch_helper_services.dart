// studio: 048 — the engine's downloader, signer and installer for
// `xcross screen touch-setup`.
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:dart_mobile_device/target/iphone/device/pymd/pymd.dart';
import 'package:dart_mobile_device/target/iphone/device/pymd/pymd_devices.dart';
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
}
