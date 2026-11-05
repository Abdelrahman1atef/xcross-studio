// studio: 027 — the capabilities of Xcode's "Signing & Capabilities" tab that
// are a key in `Runner.entitlements` (or, for background modes, in
// Info.plist), with the shape of their value and the App Store Connect
// capability each one needs on the App ID.
import 'package:meta/meta.dart';

/// How a capability's value is written.
@internal
enum CapabilityValue {
  /// `<true/>`: on or off.
  flag,

  /// One of [CapabilityInfo.choices].
  choice,

  /// A list of strings (domains, group IDs, modes).
  list,
}

/// One capability.
@internal
@immutable
final class CapabilityInfo {
  const CapabilityInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.key,
    required this.value,
    this.ascCapability,
    this.choices = const [],
    this.defaultValue,
    this.inInfoPlist = false,
    this.example,
  });

  /// The word used on the command line: `push`, `associated-domains`.
  final String id;
  final String name;
  final String description;

  /// The entitlement key (or the Info.plist key when [inInfoPlist]).
  final String key;
  final CapabilityValue value;

  /// App Store Connect's `capabilityType` the App ID needs, if any.
  final String? ascCapability;
  final List<String> choices;

  /// What `add` writes without `--value`.
  final Object? defaultValue;

  /// The key lives in `Info.plist` (background modes), not the entitlements.
  final bool inInfoPlist;

  /// A value to show as a hint: `applinks:example.com`.
  final String? example;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'key': key,
    'kind': value.name,
    'choices': choices,
    'ascCapability': ascCapability,
    'inInfoPlist': inInfoPlist,
    'example': example,
  };
}

/// The capabilities the editor offers.
@internal
abstract final class CapabilityCatalog {
  static const all = <CapabilityInfo>[
    CapabilityInfo(
      id: 'push',
      name: 'Push Notifications',
      description: 'Receive remote notifications.',
      key: 'aps-environment',
      value: CapabilityValue.choice,
      choices: ['development', 'production'],
      defaultValue: 'development',
      ascCapability: 'PUSH_NOTIFICATIONS',
    ),
    CapabilityInfo(
      id: 'background-modes',
      name: 'Background Modes',
      description: 'Keep working when the app is in the background.',
      key: 'UIBackgroundModes',
      value: CapabilityValue.list,
      choices: [
        'audio',
        'bluetooth-central',
        'bluetooth-peripheral',
        'external-accessory',
        'fetch',
        'location',
        'processing',
        'remote-notification',
        'voip',
      ],
      defaultValue: ['remote-notification'],
      inInfoPlist: true,
    ),
    CapabilityInfo(
      id: 'sign-in-with-apple',
      name: 'Sign in with Apple',
      description: 'Let people sign in with their Apple ID.',
      key: 'com.apple.developer.applesignin',
      value: CapabilityValue.list,
      defaultValue: ['Default'],
      ascCapability: 'APPLE_ID_AUTH',
    ),
    CapabilityInfo(
      id: 'associated-domains',
      name: 'Associated Domains',
      description: 'Universal links, passkeys and web credentials.',
      key: 'com.apple.developer.associated-domains',
      value: CapabilityValue.list,
      ascCapability: 'ASSOCIATED_DOMAINS',
      example: 'applinks:example.com',
    ),
    CapabilityInfo(
      id: 'app-groups',
      name: 'App Groups',
      description: 'Share data with extensions and other apps of yours.',
      key: 'com.apple.security.application-groups',
      value: CapabilityValue.list,
      ascCapability: 'APP_GROUPS',
      example: 'group.com.example.app',
    ),
    CapabilityInfo(
      id: 'keychain-sharing',
      name: 'Keychain Sharing',
      description: 'Share keychain items between your apps.',
      key: 'keychain-access-groups',
      value: CapabilityValue.list,
      example: r'$(AppIdentifierPrefix)com.example.app',
    ),
    CapabilityInfo(
      id: 'healthkit',
      name: 'HealthKit',
      description: 'Read and write health data.',
      key: 'com.apple.developer.healthkit',
      value: CapabilityValue.flag,
      defaultValue: true,
      ascCapability: 'HEALTHKIT',
    ),
    CapabilityInfo(
      id: 'homekit',
      name: 'HomeKit',
      description: 'Control home accessories.',
      key: 'com.apple.developer.homekit',
      value: CapabilityValue.flag,
      defaultValue: true,
      ascCapability: 'HOMEKIT',
    ),
    CapabilityInfo(
      id: 'apple-pay',
      name: 'Apple Pay',
      description: 'Take payments with Apple Pay.',
      key: 'com.apple.developer.in-app-payments',
      value: CapabilityValue.list,
      ascCapability: 'APPLE_PAY',
      example: 'merchant.com.example.app',
    ),
    CapabilityInfo(
      id: 'wifi-info',
      name: 'Access WiFi Information',
      description: 'Read the name of the WiFi network.',
      key: 'com.apple.developer.networking.wifi-info',
      value: CapabilityValue.flag,
      defaultValue: true,
      ascCapability: 'ACCESS_WIFI_INFORMATION',
    ),
    CapabilityInfo(
      id: 'siri',
      name: 'Siri',
      description: 'Let Siri start actions in the app.',
      key: 'com.apple.developer.siri',
      value: CapabilityValue.flag,
      defaultValue: true,
      ascCapability: 'SIRIKIT',
    ),
    CapabilityInfo(
      id: 'nfc',
      name: 'NFC Tag Reading',
      description: 'Read NFC tags.',
      key: 'com.apple.developer.nfc.readersession.formats',
      value: CapabilityValue.list,
      choices: ['NDEF', 'TAG'],
      defaultValue: ['NDEF'],
      ascCapability: 'NFC_TAG_READING',
    ),
    CapabilityInfo(
      id: 'game-center',
      name: 'Game Center',
      description: 'Leaderboards and achievements.',
      key: 'com.apple.developer.game-center',
      value: CapabilityValue.flag,
      defaultValue: true,
      ascCapability: 'GAME_CENTER',
    ),
  ];

  /// The capability with [id], or null.
  static CapabilityInfo? byId(String id) {
    for (final info in all) {
      if (info.id == id) return info;
    }
    return null;
  }

  /// The capability whose key is [key], or null.
  static CapabilityInfo? byKey(String key) {
    for (final info in all) {
      if (info.key == key) return info;
    }
    return null;
  }
}
