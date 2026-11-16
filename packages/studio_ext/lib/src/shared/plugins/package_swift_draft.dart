// studio: 006 — draft a Package.swift override from a plugin's podspec.
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/plugins/podspec.dart';

/// A pod with a known Swift package.
@internal
final class KnownPackage {
  const KnownPackage(
    this.url,
    this.package,
    this.product, {
    this.objectiveCModules = const {},
    this.defaultVersion,
    this.minimumIos,
    this.flatHeaders = false,
    this.since,
    this.extraProducts = const [],
  });

  /// More products of the same package the pod brings (the whole
  /// OneSignalXCFramework pod is four SwiftPM products).
  final List<String> extraProducts;

  /// The first release with a Swift package. A plugin that asks only for older
  /// releases cannot be drafted: SwiftPM would fail to resolve it, where
  /// leaving the plugin out keeps the build working (see [swiftPackageFor]).
  final String? since;

  final String url;

  /// SwiftPM package identity (last URL path component).
  final String package;
  final String product;

  /// Pod module → the module its Objective-C API has in the Swift package,
  /// where they differ (`@import GoogleMapsUtils;` must become
  /// `@import GoogleMapsUtilsObjC;`: the SwiftPM `GoogleMapsUtils` module is
  /// the Swift layer).
  final Map<String, String> objectiveCModules;

  /// The lowest version to ask for when the podspec names none: CocoaPods
  /// then takes the newest release, and a placeholder `from: "1.0.0"` asked
  /// SDWebImage for 1.x, which conflicts with every other user of it
  /// (a client app, 2026-11-03).
  final String? defaultVersion;

  /// The iOS version the package needs, when it can be above a podspec's:
  /// SwiftPM refuses a dependency with a higher minimum than its user.
  final String? minimumIos;

  /// The Swift package's public headers are not in a `<product>/` folder, so
  /// `#import <Mantle/Mantle.h>` cannot be found: Objective-C must use
  /// `@import Mantle;` (see [patchFlatHeaderImports]).
  final bool flatHeaders;
}

/// The Facebook SDK's Swift package names its products differently from the
/// pods (`FBSDKLoginKit` comes with `FacebookLogin`).
KnownPackage _facebook(String product) => KnownPackage(
  'https://github.com/facebook/facebook-ios-sdk',
  'facebook-ios-sdk',
  product,
  minimumIos: '12.0',
);

/// The higher of two dotted versions.
String _higherVersion(String a, String b) {
  List<int> parts(String v) => [
    for (final part in v.split('.')) int.tryParse(part) ?? 0,
  ];
  final left = parts(a);
  final right = parts(b);
  for (var i = 0; i < left.length || i < right.length; i++) {
    final x = i < left.length ? left[i] : 0;
    final y = i < right.length ? right[i] : 0;
    if (x != y) return x > y ? a : b;
  }
  return a;
}

