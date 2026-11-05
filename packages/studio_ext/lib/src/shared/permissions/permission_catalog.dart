// studio: 027 — the Info.plist purpose strings a developer can add, with the
// name Xcode shows and a sentence to start from. The sentences are only
// suggestions: App Review wants the developer's own reason, so each one is a
// complete sentence that is not a placeholder.
import 'package:meta/meta.dart';

/// One `NS…UsageDescription` key.
@internal
@immutable
final class PermissionInfo {
  const PermissionInfo(this.key, this.name, this.description, this.suggestion);

  final String key;

  /// What Xcode calls it: "Privacy - Camera Usage Description" → "Camera".
  final String name;

  /// What the key lets the app do, in a clause.
  final String description;

  /// A starting sentence for the purpose string.
  final String suggestion;

  Map<String, Object?> toJson() => {
    'key': key,
    'name': name,
    'description': description,
    'suggestion': suggestion,
  };
}

/// The keys the editor offers.
@internal
abstract final class PermissionCatalog {
  static const all = <PermissionInfo>[
    PermissionInfo(
      'NSCameraUsageDescription',
      'Camera',
      'Take photos and videos, scan codes.',
      'This app uses the camera to take photos and scan codes.',
    ),
    PermissionInfo(
      'NSPhotoLibraryUsageDescription',
      'Photo library',
      'Read photos and videos the user picks.',
      'This app reads photos you choose so you can attach them.',
    ),
    PermissionInfo(
      'NSPhotoLibraryAddUsageDescription',
      'Photo library (add only)',
      'Save photos and videos, without reading the library.',
      'This app saves photos and videos you create to your library.',
    ),
    PermissionInfo(
      'NSLocationWhenInUseUsageDescription',
      'Location, while using the app',
      'Know where the device is while the app is open.',
      'This app uses your location to show what is near you.',
    ),
    PermissionInfo(
      'NSLocationAlwaysAndWhenInUseUsageDescription',
      'Location, always',
      'Know where the device is, also in the background.',
      'This app uses your location, also in the background, to keep '
          'nearby information up to date.',
    ),
    PermissionInfo(
      'NSLocationAlwaysUsageDescription',
      'Location, always (iOS 10 and older)',
      'The older key for background location.',
      'This app uses your location, also in the background, to keep '
          'nearby information up to date.',
    ),
    PermissionInfo(
      'NSMicrophoneUsageDescription',
      'Microphone',
      'Record audio.',
      'This app uses the microphone to record audio and voice messages.',
    ),
    PermissionInfo(
      'NSContactsUsageDescription',
      'Contacts',
      'Read the address book.',
      'This app reads your contacts so you can find people you know.',
    ),
    PermissionInfo(
      'NSBluetoothAlwaysUsageDescription',
      'Bluetooth',
      'Connect to Bluetooth accessories.',
      'This app uses Bluetooth to connect to your nearby devices.',
    ),
    PermissionInfo(
      'NSFaceIDUsageDescription',
      'Face ID',
      'Unlock with Face ID.',
      'This app uses Face ID to unlock your account safely.',
    ),
    PermissionInfo(
      'NSCalendarsFullAccessUsageDescription',
      'Calendars (full access)',
      'Read and change calendar events.',
      'This app reads and adds calendar events for your appointments.',
    ),
    PermissionInfo(
      'NSCalendarsWriteOnlyAccessUsageDescription',
      'Calendars (add only)',
      'Add calendar events without reading them.',
      'This app adds calendar events for your appointments.',
    ),
    PermissionInfo(
      'NSCalendarsUsageDescription',
      'Calendars (iOS 16 and older)',
      'The older key for calendar access.',
      'This app reads and adds calendar events for your appointments.',
    ),
    PermissionInfo(
      'NSRemindersFullAccessUsageDescription',
      'Reminders (full access)',
      'Read and change reminders.',
      'This app creates reminders so you do not miss appointments.',
    ),
    PermissionInfo(
      'NSMotionUsageDescription',
      'Motion and fitness',
      'Read motion sensors and step counts.',
      'This app uses motion data to count your activity.',
    ),
    PermissionInfo(
      'NSUserTrackingUsageDescription',
      'Tracking',
      "Ask to track the user across other companies' apps and sites.",
      'This app uses your device identifier to show you relevant offers.',
    ),
    PermissionInfo(
      'NSSpeechRecognitionUsageDescription',
      'Speech recognition',
      'Turn speech into text.',
      'This app turns your speech into text so you can dictate messages.',
    ),
    PermissionInfo(
      'NSLocalNetworkUsageDescription',
      'Local network',
      'Find and talk to devices on the local network.',
      'This app talks to devices on your local network.',
    ),
    PermissionInfo(
      'NSAppleMusicUsageDescription',
      'Media library',
      'Read the music library.',
      'This app plays music from your media library.',
    ),
    PermissionInfo(
      'NSHealthShareUsageDescription',
      'Health (read)',
      'Read health data.',
      'This app reads your health data to show your progress.',
    ),
    PermissionInfo(
      'NSHealthUpdateUsageDescription',
      'Health (write)',
      'Write health data.',
      'This app saves your measurements to the Health app.',
    ),
    PermissionInfo(
      'NSSiriUsageDescription',
      'Siri',
      'Let Siri use the app.',
      'This app lets you use Siri to start common actions.',
    ),
    PermissionInfo(
      'NFCReaderUsageDescription',
      'NFC',
      'Read NFC tags.',
      'This app reads NFC tags to identify items you scan.',
    ),
    PermissionInfo(
      'NSNearbyInteractionUsageDescription',
      'Nearby interaction',
      'Measure the distance to nearby devices.',
      'This app measures the distance to nearby devices you pair with.',
    ),
    PermissionInfo(
      'NSHomeKitUsageDescription',
      'HomeKit',
      'Control HomeKit accessories.',
      'This app controls the accessories in your home.',
    ),
  ];

  /// The entry for [key], or null for a key the catalog does not know.
  static PermissionInfo? of(String key) {
    for (final info in all) {
      if (info.key == key) return info;
    }
    return null;
  }
}
