import 'package:cli_kit/shared/process/process.dart';
import 'package:dart_mobile_device/host/shared/usbmux_service_probe.dart';
import 'package:dart_mobile_device/shared/host/device_host_policy.dart';
import 'package:dart_mobile_device/src/shared/preparation/tunnel_failure_guidance.dart';

abstract base class PosixDeviceHost implements DeviceHostPolicy {
  const PosixDeviceHost(this.runner);
  final ProcessRunner runner;
  List<String> get pipxDirectories {
    final env = runner.effectiveEnvironment;
    final home = env['HOME'] ?? env['USERPROFILE'];
    return [
      if (env['PIPX_BIN_DIR'] case final String configured
          when configured.isNotEmpty)
        configured,
      if (home != null && home.isNotEmpty)
        runner.host.paths.context.join(home, '.local', 'bin'),
    ];
  }

  @override
  String get preparationDeniedMessage =>
      'xcross needs elevated privileges to create the RSD tunnel.\n'
      'Run the displayed preparation steps with an authorized account.';

  @override
  String describeTunnelFailure(List<String> recent) =>
      describeDeviceTunnelFailure(recent);

  @override
  String get installCommand =>
      'pipx install pymobiledevice3 --pip-args=--prefer-binary && '
      'pipx ensurepath';

  @override
  String elevatedCommand(String arguments) => 'sudo pymobiledevice3 $arguments';

  @override
  Future<String?> resolvePipx() =>
      runner.which('pipx', extraDirectories: pipxDirectories);

  @override
  Future<bool> lockdownTunnelLooksAlive() async {
    try {
      final result = await runner.run(await runner.locateTool('pgrep'), [
        '-f',
        'pymobiledevice3.*lockdown.*start-tunnel',
      ]);
      return result.exitCode == 0 && result.stdout.trim().isNotEmpty;
    } on Object {
      return false;
    }
  }

  // studio: 002 — usbmuxd's default unix socket.
  static const defaultUsbmuxAddress = '/var/run/usbmuxd';

  @override
  Future<String?> deviceServiceProblem(String? usbmuxAddress) async {
    final address = usbmuxAddress ?? defaultUsbmuxAddress;
    if (await usbmuxServiceReachable(address)) return null;
    return 'usbmuxd is not reachable at $address. Install usbmuxd and start '
        'it: sudo systemctl start usbmuxd (and add the udev rules shipped '
        'with usbmuxd if the device is not detected).';
  }
}
