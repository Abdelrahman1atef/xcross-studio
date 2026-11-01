// studio: 005 — launching on iOS 15/16, where CoreDevice is not available.
import 'package:cli_kit/shared/logging/logging.dart';
import 'package:cli_kit/shared/process/process_models.dart';
import 'package:dart_mobile_device/shared/errors/errors.dart';
import 'package:meta/meta.dart';
import 'package:xcross/src/target/iphone/device/ddi_locator.dart';

/// Runs one pymobiledevice3 command (throws [TunnelError] on failure).
@internal
typedef PymdCommand =
    Future<CapturedProcess> Function(List<String> args, {Duration? timeout});

/// Opens an installed app on an iOS 15/16 device: mounts the user's
/// developer disk image and launches through DVT, or explains how to open it
/// by hand. Never fails the run: the app is already installed.
@internal
final class LegacyDeviceLauncher {
  LegacyDeviceLauncher({required this.run, required this.log});

  final PymdCommand run;
  final Log log;

  static const _timeout = Duration(seconds: 60);
  static final _alreadyMounted = RegExp(
    'already mounted|AlreadyMounted',
    caseSensitive: false,
  );

  /// True when the app was launched.
  Future<bool> launch({
    required String udid,
    required String bundleId,
    required String? osVersion,
    required DeveloperDiskImagePaths? ddi,
  }) async {
    if (ddi == null) {
      _guidance(bundleId, osVersion, reason: null);
      return false;
    }
    try {
      await log.logStep(
        'Mounting developer disk image',
        () => run([
          'mounter',
          'mount-developer',
          ddi.image,
          ddi.signature,
          '--udid',
          udid,
        ], timeout: _timeout),
      );
    } on TunnelError catch (error) {
      if (!_alreadyMounted.hasMatch(error.message)) {
        _guidance(
          bundleId,
          osVersion,
          reason: 'mounting failed: ${error.message}',
        );
        return false;
      }
    }
    try {
      await log.logStep(
        'Launching',
        () => run([
          'developer',
          'dvt',
          'launch',
          bundleId,
          '--udid',
          udid,
        ], timeout: _timeout),
      );
      log.logInfo('Launched', bundleId);
      return true;
    } on TunnelError catch (error) {
      _guidance(bundleId, osVersion, reason: 'launch failed: ${error.message}');
      return false;
    }
  }

  void _guidance(
    String bundleId,
    String? osVersion, {
    required String? reason,
  }) {
    if (reason != null) {
      log.logWarn('Could not open the app automatically ($reason).');
    }
    log
      ..logInfo(
        'Installed',
        'Tap the app icon on the iPhone to open it '
            '(iOS ${osVersion ?? '< 17'} needs a developer disk image for remote '
            'launch: pass --ddi <dir> with DeveloperDiskImage.dmg + .signature '
            'from an Xcode that supports this iOS version).',
      )
      ..logInfo('Logs', 'xcross logs --app $bundleId');
  }
}
