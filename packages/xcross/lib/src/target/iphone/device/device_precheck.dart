// studio: 002 — device checks before the build (specs/002-quick-wins, #147).
import 'package:cli_kit/shared/logging/logging.dart';
import 'package:dart_mobile_device/shared/device/models/device.dart';
import 'package:dart_mobile_device/shared/errors/errors.dart';
import 'package:meta/meta.dart';
import 'package:xcross/src/shared/diagnostics/xcross_diagnostics.dart';
import 'package:xcross/src/shared/errors/errors.dart';

/// The device chosen before the build; install and launch reuse it.
@internal
final class PrecheckedDevice {
  const PrecheckedDevice({
    required this.device,
    required this.osMajor,
    this.osVersion,
  });

  final Device device;

  /// Null when the OS version could not be read (the run continues).
  final int? osMajor;

  /// Full version when known, e.g. `16.7.16` (studio: 005).
  final String? osVersion;

  /// iOS 15/16: no CoreDevice; install over usbmux, launch through the
  /// user's developer disk image (studio: 005).
  bool get legacy => osMajor != null && osMajor! < 17;
}

@internal
typedef PrecheckResolveDevice =
    Future<Device> Function({required DeviceSearchMode mode, String? selector});

/// Host service check → device resolution → OS version → minimum gate, all
/// before any build work, so an unusable device fails in seconds.
@internal
final class DevicePrecheck {
  DevicePrecheck({
    required this.log,
    required this.serviceProblem,
    required this.resolveDevice,
    required this.osMajor,
    this.minimumIos = 15, // studio: 005 — iOS 15/16 run the legacy path
  });

  final Log log;

  /// Null when the host device service is reachable, else an explanation
  /// with an OS-specific fix.
  final Future<String?> Function() serviceProblem;
  final PrecheckResolveDevice resolveDevice;
  final Future<int?> Function(Device device) osMajor;
  final int minimumIos;

  Future<PrecheckedDevice> run({
    required DeviceSearchMode mode,
    String? selector,
  }) async {
    final problem = mode == DeviceSearchMode.wifi
        ? null
        : await serviceProblem();
    if (problem != null && mode == DeviceSearchMode.usb) {
      throw _serviceUnavailable(problem);
    }

    final Device device;
    try {
      device = await resolveDevice(selector: selector, mode: mode);
    } on PymdTimeoutError catch (error) {
      throw codedError(XcrossCodes.deviceQueryTimeout, error.message);
    } on DeviceNotFoundError catch (error) {
      // With the service down, "no device" is a symptom; report the cause.
      if (problem != null) throw _serviceUnavailable(problem);
      throw codedError(XcrossCodes.deviceNotFound, error.message);
    }
    log.logInfo('Device', device.name);

    final major = majorOf(device.osVersion) ?? await osMajor(device);
    if (major == null) {
      log.logWarn(
        'Could not read the device OS version; attempting the native '
        'CoreDevice path.',
      );
    } else if (major < minimumIos) {
      throw codedError(
        XcrossCodes.deviceIosUnsupported,
        '${device.name} runs iOS ${device.osVersion ?? major}; xcross needs '
        'iOS $minimumIos or later to install and launch.',
      );
    }
    final prechecked = PrecheckedDevice(
      device: device,
      osMajor: major,
      osVersion: device.osVersion ?? (major == null ? null : '$major'),
    );
    reportDevice(log, prechecked); // studio: 012
    return prechecked;
  }

  // studio: 012 — the chosen device as a `device` event (no UDID).
  /// Reports [device] to the log's event consumer, when there is one.
  static void reportDevice(Log log, PrecheckedDevice device) =>
      log.events?.event('device', {
        'name': device.device.name,
        'osVersion': device.osVersion,
        'legacy': device.legacy,
        'connection': device.device.type.name,
      });

  /// First sentence of the host's explanation is the message, the rest the
  /// hint.
  static XcrossError _serviceUnavailable(String problem) {
    final end = problem.indexOf('. ');
    return end < 0
        ? codedError(XcrossCodes.deviceHostServiceUnavailable, problem)
        : codedError(
            XcrossCodes.deviceHostServiceUnavailable,
            problem.substring(0, end + 1),
            hint: problem.substring(end + 2),
          );
  }

  /// Major version of an iOS version string such as `16.7.10`.
  static int? majorOf(String? version) =>
      version == null ? null : int.tryParse(version.split('.').first);
}
