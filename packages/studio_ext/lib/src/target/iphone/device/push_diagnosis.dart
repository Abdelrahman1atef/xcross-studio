import 'package:meta/meta.dart';

import 'package:studio_ext/src/target/iphone/device/log_filter.dart';
import 'package:studio_ext/src/target/iphone/device/log_output.dart';

/// The push preset's conclusion (research D6).
@internal
enum PushVerdict {
  missingEntitlement('missing_entitlement'),
  permissionDenied('permission_denied'),
  appNotRunning('app_not_running'),
  notRegistered('not_registered'),
  registeredNoDelivery('registered_no_delivery'),
  delivered('delivered');

  const PushVerdict(this.wire);

  final String wire;
}

/// Collects push evidence from the stream and explains it.
@internal
final class PushDiagnosis {
  PushDiagnosis({required this.bundleId, required this.entitlement});

  final String bundleId;

  /// Installed `aps-environment`, null when missing.
  final String? entitlement;

  bool appSeen = false;
  bool registrationSeen = false;
  bool deliverySeen = false;
  bool permissionDenied = false;
  bool entitlementError = false;

  /// Records what [event] shows; [fromApp] marks lines of the app itself.
  void observe(DeviceLogEvent event, {required bool fromApp}) {
    if (fromApp) appSeen = true;
    final message = event.entry.message;
    switch (event.highlight) {
      case Highlight.registration:
        registrationSeen = true;
      case Highlight.delivery:
        deliverySeen = true;
      case Highlight.error:
        if (LogFilter.mentionsEntitlementError(message)) {
          entitlementError = true;
        } else if (LogFilter.mentionsPermissionDenied(message)) {
          permissionDenied = true;
        }
      case null:
        break;
    }
  }

  /// Marks that the app process logged something (any preset line or not).
  void sawApp() => appSeen = true;

  PushVerdict get verdict {
    if (entitlement == null || entitlementError) {
      return PushVerdict.missingEntitlement;
    }
    if (permissionDenied) return PushVerdict.permissionDenied;
    if (deliverySeen) return PushVerdict.delivered;
    if (!appSeen) return PushVerdict.appNotRunning;
    if (!registrationSeen) return PushVerdict.notRegistered;
    return PushVerdict.registeredNoDelivery;
  }

  String get hint => switch (verdict) {
    PushVerdict.missingEntitlement =>
      'The installed app has no aps-environment entitlement, so iOS never '
          'registers it with APNs. Re-sign with the Push Notifications '
          'capability (feature 003) and check `xcross app info $bundleId`.',
    PushVerdict.permissionDenied =>
      'Notifications are not allowed for this app. Enable them in Settings → '
          'Notifications, or reinstall to see the permission prompt again.',
    PushVerdict.appNotRunning =>
      'The app did not log anything. Launch it on the iPhone while this runs.',
    PushVerdict.notRegistered =>
      'The app ran but no APNs registration was seen. Check that it calls '
          'registerForRemoteNotifications (Firebase Messaging setup) and that '
          'the device has network access to APNs.',
    PushVerdict.registeredNoDelivery =>
      'The app registered with APNs but no message arrived yet. Send a test '
          'message now, and make sure the server uses the $entitlement '
          'APNs environment.',
    PushVerdict.delivered =>
      'A push message reached the device. If nothing showed, check the app '
          'in-foreground handling and notification settings.',
  };

  /// Human block printed at the checkpoint and at the end.
  String toHuman() =>
      'Push diagnosis for $bundleId\n'
      '  ${_mark(entitlement != null && !entitlementError)} entitlement      '
      '${entitlement == null ? 'aps-environment missing' : 'aps-environment = $entitlement'}\n'
      '  ${_mark(appSeen)} app running      ${appSeen ? 'yes' : 'no lines from the app'}\n'
      '  ${_mark(!permissionDenied)} permission       ${permissionDenied ? 'denied' : 'no denial seen'}\n'
      '  ${_mark(registrationSeen)} APNs registration ${registrationSeen ? 'seen' : 'not seen'}\n'
      '  ${_mark(deliverySeen)} delivery         ${deliverySeen ? 'seen' : 'not seen'}\n'
      '  verdict: ${verdict.wire}\n'
      '  hint: $hint\n';

  static String _mark(bool ok) => ok ? '✔' : '✖';

  /// NDJSON `diagnosis` event.
  Map<String, Object?> toJson() => {
    'v': 1,
    'type': 'diagnosis',
    'bundleId': bundleId,
    'entitlement': entitlement,
    'appSeen': appSeen,
    'registrationSeen': registrationSeen,
    'deliverySeen': deliverySeen,
    'permissionDenied': permissionDenied,
    'verdict': verdict.wire,
    'hint': hint,
  };
}
