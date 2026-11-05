// studio: 027 — which iOS permissions `permission_handler_apple` compiles in.
//
// The plugin compiles every permission OUT unless its macro (`PERMISSION_CAMERA`)
// is set, and a compiled-out permission always answers "denied" without asking.
// CocoaPods builds set the macros from the app's Podfile. Builds without
// CocoaPods get them from the plugin's own `Package.swift`, which reads an
// environment variable per macro, or the app's Info.plist, found by walking up
// from the manifest. xcross builds the plugin from a staging folder, so that
// walk finds no app: every permission is compiled out and the camera never asks.
// This reads the same two places the developer already filled in (the Podfile's
// `PERMISSION_X=1`, the Info.plist purpose strings) and gives the plugin the
// environment variables it understands.
abstract final class PermissionMacros {
  /// The plugin whose manifest reads these variables.
  static const plugin = 'permission_handler_apple';

  /// Info.plist key → the macros its presence enables (the table in the
  /// plugin's `Package.swift`: `enabled("PERMISSION_X", plistKeys: …)`).
  static const byInfoPlistKey = <String, List<String>>{
    'NSCalendarsUsageDescription': ['PERMISSION_EVENTS'],
    'NSCalendarsFullAccessUsageDescription': ['PERMISSION_EVENTS_FULL_ACCESS'],
    'NSCalendarsWriteOnlyAccessUsageDescription': [
      'PERMISSION_EVENTS_FULL_ACCESS',
    ],
    'NSRemindersUsageDescription': ['PERMISSION_REMINDERS'],
    'NSContactsUsageDescription': ['PERMISSION_CONTACTS'],
    'NSCameraUsageDescription': ['PERMISSION_CAMERA'],
    'NSMicrophoneUsageDescription': ['PERMISSION_MICROPHONE'],
    'NSSpeechRecognitionUsageDescription': ['PERMISSION_SPEECH_RECOGNIZER'],
    'NSPhotoLibraryUsageDescription': ['PERMISSION_PHOTOS'],
    'NSPhotoLibraryAddUsageDescription': [
      'PERMISSION_PHOTOS',
      'PERMISSION_PHOTOS_ADD_ONLY',
    ],
    'NSLocationWhenInUseUsageDescription': [
      'PERMISSION_LOCATION',
      'PERMISSION_LOCATION_WHENINUSE',
    ],
    'NSLocationAlwaysAndWhenInUseUsageDescription': [
      'PERMISSION_LOCATION',
      'PERMISSION_LOCATION_ALWAYS',
    ],
    'NSAppleMusicUsageDescription': ['PERMISSION_MEDIA_LIBRARY'],
    'NSMotionUsageDescription': ['PERMISSION_SENSORS'],
    'NSBluetoothAlwaysUsageDescription': ['PERMISSION_BLUETOOTH'],
    'NSBluetoothPeripheralUsageDescription': ['PERMISSION_BLUETOOTH'],
    'NSUserTrackingUsageDescription': ['PERMISSION_APP_TRACKING_TRANSPARENCY'],
    'NSSiriUsageDescription': ['PERMISSION_ASSISTANT'],
  };

  static final _infoKey = RegExp(r'<key>\s*([A-Za-z0-9_.-]+)\s*</key>');
  static final _podfileDefine = RegExp(
    r'''['"](PERMISSION_[A-Z0-9_]+)\s*=\s*([01])['"]''',
  );

  /// The environment variables to build the plugin with, from the project's
  /// [infoPlist] text and [podfile] text (either may be null).
  ///
  /// A permission whose purpose string is in Info.plist is on. A Podfile
  /// `PERMISSION_X=1` turns it on, and `PERMISSION_X=0` turns it off even with
  /// the string present: the developer said so explicitly.
  static Map<String, String> environment({String? infoPlist, String? podfile}) {
    final macros = <String, String>{};
    if (infoPlist != null) {
      for (final match in _infoKey.allMatches(infoPlist)) {
        for (final macro
            in byInfoPlistKey[match.group(1)] ?? const <String>[]) {
          macros[macro] = '1';
        }
      }
    }
    if (podfile != null) {
      for (final match in _podfileDefine.allMatches(podfile)) {
        macros[match.group(1)!] = match.group(2)!;
      }
    }
    return {for (final key in macros.keys.toList()..sort()) key: macros[key]!};
  }
}