/// Compares two dotted versions (missing parts are 0).
int _compareVersions(List<int> a, List<int> b) {
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

List<int> _versionParts(String v) => [
  for (final part in v.split('.')) int.tryParse(part) ?? 0,
];

/// Whether the CocoaPods [requirement] allows [since] or a newer release
/// (SwiftPM takes the newest allowed): `~> 6.3` allows up to 7.0, `~> 6.0.3`
/// up to 6.1, `>= 2.0` everything after, `1.2.0` only itself. No requirement
/// means the package's default version, which is never below [since].
@internal
bool requirementReaches(String? requirement, String since) {
  final raw = requirement?.trim() ?? '';
  final first = _versionParts(since);
  final pessimistic = RegExp(r'^~>\s*([\d.]+)$').firstMatch(raw);
  if (pessimistic != null) {
    final v = _versionParts(pessimistic.group(1)!);
    final below = v.length >= 3 ? [v[0], v[1] + 1] : [v[0] + 1];
    return _compareVersions(first, below) < 0;
  }
  final exact = RegExp(r'^=?\s*([\d.]+)$').firstMatch(raw);
  if (exact != null) {
    return _compareVersions(_versionParts(exact.group(1)!), first) >= 0;
  }
  return true;
}

/// The Swift package for [pod] when one is known for the release the plugin
/// asks for ([requirement]); null leaves the plugin out of the build, with a
/// warning.
@internal
KnownPackage? swiftPackageFor(String pod, String? requirement) {
  final known = knownPackageFor(pod);
  final since = known?.since;
  if (since == null || requirementReaches(requirement, since)) return known;
  return null;
}

/// Swift packages for pods that plugins commonly depend on.
@internal
KnownPackage? knownPackageFor(String pod) {
  final base = pod.split('/').first;
  if (base == 'Firebase' || base.startsWith('Firebase')) {
    final product = pod.contains('/') ? 'Firebase${pod.split('/').last}' : base;
    return KnownPackage(
      'https://github.com/firebase/firebase-ios-sdk',
      'firebase-ios-sdk',
      product == 'FirebaseCore' || product == 'Firebase'
          ? 'FirebaseCore'
          : product,
    );
  }
  // onesignal_flutter: from 5.0 the modules are OneSignalFramework,
  // OneSignalInAppMessages, OneSignalLocation and OneSignalExtension (3.x had
  // one `OneSignal` module), and the whole pod is all four.
  if (base == 'OneSignalXCFramework') {
    const products = [
      'OneSignalFramework',
      'OneSignalInAppMessages',
      'OneSignalLocation',
      'OneSignalExtension',
    ];
    final subspec = pod.contains('/') ? pod.split('/').last : null;
    final product = products.contains(subspec) ? subspec! : products.first;
    return KnownPackage(
      'https://github.com/OneSignal/OneSignal-XCFramework',
      'OneSignal-XCFramework',
      product,
      since: '5.0.0',
      extraProducts: subspec == null ? products.skip(1).toList() : const [],
    );
  }
  return switch (base) {
    'GoogleMaps' => const KnownPackage(
      'https://github.com/googlemaps/ios-maps-sdk',
      'ios-maps-sdk',
      'GoogleMaps',
    ),
    'Google-Maps-iOS-Utils' => const KnownPackage(
      'https://github.com/googlemaps/google-maps-ios-utils',
      'google-maps-ios-utils',
      'GoogleMapsUtils',
      // google_maps_flutter_ios: "unknown type name 'GMUGradient'" (a client app,
      // 2026-11-02).
      objectiveCModules: {'GoogleMapsUtils': 'GoogleMapsUtilsObjC'},
    ),
    'PusherSwift' => const KnownPackage(
      'https://github.com/pusher/pusher-websocket-swift',
      'pusher-websocket-swift',
      'PusherSwift',
    ),
    'Alamofire' => const KnownPackage(
      'https://github.com/Alamofire/Alamofire',
      'Alamofire',
      'Alamofire',
      defaultVersion: '5.0.0',
    ),
    'SDWebImage' => const KnownPackage(
      'https://github.com/SDWebImage/SDWebImage',
      'SDWebImage',
      'SDWebImage',
      defaultVersion: '5.0.0',
    ),
    'SDWebImageWebPCoder' => const KnownPackage(
      'https://github.com/SDWebImage/SDWebImageWebPCoder',
      'SDWebImageWebPCoder',
      'SDWebImageWebPCoder',
      defaultVersion: '0.14.0',
      flatHeaders: true,
    ),
    'FBSDKLoginKit' => _facebook('FacebookLogin'),
    'FBSDKCoreKit' => _facebook('FacebookCore'),
    'FBSDKShareKit' => _facebook('FacebookShare'),
    'Mantle' => const KnownPackage(
      'https://github.com/Mantle/Mantle',
      'Mantle',
      'Mantle',
      defaultVersion: '2.2.0',
      flatHeaders: true,
    ),
    'Kingfisher' => const KnownPackage(
      'https://github.com/onevcat/Kingfisher',
      'Kingfisher',
      'Kingfisher',
    ),
    // A client app's TikTok App Events bridge (2026-11-15): "no Swift package
    // is known for TikTokBusinessSDK", so the build left its native code out.
    // The SDK ships a Package.swift from 1.3.4 on. No Objective-C module
    // rename: before 1.7 the module is `TikTokBusinessSDK`, from 1.7 it is
    // `TikTokBusinessSDKCore`, and the documented
    // `#import <TikTokBusinessSDK/TikTokBusiness.h>` works with both.
    'TikTokBusinessSDK' => const KnownPackage(
      'https://github.com/tiktok/tiktok-business-ios-sdk',
      'tiktok-business-ios-sdk',
      'TikTokBusinessSDK',
      defaultVersion: '1.7.0',
      minimumIos: '12.0',
      since: '1.3.4',
    ),
    // The pods below come from a scan of the most used pub.dev iOS plugins
    // that still ship only a podspec (2026-11-15). Each package, its product
    // and the module the plugin imports were checked against the vendor's
    // Package.swift at the version the plugin asks for.
    //
    // flutter_inappwebview_ios (`import OrderedSet`); tags are `v6.0.3`,
    // which SwiftPM reads as 6.0.3.
    'OrderedSet' => const KnownPackage(
      'https://github.com/Weebly/OrderedSet',
      'OrderedSet',
      'OrderedSet',
      defaultVersion: '6.0.0',
      since: '5.0.0',
    ),
    // flutter_libphonenumber_ios (`PhoneNumberKit/PhoneNumberKitCore`),
    // libphonenumber_plugin. CocoaPods takes 4.x when no version is named.
    'PhoneNumberKit' => const KnownPackage(
      'https://github.com/marmelroy/PhoneNumberKit',
      'PhoneNumberKit',
      'PhoneNumberKit',
      defaultVersion: '4.0.0',
      minimumIos: '12.0',
      since: '3.0.0',
    ),
    // video_thumbnail: it imports "webp/decode.h" first, the header path of
    // this package (the libwebp pod itself has no Swift package).
    'libwebp' => const KnownPackage(
      'https://github.com/SDWebImage/libwebp-Xcode',
      'libwebp-Xcode',
      'libwebp',
      defaultVersion: '1.1.0',
      since: '1.1.0',
    ),
    // auth0_flutter before it built from darwin/ with its own Package.swift
    // (it pins all three; Auth0 3.x pins the same JWTDecode and
    // SimpleKeychain versions in its Package.swift). No iOS raise: the
    // plugin's podspec already names what its Auth0 release needs.
    'Auth0' => const KnownPackage(
      'https://github.com/auth0/Auth0.swift',
      'Auth0.swift',
      'Auth0',
    ),
    'JWTDecode' => const KnownPackage(
      'https://github.com/auth0/JWTDecode.swift',
      'JWTDecode.swift',
      'JWTDecode',
    ),
    'SimpleKeychain' => const KnownPackage(
      'https://github.com/auth0/SimpleKeychain',
      'SimpleKeychain',
      'SimpleKeychain',
    ),
    // flutter_jailbreak_detection (no version named).
    'IOSSecuritySuite' => const KnownPackage(
      'https://github.com/securing/IOSSecuritySuite',
      'IOSSecuritySuite',
      'IOSSecuritySuite',
      defaultVersion: '2.0.0',
      since: '2.0.0',
    ),
    // instabug_flutter: a binary package; the framework inside is
    // `InstabugSDK`, which is what the plugin imports.
    'Instabug' => const KnownPackage(
      'https://github.com/Instabug/Instabug-SP',
      'Instabug-SP',
      'Instabug',
      since: '10.1.0',
    ),
    // applovin_max: a binary package with the same releases as the pod.
    'AppLovinSDK' => const KnownPackage(
      'https://github.com/AppLovin/AppLovin-MAX-Swift-Package',
      'AppLovin-MAX-Swift-Package',
      'AppLovinSDK',
      since: '10.3.7',
    ),
    // facebook_audience_network (`~> 6.3`): Meta publishes the Swift
    // package from 6.21.0 on, for iOS 15.
    'FBAudienceNetwork' => const KnownPackage(
      'https://github.com/facebook/FBAudienceNetwork',
      'FBAudienceNetwork',
      'FBAudienceNetwork',
      minimumIos: '15.0',
      since: '6.21.0',
    ),
    // edge_detection (no version named) ships WeScan 3.0.0's sources and is
    // written against it; WeScan 1.x has no library package.
    'WeScan' => const KnownPackage(
      'https://github.com/WeTransfer/WeScan',
      'WeScan',
      'WeScan',
      defaultVersion: '3.0.0',
      minimumIos: '13.0',
      since: '3.0.0',
    ),
    _ => _vendorPackages[base],
  };
}

/// Pods of SDK vendors that publish their own Swift package, mapped the way
/// the plugins that moved to Swift Package Manager map them in their
/// Package.swift (pub.dev, 2026-11-15). Older versions of those plugins
/// ship only a podspec, so apps that did not upgrade still need a draft.
/// `since` is the vendor's first tag with a Package.swift; `defaultVersion`
/// mirrors CocoaPods taking the newest release when no version is named.
const _vendorPackages = <String, KnownPackage>{
  // image_cropper. The package's headers are not in a TOCropViewController/
  // folder: image_cropper 8.0.2 failed with "'TOCropViewController/
  // TOCropViewController.h' file not found" (a probe build, 2026-11-15).
  'TOCropViewController': KnownPackage(
    'https://github.com/TimOliver/TOCropViewController',
    'TOCropViewController',
    'TOCropViewController',
    defaultVersion: '3.0.0',
    since: '2.5.3',
    flatHeaders: true,
  ),
  // flutter_callkit_incoming
  'CryptoSwift': KnownPackage(
    'https://github.com/krzyzanowskim/CryptoSwift',
    'CryptoSwift',
    'CryptoSwift',
    defaultVersion: '1.8.0',
  ),
  // flutter_udid
  'KeychainAccess': KnownPackage(
    'https://github.com/kishikawakatsumi/KeychainAccess',
    'KeychainAccess',
    'KeychainAccess',
    defaultVersion: '4.0.0',
    since: '2.3.2',
  ),
  // flutter_archive
  'ZIPFoundation': KnownPackage(
    'https://github.com/weichsel/ZIPFoundation',
    'ZIPFoundation',
    'ZIPFoundation',
    defaultVersion: '0.9.0',
  ),
  // posthog_flutter
  'PostHog': KnownPackage(
    'https://github.com/PostHog/posthog-ios',
    'posthog-ios',
    'PostHog',
    defaultVersion: '3.0.0',
    since: '2.0.0',
  ),
  // amplitude_flutter
  'AmplitudeSwift': KnownPackage(
    'https://github.com/amplitude/Amplitude-Swift',
    'Amplitude-Swift',
    'AmplitudeSwift',
    defaultVersion: '1.0.0',
  ),
  // speech_to_text
  'CwlCatchException': KnownPackage(
    'https://github.com/mattgallagher/CwlCatchException',
    'CwlCatchException',
    'CwlCatchException',
    defaultVersion: '2.0.0',
    since: '1.0.0',
  ),
  // barcode_scan2, reactive_ble_mobile
  'SwiftProtobuf': KnownPackage(
    'https://github.com/apple/swift-protobuf',
    'swift-protobuf',
    'SwiftProtobuf',
    defaultVersion: '1.0.0',
    since: '0.9.13',
  ),
  // patrol
  'CocoaAsyncSocket': KnownPackage(
    'https://github.com/robbiehanson/CocoaAsyncSocket',
    'CocoaAsyncSocket',
    'CocoaAsyncSocket',
    defaultVersion: '7.6.4',
    since: '7.6.4',
  ),
  // google_sign_in_ios
  'GoogleSignIn': KnownPackage(
    'https://github.com/google/GoogleSignIn-iOS',
    'GoogleSignIn-iOS',
    'GoogleSignIn',
    defaultVersion: '10.0.0',
    since: '6.0.0',
  ),
  // google_mobile_ads and its mediation adapters
  'Google-Mobile-Ads-SDK': KnownPackage(
    'https://github.com/googleads/swift-package-manager-google-mobile-ads',
    'swift-package-manager-google-mobile-ads',
    'GoogleMobileAds',
    defaultVersion: '13.0.0',
    since: '9.0.0',
  ),
  // flutter_appauth: its own Package.swift build uses `@import AppAuth;`
  // where CocoaPods builds use `#import <AppAuth/AppAuth.h>`.
  'AppAuth': KnownPackage(
    'https://github.com/openid/AppAuth-iOS',
    'AppAuth-iOS',
    'AppAuth',
    defaultVersion: '3.0.0',
    since: '1.4.0',
    flatHeaders: true,
  ),
  // msal_auth
  'MSAL': KnownPackage(
    'https://github.com/AzureAD/microsoft-authentication-library-for-objc',
    'microsoft-authentication-library-for-objc',
    'MSAL',
    defaultVersion: '2.0.0',
    since: '1.1.14',
  ),
  // purchases_flutter
  'PurchasesHybridCommon': KnownPackage(
    'https://github.com/RevenueCat/purchases-hybrid-common',
    'purchases-hybrid-common',
    'PurchasesHybridCommon',
    since: '13.3.0',
  ),
  // appsflyer_sdk: its Main and Strict subspecs are both AppsFlyerLib.
  'AppsFlyerFramework': KnownPackage(
    'https://github.com/AppsFlyerSDK/AppsFlyerFramework',
    'AppsFlyerFramework',
    'AppsFlyerLib',
    since: '6.0.8',
  ),
  // flutter_branch_sdk; before 3.0 the pod and module were `Branch`.
  'BranchSDK': KnownPackage(
    'https://github.com/BranchMetrics/ios-branch-sdk-spm',
    'ios-branch-sdk-spm',
    'BranchSDK',
    since: '3.0.0',
  ),
  // intercom_flutter (no version named)
  'Intercom': KnownPackage(
    'https://github.com/intercom/intercom-ios-sp',
    'intercom-ios-sp',
    'Intercom',
    defaultVersion: '19.0.0',
    since: '15.0.2',
  ),
  // clevertap_plugin: the headers sit directly in include/, so
  // `#import <CleverTapSDK/…>` needs `@import CleverTapSDK;`.
  'CleverTap-iOS-SDK': KnownPackage(
    'https://github.com/CleverTap/clevertap-ios-sdk',
    'clevertap-ios-sdk',
    'CleverTapSDK',
    since: '3.9.3',
    flatHeaders: true,
  ),
  // singular_flutter_sdk
  'Singular-SDK': KnownPackage(
    'https://github.com/singular-labs/Singular-iOS-SDK',
    'Singular-iOS-SDK',
    'Singular',
    since: '10.4.1',
  ),
  // unity_ads_plugin
  'UnityAds': KnownPackage(
    'https://github.com/Unity-Technologies/Unity-Ads-Swift-Package',
    'Unity-Ads-Swift-Package',
    'UnityAds',
    since: '4.16.5',
  ),
  // flutter_line_sdk
  'LineSDKSwift': KnownPackage(
    'https://github.com/line/line-sdk-ios-swift',
    'line-sdk-ios-swift',
    'LineSDK',
    since: '5.4.0',
  ),
  // mixpanel_flutter
  'Mixpanel-swift': KnownPackage(
    'https://github.com/mixpanel/mixpanel-swift',
    'mixpanel-swift',
    'Mixpanel',
    since: '2.8.0',
  ),
  // freshchat_sdk
  'FreshchatSDK': KnownPackage(
    'https://github.com/freshworks-oss/freshchat-ios',
    'freshchat-ios',
    'FreshchatSDK',
    since: '5.0.7',
  ),
  // crisp_chat
  'Crisp': KnownPackage(
    'https://github.com/crisp-im/crisp-sdk-ios',
    'crisp-sdk-ios',
    'Crisp',
    since: '1.0.6',
  ),
  // twilio_voice
  'TwilioVoice': KnownPackage(
    'https://github.com/twilio/twilio-voice-ios',
    'twilio-voice-ios',
    'TwilioVoice',
    since: '6.2.0',
  ),
  // screen_protector
  'ScreenProtectorKit': KnownPackage(
    'https://github.com/prongbang/ScreenProtectorKit',
    'ScreenProtectorKit',
    'ScreenProtectorKit',
    since: '1.0.0',
  ),
  // newrelic_mobile
  'NewRelicAgent': KnownPackage(
    'https://github.com/newrelic/newrelic-ios-agent-spm',
    'newrelic-ios-agent-spm',
    'NewRelic',
    since: '7.1.0',
  ),
  // superwallkit_flutter
  'SuperwallKit': KnownPackage(
    'https://github.com/superwall/Superwall-iOS',
    'Superwall-iOS',
    'SuperwallKit',
  ),
  // qonversion_flutter
  'QonversionSandwich': KnownPackage(
    'https://github.com/qonversion/sandwich-sdk',
    'sandwich-sdk',
    'QonversionSandwich',
    since: '7.13.0',
  ),
  // flutter_naver_map
  'NMapsMap': KnownPackage(
    'https://github.com/navermaps/SPM-NMapsMap',
    'SPM-NMapsMap',
    'NMapsMap',
    since: '3.16.2',
  ),
  // maplibre_gl
  'MapLibre': KnownPackage(
    'https://github.com/maplibre/maplibre-gl-native-distribution',
    'maplibre-gl-native-distribution',
    'MapLibre',
    since: '5.9.0',
  ),
  // background_fetch, flutter_background_geolocation
  'TSBackgroundFetch': KnownPackage(
    'https://github.com/transistorsoft/transistor-background-fetch',
    'transistor-background-fetch',
    'TSBackgroundFetch',
    since: '4.0.0',
  ),
  // awesome_notifications
  'IosAwnCore': KnownPackage(
    'https://github.com/rafaelsetragni/IosAwnCore',
    'IosAwnCore',
    'IosAwnCore',
    since: '0.12.0',
  ),
  // braze_plugin: each pod is the product of the same name.
  'BrazeKit': KnownPackage(
    'https://github.com/braze-inc/braze-swift-sdk',
    'braze-swift-sdk',
    'BrazeKit',
    since: '5.0.0',
  ),
  'BrazeUI': KnownPackage(
    'https://github.com/braze-inc/braze-swift-sdk',
    'braze-swift-sdk',
    'BrazeUI',
    since: '5.0.0',
  ),
  'BrazeLocation': KnownPackage(
    'https://github.com/braze-inc/braze-swift-sdk',
    'braze-swift-sdk',
    'BrazeLocation',
    since: '5.0.0',
  ),
};

/// The SwiftPM version requirement for a CocoaPods [requirement]:
/// `~> 8.4` → up to next major from 8.4.0, `~> 8.4.1` → up to next minor,
/// `>= 2.0` / `2.0` → from / exact.
/// Without a requirement, [defaultVersion] (newest release with that major
/// version) or a placeholder to review.
@internal
String swiftRequirement(String? requirement, {String? defaultVersion}) {
  final raw = requirement?.trim() ?? '';
  String full(String v) {
    final parts = v.split('.');
    while (parts.length < 3) {
      parts.add('0');
    }
    return parts.take(3).join('.');
  }

  final pessimistic = RegExp(r'^~>\s*([\d.]+)$').firstMatch(raw);
  if (pessimistic != null) {
    final version = pessimistic.group(1)!;
    return version.split('.').length >= 3
        ? '.upToNextMinor(from: "${full(version)}")'
        : '.upToNextMajor(from: "${full(version)}")';
  }
  final atLeast = RegExp(r'^>=?\s*([\d.]+)').firstMatch(raw);
  if (atLeast != null) return 'from: "${full(atLeast.group(1)!)}"';
  final exact = RegExp(r'^=?\s*([\d.]+)$').firstMatch(raw);
  if (exact != null) return 'exact: "${full(exact.group(1)!)}"';
  if (defaultVersion != null) return 'from: "${full(defaultVersion)}"';
  return 'from: "1.0.0" /* TODO: pick a version */';
}

/// A drafted `Package.swift` and what the user must review.
@internal
final class PackageSwiftDraft {
  const PackageSwiftDraft(
    this.text,
    this.notes, {
    this.objcSources = const [],
    this.swiftSources = const [],
    this.splitsSwift = false,
    this.moduleRenames = const {},
    this.flatHeaderModules = const {},
    this.resourceCopies = const {},
    this.generatedFiles = const {},
  });

  /// Files the draft writes into the override folder: path relative to it
  /// → text (the Swift target's bridging header, see [swiftUsedHeaders]).
  final Map<String, String> generatedFiles;

  /// Resources the draft declares that sit outside the target's folder: their
  /// path relative to the podspec folder → where the override needs a copy,
  /// relative to the override folder.
  final Map<String, String> resourceCopies;

  /// Modules whose headers Objective-C must import as modules
  /// (see [patchFlatHeaderImports]).
  final Set<String> flatHeaderModules;

  final String text;
  final List<String> notes;

  /// Swift sources (relative to the podspec folder) that may need patched
  /// copies: see [patchImplicitImports].
  final List<String> swiftSources;

  /// Objective-C sources and headers (relative to the podspec folder) that
  /// may need patched copies: see [splitsSwift] and [moduleRenames].
  final List<String> objcSources;

  /// The plugin is split into Swift + Objective-C targets: `<plugin>-Swift.h`
  /// imports must become `@import <plugin>_swift;`
  /// (see [patchSwiftHeaderImports]).
  final bool splitsSwift;

  /// `@import` renames for the Swift packages' Objective-C modules
  /// (see [patchModuleImports]).
  final Map<String, String> moduleRenames;
}

/// The modules a Swift file relied on CocoaPods for, or empty when it needs
/// none: a pod's Swift files see its umbrella header (Foundation, UIKit and
/// the plugin's own headers, so Flutter) without importing them. SwiftPM has
/// no such thing, so each file must import what it uses.
@internal
List<String> implicitImports(String source) {
  bool imported(String module) => RegExp(
    '^[ \\t]*(?:@\\w+[ \\t]+)*import[ \\t]+(?:\\w+[ \\t]+)?$module\\b',
    multiLine: true,
  ).hasMatch(source);
  final code = _withoutComments(source);
  if (code.trim().isEmpty) return const [];
  final flutter =
      !imported('Flutter') && RegExp(r'\bFlutter[A-Z]\w*').hasMatch(code);
  final uiKit =
      !imported('UIKit') && RegExp(r'\bUI[A-Z][a-z]\w*').hasMatch(code);
  return [
    if (flutter) 'Flutter',
    if (uiKit) 'UIKit',
    // Flutter and UIKit bring Foundation.
    if (!flutter &&
        !uiKit &&
        !imported('Foundation') &&
        !imported('UIKit') &&
        !imported('Flutter'))
      'Foundation',
  ];
}

/// [source] with [implicitImports] added before its first line of code, or
/// null when it needs none.
@internal
String? patchImplicitImports(String source) {
  final missing = implicitImports(source);
  if (missing.isEmpty) return null;
  final eol = source.contains('\r\n') ? '\r\n' : '\n';
  final at = _firstCodeOffset(source);
  return source.replaceRange(
    at,
    at,
    [for (final module in missing) 'import $module$eol'].join(),
  );
}

/// The Objective-C side of [patchImplicitImports], for `.m`, `.mm` and `.h`
/// files: a pod's prefix header gave each file UIKit. Adds it when the file
/// uses UIKit types without importing UIKit or Flutter (whose header brings
/// it), and Foundation when it uses `NS` types and imports nothing at all.
/// Null when it needs neither. [header] guards the import: a header can be
/// included from plain C.
@internal
String? patchImplicitObjcImports(String source, {bool header = false}) {
  bool imported(String framework) => RegExp(
    '(?:#\\s*(?:import|include)\\s*<$framework/|@import\\s+$framework\\b)',
  ).hasMatch(source);
  final code = _withoutComments(source);
  final String module;
  if (RegExp(r'\bUI[A-Z][a-z]\w*').hasMatch(code) &&
      !imported('UIKit') &&
      !imported('Flutter')) {
    module = 'UIKit';
  } else if (RegExp(r'\bNS(?:[A-Z]|_[A-Z])\w*').hasMatch(code) &&
      !RegExp(r'#\s*(?:import|include)\b|@import\b').hasMatch(code)) {
    module = 'Foundation';
  } else {
    return null;
  }
  final eol = source.contains('\r\n') ? '\r\n' : '\n';
  final line = '#import <$module/$module.h>$eol';
  final at = _firstCodeOffset(source);
  return source.replaceRange(
    at,
    at,
    header ? '#ifdef __OBJC__$eol$line#endif$eol' : line,
  );
}

String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// Where the first line that is neither blank nor a comment starts.
int _firstCodeOffset(String source) {
  var offset = 0;
  var inBlock = false;
  for (final line in source.split('\n')) {
    final trimmed = line.trim();
    if (inBlock) {
      if (trimmed.contains('*/')) inBlock = false;
    } else if (trimmed.startsWith('/*')) {
      inBlock = !trimmed.contains('*/');
    } else if (trimmed.isNotEmpty && !trimmed.startsWith('//')) {
      return offset;
    }
    offset += line.length + 1;
  }
  return source.length;
}

/// [source], the header [file], with bare-name imports of headers in another
/// folder given their relative path, or null when nothing changed. CocoaPods
/// flattens a pod's headers, so `#import "X.h"` finds X.h in any folder; under
/// SwiftPM a module built for another target only finds what the path says.
/// [file] and [headers] are relative to one folder, with `/` separators. A
/// name that is unknown or in several folders is left alone.
@internal
String? patchHeaderPaths(
  String source, {
  required String file,
  required List<String> headers,
}) {
  final folder = p.posix.dirname(file);
  final patched = source.replaceAllMapped(
    RegExp(
      r'^([ \t]*#[ \t]*(?:import|include)[ \t]*)"([^"/\\]+\.h)"',
      multiLine: true,
    ),
    (match) {
      final name = match[2]!;
      if (headers.contains(p.posix.join(folder, name))) return match[0]!;
      final found = headers.where((h) => p.posix.basename(h) == name).toList();
      if (found.length != 1) return match[0]!;
      return '${match[1]}"${p.posix.relative(found.single, from: folder)}"';
    },
  );
  return patched == source ? null : patched;
}

/// [source] with `#import <Module/…>` replaced by `@import Module;` for each
/// of [modules], or null when nothing changed.
@internal
String? patchFlatHeaderImports(String source, Set<String> modules) {
  var patched = source;
  for (final module in modules) {
    patched = patched.replaceAll(
      RegExp(
        '^[ \\t]*#[ \\t]*(?:import|include)[ \\t]*<${RegExp.escape(module)}/'
        r'[^>\n]*>[^\n\r]*',
        multiLine: true,
      ),
      '@import $module;',
    );
  }
  return patched == source ? null : patched;
}

/// [source] with `@import <from>;` replaced by `@import <to>;` for every
/// entry of [renames], or null when nothing changed.
@internal
String? patchModuleImports(String source, Map<String, String> renames) {
  var patched = source;
  for (final MapEntry(key: from, value: to) in renames.entries) {
    patched = patched.replaceAll(
      RegExp('@import[ \\t]+${RegExp.escape(from)}[ \\t]*;'),
      '@import $to;',
    );
  }
  return patched == source ? null : patched;
}

/// [source] with its imports of the Swift compatibility header
/// (`#import "<x>-Swift.h"`, `#import <x/x-Swift.h>`, and Flutter's
/// `#if __has_include(<…-Swift.h>) … #else … #endif` fallback block)
/// replaced by `@import <plugin>_swift;`, or null when it has none.
@internal
String? patchSwiftHeaderImports(String source, String plugin) {
  final module = '@import ${plugin}_swift;';
  var patched = source.replaceAllMapped(
    RegExp(
      r'#if\s+__has_include\([<"][^>"]*-Swift\.h[>"]\)[\s\S]*?#endif[^\n]*',
    ),
    (_) => module,
  );
  patched = patched.replaceAllMapped(
    RegExp(r'^[ \t]*#import\s+[<"][^>"]*-Swift\.h[>"][^\n]*', multiLine: true),
    (_) => module,
  );
  return patched == source ? null : patched;
}

/// The headers in [headers] (path → text) that declare an Objective-C class
/// or protocol the Swift code in [swift] uses, sorted.
///
/// A mixed plugin is split into a Swift and an Objective-C target, and the
/// Objective-C one depends on the Swift one. When the Swift code calls the
/// plugin's Objective-C classes back (flutter_background_service_ios 5.0.3
/// calls `FlutterBackgroundServicePlugin.register(engine)`: "cannot find
/// 'FlutterBackgroundServicePlugin' in scope", 2026-11-11), the Swift target
/// needs their headers. A header that imports the Swift target itself is
/// left out: it would import the module being built.
@internal
List<String> swiftUsedHeaders({
  required String plugin,
  required Iterable<String> swift,
  required Map<String, String> headers,
}) {
  final code = swift.map(_withoutComments).join('\n');
  final declaration = RegExp(r'@(?:interface|protocol)\s+(\w+)\b(?!\s*[;,])');
  return [
    for (final MapEntry(key: path, value: text) in headers.entries)
      if (!text.contains('-Swift.h') &&
          !text.contains('@import ${plugin}_swift') &&
          declaration
              .allMatches(_withoutComments(text))
              .map((m) => m.group(1)!)
              .any(
                (name) => RegExp('\\b${RegExp.escape(name)}\\b').hasMatch(code),
              ))
        path,
  ]..sort();
}

/// Drafts a `Package.swift` for [plugin] from [spec]. [files] are the
/// plugin's files relative to the podspec folder (`ios/` or `darwin/`),
/// with `/` separators; they decide the language split. The staged package
/// root is that folder (feature 006), so paths are relative to it. [read]
/// gives a file's text by that path (null when unreadable); without it the
/// draft cannot see which Objective-C classes the Swift code uses.
@internal
PackageSwiftDraft draftPackageSwift({
  required String plugin,
  required Podspec spec,
  required List<String> files,
  String? pluginVersion,
  Map<String, String> defines = const {},
  String? Function(String path)? read,
}) {
  final notes = <String>[];
  final targetPath = _commonDirectory(spec.sourceFiles);
  final inTarget = [
    for (final file in files)
      if (targetPath == '.')
        file
      else if (file.startsWith('$targetPath/'))
        file.substring(targetPath.length + 1),
  ];
  final swift = inTarget.where((f) => f.endsWith('.swift')).toList();
  final native = inTarget
      .where((f) => RegExp(r'\.(m|mm|c|cc|cpp)$').hasMatch(f))
      .toList();
  final headers = inTarget.where((f) => f.endsWith('.h')).toList();
  final headerDirectory = _commonDirectory(spec.publicHeaderFiles);
  final publicHeaders =
      spec.publicHeaderFiles.isNotEmpty &&
          headerDirectory != '.' &&
          (targetPath == '.' || headerDirectory.startsWith('$targetPath/'))
      ? (targetPath == '.'
            ? headerDirectory
            : headerDirectory.substring(targetPath.length + 1))
      : '.';
  if (swift.isEmpty && native.isEmpty) {
    notes.add(
      'No Swift or Objective-C sources were found under "$targetPath"; '
      'check the target path.',
    );
  }

  final dependencyLines = <String>[
    '.package(name: "FlutterFramework", path: "../FlutterFramework")',
  ];
  final productLines = <String>[
    '.product(name: "FlutterFramework", package: "FlutterFramework")',
  ];
  final todo = <String>[];
  final seenPackages = <String>{};
  final moduleRenames = <String, String>{};
  final flatHeaderModules = <String>{};
  for (final dependency in spec.dependencies) {
    if (dependency.name == 'Flutter') continue;
    final known = swiftPackageFor(dependency.name, dependency.requirement);
    if (known == null) {
      todo.add(
        "// TODO: pod '$dependency' has no known Swift package; add it here.",
      );
      notes.add('Add a Swift package for pod $dependency.');
      continue;
    }
    moduleRenames.addAll(known.objectiveCModules);
    if (known.flatHeaders) flatHeaderModules.add(known.product);
    if (seenPackages.add(known.package)) {
      dependencyLines.add(
        '.package(url: "${known.url}", '
        '${swiftRequirement(dependency.requirement, defaultVersion: known.defaultVersion ?? known.since)})',
      );
    }
    // Two subspecs can be one product (AppsFlyerFramework/Main and /Strict).
    for (final product in [known.product, ...known.extraProducts]) {
      final line = '.product(name: "$product", package: "${known.package}")';
      if (!productLines.contains(line)) productLines.add(line);
    }
  }

  final linker = [
    for (final f in spec.frameworks) '.linkedFramework("$f")',
    for (final f in spec.weakFrameworks) '.linkedFramework("$f")',
    for (final l in spec.libraries) '.linkedLibrary("$l")',
  ];

  final resourceLines = <String>[];
  final resourceCopies = <String, String>{};
  for (final path in [...spec.resourceBundles.values.expand((v) => v)]) {
    if (targetPath == '.' || path.startsWith('$targetPath/')) {
      final relative = targetPath == '.'
          ? path
          : path.substring(targetPath.length + 1);
      resourceLines.add('.process("$relative")');
    } else if (path.endsWith('.xcprivacy') && files.contains(path)) {
      // CocoaPods ships a manifest from anywhere in the pod, but a SwiftPM
      // target only sees its own folder, so without a copy there the app has
      // no manifest (fluttertoast 8.2.14, 2026-11-05).
      final name = path.substring(path.lastIndexOf('/') + 1);
      resourceCopies[path] = '$targetPath/$name';
      resourceLines.add('.process("$name")');
    } else {
      notes.add(
        'Resource "$path" is outside "$targetPath"; copy it into the override '
        'folder under $targetPath/ or drop it (privacy manifests are optional '
        'for development builds).',
      );
    }
  }

  final mixed = swift.isNotEmpty && native.isNotEmpty;
  if (mixed) {
    notes.add(
      'Swift and Objective-C cannot share a SwiftPM target, so the draft '
      'splits them: "$plugin" (Objective-C, the registered plugin class) and '
      '"${plugin}_swift". The Swift classes the Objective-C side uses must '
      'stay public (they usually are).',
    );
  }

  // The Objective-C headers the Swift target reads (see swiftUsedHeaders),
  // relative to the target folder: one directly, several through a header
  // the draft writes.
  String inPodspecFolder(String file) =>
      targetPath == '.' ? file : '$targetPath/$file';
  final usedHeaders = !mixed || read == null
      ? const <String>[]
      : swiftUsedHeaders(
          plugin: plugin,
          swift: [for (final file in swift) ?read(inPodspecFolder(file))],
          headers: {
            for (final file in headers) file: ?read(inPodspecFolder(file)),
          },
        );
  final generatedFiles = <String, String>{};
  String? bridgingHeader;
  if (usedHeaders.length == 1) {
    bridgingHeader = usedHeaders.single;
  } else if (usedHeaders.length > 1) {
    bridgingHeader = '${plugin}_swift-Bridging.h';
    generatedFiles[inPodspecFolder(bridgingHeader)] = [
      '// Generated by `xcross plugin shim`: the Objective-C headers the Swift',
      '// target "${plugin}_swift" uses.',
      for (final header in usedHeaders) '#import "$header"',
      '',
    ].join('\n');
  }
  if (bridgingHeader != null) {
    notes.add(
      "The Swift code uses the plugin's Objective-C classes, so the Swift "
      'target reads ${usedHeaders.join(', ')} (-import-objc-header).',
    );
  }

  final product = plugin.replaceAll('_', '-');
  var platform = spec.deploymentTarget ?? '13.0';
  for (final dependency in spec.dependencies) {
    final minimum = swiftPackageFor(
      dependency.name,
      dependency.requirement,
    )?.minimumIos;
    if (minimum != null) platform = _higherVersion(platform, minimum);
  }
  String list(List<String> items, String indent) =>
      items.map((i) => '$indent$i,').join('\n');

  String block(String label, List<String> items) => [
    '            $label: [',
    list(items, '                '),
    '            ]',
  ].join('\n');

  // CocoaPods puts every header folder of a pod on the search path, so pods
  // `#import "Name.h"` across folders; google_maps_flutter_ios imports
  // "google_maps_flutter_pigeon_messages.g.h" from include/<name>/ ("file
  // not found" under SwiftPM, 2026-11-02). Same for the drafts.
  final headerSearchPaths = {
    for (final header in headers)
      if (header.contains('/')) header.substring(0, header.lastIndexOf('/')),
  }.toList()..sort();

  String target({
    required String name,
    required List<String> dependencies,
    List<String> exclude = const [],
    bool objc = false,
    List<String> swiftSettings = const [],
  }) {
    // No trailing comma after the last argument: Swift accepts that only
    // from 6.1 on. The order is PackageDescription's: `resources` before
    // `publicHeadersPath`, or the manifest fails with "type 'Any' has no
    // member 'target'" (google_maps_flutter_ios, 2026-11-02).
    final arguments = <String>[
      '            name: "$name"',
      block('dependencies', dependencies),
      '            path: "$targetPath"',
      if (exclude.isNotEmpty)
        block('exclude', [for (final e in exclude) '"$e"']),
      if (resourceLines.isNotEmpty && name == plugin)
        block('resources', resourceLines),
      if (objc && headers.isNotEmpty)
        '            publicHeadersPath: "$publicHeaders"',
      // The macros are the plugin's own switches (permission_handler's
      // PERMISSION_CAMERA): without them an Objective-C plugin built from a
      // podspec compiles its permissions out (studio: 027).
      if (objc &&
          (headerSearchPaths.isNotEmpty ||
              (name == plugin && defines.isNotEmpty)))
        block('cSettings', [
          for (final dir in headerSearchPaths) '.headerSearchPath("$dir")',
          if (name == plugin)
            for (final MapEntry(:key, :value) in defines.entries)
              '.define("$key", to: "$value")',
        ]),
      if (swiftSettings.isNotEmpty) block('swiftSettings', swiftSettings),
      if (linker.isNotEmpty && name == plugin) block('linkerSettings', linker),
    ];
    return ['        .target(', arguments.join(',\n'), '        ),'].join('\n');
  }

  final generatedHeader = generatedFiles.isEmpty ? null : bridgingHeader;
  final targets = mixed
      ? [
          target(
            name: '${plugin}_swift',
            dependencies: productLines,
            exclude: [
              ...native,
              ...headers,
              ?generatedHeader,
              // Declared by the Objective-C target, in this same folder.
              for (final copy in resourceCopies.values)
                copy.substring(targetPath.length + 1),
            ],
            swiftSettings: [
              if (bridgingHeader != null)
                [
                  '.unsafeFlags([',
                  '                    "-import-objc-header",',
                  '                    packageDirectory + "/${inPodspecFolder(bridgingHeader)}",',
                  '                ])',
                ].join('\n'),
            ],
          ),
          target(
            name: plugin,
            dependencies: [...productLines, '"${plugin}_swift"'],
            exclude: [...swift, ?generatedHeader],
            objc: true,
          ),
        ]
      : [target(name: plugin, dependencies: productLines, objc: swift.isEmpty)];

  final text = StringBuffer()
    ..writeln('// swift-tools-version: 5.9')
    ..writeln(
      '// DRAFT generated by `xcross plugin shim` from $plugin.podspec'
      '${pluginVersion == null ? '' : ' ($plugin $pluginVersion)'}.',
    )
    ..writeln('// Review it before use; see the notes printed by the command.')
    ..writeln('import PackageDescription')
    ..writeln();
  if (bridgingHeader != null) {
    // -import-objc-header needs a path the compiler finds from anywhere.
    text
      ..writeln('// The Swift target reads Objective-C headers of this folder.')
      ..writeln('let packageDirectory = String(')
      ..writeln(
        r'    #filePath[..<#filePath.lastIndex(where: { $0 == "/" || '
        r'$0 == "\\" })!]',
      )
      ..writeln(')')
      ..writeln();
  }
  text
    ..writeln('let package = Package(')
    ..writeln('    name: "$plugin",')
    ..writeln('    platforms: [.iOS("$platform")],')
    ..writeln(
      '    products: [.library(name: "$product", targets: ["$plugin"])],',
    )
    ..writeln('    dependencies: [')
    ..writeln(list(dependencyLines, '        '));
  for (final line in todo) {
    text.writeln('        $line');
  }
  text
    ..writeln('    ],')
    ..writeln('    targets: [')
    ..writeln(targets.join('\n'))
    ..writeln('    ]')
    ..writeln(')');
  return PackageSwiftDraft(
    text.toString(),
    notes,
    objcSources: [
      for (final file in [...native, ...headers])
        if (targetPath == '.') file else '$targetPath/$file',
    ],
    swiftSources: [
      for (final file in swift)
        if (targetPath == '.') file else '$targetPath/$file',
    ],
    splitsSwift: mixed,
    moduleRenames: moduleRenames,
    flatHeaderModules: flatHeaderModules,
    resourceCopies: resourceCopies,
    generatedFiles: generatedFiles,
  );
}

/// The directory every pattern starts with (`Classes/**/*` → `Classes`),
/// or `.` when they share none.
String _commonDirectory(List<String> patterns) {
  if (patterns.isEmpty) return 'Classes';
  List<String> fixed(String pattern) {
    final parts = pattern.replaceAll(r'\', '/').split('/');
    final out = <String>[];
    for (final part in parts.take(parts.length - 1)) {
      if (RegExp(r'[*?{\[]').hasMatch(part)) break;
      out.add(part);
    }
    return out;
  }

  var common = fixed(patterns.first);
  for (final pattern in patterns.skip(1)) {
    final next = fixed(pattern);
    var i = 0;
    while (i < common.length && i < next.length && common[i] == next[i]) {
      i++;
    }
    common = common.take(i).toList();
  }
  return common.isEmpty ? '.' : common.join('/');
}
