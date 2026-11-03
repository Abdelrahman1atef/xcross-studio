// studio: 016 — push without an entitlements file (specs/016-push-firebase-maps).
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:xcross/src/shared/flutter/build/flutter_app_entitlements.dart';
import 'package:xcross/src/shared/flutter/build/ios_plugins.dart';
import 'package:yaml/yaml.dart';

/// What says an app wants remote notifications even when its entitlements
/// file (often missing in Flutter projects) does not declare
/// `aps-environment`.
@internal
@immutable
final class PushSignals {
  const PushSignals({
    required this.usesFirebaseMessaging,
    required this.remoteNotificationMode,
  });

  /// Reads both signals for the project at [projectRoot]; [infoPlistXml] is
  /// the app's Info.plist (the project's own when omitted).
  factory PushSignals.read({
    required HostFileSystemInterface fileSystem,
    required String projectRoot,
    String? infoPlistXml,
  }) {
    final plist =
        infoPlistXml ??
        switch (fileSystem.file(
          p.join(projectRoot, 'ios', 'Runner', 'Info.plist'),
        )) {
          final file when file.existsSync() => file.readAsStringSync(),
          _ => null,
        };
    return PushSignals(
      usesFirebaseMessaging: _plugins(
        fileSystem,
        projectRoot,
      ).contains(firebaseMessaging),
      remoteNotificationMode: plist != null && hasRemoteNotificationMode(plist),
    );
  }

  /// The entitlement key that turns push on.
  static const entitlementKey = 'aps-environment';

  /// The plugin whose presence means the app registers for push.
  static const firebaseMessaging = 'firebase_messaging';

  /// `firebase_messaging` is among the app's iOS plugins or dependencies.
  final bool usesFirebaseMessaging;

  /// `Info.plist` lists `remote-notification` in `UIBackgroundModes`.
  final bool remoteNotificationMode;

  bool get any => usesFirebaseMessaging || remoteNotificationMode;

  /// Why push is wanted, for messages; `null` without a signal.
  String? get reason => usesFirebaseMessaging
      ? 'the app uses $firebaseMessaging'
      : remoteNotificationMode
      ? 'Info.plist lists remote-notification in UIBackgroundModes'
      : null;

  /// Whether the Info.plist XML [plistXml] lists `remote-notification` in
  /// `UIBackgroundModes`.
  @visibleForTesting
  static bool hasRemoteNotificationMode(String plistXml) {
    try {
      final modes = FlutterAppEntitlements.parseDictionary(
        plistXml,
      )['UIBackgroundModes'];
      return modes is List && modes.contains('remote-notification');
    } on FormatException {
      return false;
    }
  }

  /// [declared] plus `aps-environment: development` when a signal exists and
  /// the key is not declared; `null` when nothing is added. The signer keeps
  /// the value the profile grants (`production` for App Store profiles).
  Map<String, Object>? inferInto(Map<String, Object> declared) {
    if (!any || declared.containsKey(entitlementKey)) return null;
    return {...declared, entitlementKey: 'development'};
  }

  /// The iOS plugins `flutter pub get` resolved, plus the direct
  /// dependencies in `pubspec.yaml` (before the first `pub get`).
  static Set<String> _plugins(
    HostFileSystemInterface fileSystem,
    String projectRoot,
  ) {
    final names = <String>{};
    try {
      names.addAll([
        for (final plugin in PluginDiscovery(
          fileSystem,
        ).discoverSync(projectRoot))
          plugin.name,
      ]);
    } on Object {
      // A broken plugin list is reported by the build itself.
    }
    final pubspec = fileSystem.file(p.join(projectRoot, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      try {
        final Object? yaml = loadYaml(pubspec.readAsStringSync());
        if (yaml case {'dependencies': final Map<Object?, Object?> deps}) {
          names.addAll(deps.keys.whereType<String>());
        }
      } on Object {
        // Invalid YAML is reported by pub, not here.
      }
    }
    return names;
  }
}
