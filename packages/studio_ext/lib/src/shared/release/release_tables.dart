// studio: 018 — what App Review and App Store Connect expect, as tables
// (specs/018-app-store-build, research R4).
import 'package:meta/meta.dart';

/// One protected resource a plugin uses: the Info.plist keys of which at least
/// one must be present, and what it is for.
@internal
@immutable
final class UsageRequirement {
  const UsageRequirement(this.resource, this.anyOf);

  final String resource;
  final List<String> anyOf;
}

/// A call whose presence in a binary means Info.plist needs purpose strings,
/// the way App Store Connect finds them (it reads the code, not the plugin
/// list): "Missing purpose string in Info.plist" (90683).
@internal
@immutable
final class UsageSymbol {
  const UsageSymbol(this.symbol, this.resource, this.allOf);

  /// An Objective-C selector or symbol name found in the binary.
  final String symbol;
  final String resource;

  /// Every key must be present.
  final List<String> allOf;
}

/// Release-check knowledge that changes with Apple's rules and plugin
/// releases; kept in one place so updates are one-line edits.
@internal
abstract final class ReleaseTables {
  static const _camera = UsageRequirement('camera', [
    'NSCameraUsageDescription',
  ]);
  static const _photos = UsageRequirement('photo library', [
    'NSPhotoLibraryUsageDescription',
    'NSPhotoLibraryAddUsageDescription',
  ]);
  static const _location = UsageRequirement('location', [
    'NSLocationWhenInUseUsageDescription',
    'NSLocationAlwaysAndWhenInUseUsageDescription',
  ]);
  static const _microphone = UsageRequirement('microphone', [
    'NSMicrophoneUsageDescription',
  ]);
  static const _contacts = UsageRequirement('contacts', [
    'NSContactsUsageDescription',
  ]);
  static const _bluetooth = UsageRequirement('Bluetooth', [
    'NSBluetoothAlwaysUsageDescription',
  ]);
  static const _faceId = UsageRequirement('Face ID', [
    'NSFaceIDUsageDescription',
  ]);
  static const _calendars = UsageRequirement('calendars', [
    'NSCalendarsFullAccessUsageDescription',
    'NSCalendarsUsageDescription',
  ]);
  static const _motion = UsageRequirement('motion', [
    'NSMotionUsageDescription',
  ]);
  static const _tracking = UsageRequirement('tracking', [
    'NSUserTrackingUsageDescription',
  ]);
  static const _speech = UsageRequirement('speech recognition', [
    'NSSpeechRecognitionUsageDescription',
  ]);

  /// Plugin (pub package) → protected resources it reaches.
  static const pluginUsage = <String, List<UsageRequirement>>{
    'image_picker': [_camera, _photos],
    'image_picker_ios': [_camera, _photos],
    'camera': [_camera, _microphone],
    'camera_avfoundation': [_camera, _microphone],
    'mobile_scanner': [_camera],
    'photo_manager': [_photos],
    'gal': [_photos],
    'geolocator': [_location],
    'geolocator_apple': [_location],
    'location': [_location],
    'record': [_microphone],
    'record_ios': [_microphone],
    'flutter_sound': [_microphone],
    'speech_to_text': [_microphone, _speech],
    'flutter_contacts': [_contacts],
    'contacts_service': [_contacts],
    'flutter_blue_plus': [_bluetooth],
    'local_auth': [_faceId],
    'local_auth_darwin': [_faceId],
    'device_calendar': [_calendars],
    'sensors_plus': [_motion],
    'app_tracking_transparency': [_tracking],
  };

  /// `UIBackgroundModes` value → plugins that legitimately need it.
  static const backgroundModePlugins = <String, List<String>>{
    'remote-notification': [
      'firebase_messaging',
      'onesignal_flutter',
      'flutter_local_notifications',
      'pusher_beams',
    ],
    'audio': ['audioplayers', 'just_audio', 'audio_service', 'flutter_sound'],
    'location': ['geolocator', 'location', 'background_location'],
    'fetch': ['workmanager', 'background_fetch'],
    'processing': ['workmanager', 'background_fetch'],
    'voip': ['flutter_callkit_incoming', 'callkeep'],
  };

