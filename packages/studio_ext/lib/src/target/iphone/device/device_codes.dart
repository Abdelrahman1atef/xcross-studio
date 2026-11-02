import 'package:cli_kit/shared/errors/errors.dart';
import 'package:meta/meta.dart';

/// A stable device-command code with its fix hint
/// (specs/010-device-logs/contracts/cli.md).
@internal
final class DeviceCode {
  const DeviceCode(this.code, this.hint);

  final String code;
  final String hint;
}

/// Codes used by `xcross logs`, `xcross app info` and `xcross crashes`. The
/// device codes match feature 002.
@internal
abstract final class DeviceCodes {
  static const notFound = DeviceCode(
    'device.not_found',
    'Connect the iPhone with a cable, unlock it and tap Trust, then retry '
        '(or pass --wifi for a paired wireless device).',
  );
  static const hostServiceUnavailable = DeviceCode(
    'device.host_service_unavailable',
    'Start the host device service, then retry.',
  );
  static const selectRequired = DeviceCode(
    'device.select_required',
    'Pass --udid <id> to pick one (list them with: pymobiledevice3 usbmux '
        'list).',
  );
  static const notTrusted = DeviceCode(
    'device.not_trusted',
    'Unlock the iPhone and tap Trust on "Trust This Computer?", then retry.',
  );
  static const appNotInstalled = DeviceCode(
    'app.not_installed',
    'Check the bundle id (see the app list with `xcross app list`), or '
        'install the app first.',
  );
  static const crashNotFound = DeviceCode(
    'crash.not_found',
    'Run `xcross crashes list` to see the available reports.',
  );
}

/// A coded failure of a device command.
@internal
final class DeviceFailure implements Exception {
  DeviceFailure(DeviceCode code, this.message, {String? hint})
    : code = code.code,
      hint = hint ?? code.hint;

  final String code;
  final String message;
  final String hint;

  /// `error: [code] message` + `hint:` through the CLI runner.
  CliError toCliError() => CliError('[$code] $message\nhint: $hint');

  @override
  String toString() => '[$code] $message';
}