  /// Calls App Store Connect warned about, with the keys it wanted. Only rules
  /// with a message from Apple behind them are here; add the next one when an
  /// upload reports it (90683 named
  /// NSLocationAlwaysAndWhenInUseUsageDescription for doctory).
  static const usageSymbols = <UsageSymbol>[
    UsageSymbol('requestAlwaysAuthorization', 'always-on location', [
      'NSLocationAlwaysAndWhenInUseUsageDescription',
      'NSLocationWhenInUseUsageDescription',
    ]),
    UsageSymbol('requestWhenInUseAuthorization', 'location', [
      'NSLocationWhenInUseUsageDescription',
    ]),
  ];

  /// Required-reason API category → symbol names whose presence in a binary
  /// means the API is used (Apple's "Describing use of required reason API").
  static const requiredReasonSymbols = <String, List<String>>{
    'NSPrivacyAccessedAPICategoryFileTimestamp': [
      'NSFileCreationDate',
      'NSFileModificationDate',
      'NSURLContentModificationDateKey',
      'NSURLCreationDateKey',
      'getattrlist',
    ],
    'NSPrivacyAccessedAPICategorySystemBootTime': [
      'systemUptime',
      'mach_absolute_time',
    ],
    'NSPrivacyAccessedAPICategoryDiskSpace': [
      'NSFileSystemFreeSize',
      'NSFileSystemSize',
      'volumeAvailableCapacityKey',
      'NSURLVolumeAvailableCapacityKey',
      'statfs',
    ],
    'NSPrivacyAccessedAPICategoryActiveKeyboards': ['activeInputModes'],
    'NSPrivacyAccessedAPICategoryUserDefaults': ['NSUserDefaults'],
  };

  /// SDKs on Apple's list of commonly used SDKs that must ship a privacy
  /// manifest, as frameworks or Flutter plugins name them.
  static const sdksNeedingManifest = <String>{
    'Flutter',
    'FirebaseCore',
    'FirebaseCoreInternal',
    'FirebaseMessaging',
    'FirebaseInstallations',
    'FirebaseCrashlytics',
    'FirebaseAnalytics',
    'GoogleUtilities',
    'GoogleDataTransport',
    'nanopb',
    'FBLPromises',
    'AppAuth',
    'GTMSessionFetcher',
    'OneSignal',
    'SDWebImage',
    'Alamofire',
    'Kingfisher',
    'Lottie',
    'RxSwift',
    'SnapKit',
    'Starscream',
    'SwiftyJSON',
    'connectivity_plus',
    'device_info_plus',
    'file_picker',
    'fluttertoast',
    'image_picker_ios',
    'package_info_plus',
    'path_provider_foundation',
    'shared_preferences_foundation',
    'sqflite',
    'sqflite_darwin',
    'url_launcher_ios',
    'webview_flutter_wkwebview',
  };

  /// The toolchain keys Xcode writes and App Store Connect reads.
  static const dtKeys = [
    'DTCompiler',
    'DTPlatformBuild',
    'DTSDKBuild',
    'DTXcode',
    'DTXcodeBuild',
  ];

  /// App Store Connect's minimum iOS SDK (since April 2026).
  static const minimumSdkMajor = 26;

  /// The lowest deployment target Flutter and App Store builds support.
  static const minimumDeploymentTarget = 13;

  /// iPad multitasking needs all four orientations unless the app opts out.
  static const allOrientations = [
    'UIInterfaceOrientationPortrait',
    'UIInterfaceOrientationPortraitUpsideDown',
    'UIInterfaceOrientationLandscapeLeft',
    'UIInterfaceOrientationLandscapeRight',
  ];
}
