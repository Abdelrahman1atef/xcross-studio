// studio: 002 — coded diagnostics (specs/002-quick-wins/contracts/diagnostics.md).
import 'package:meta/meta.dart';
import 'package:xcross/src/shared/errors/errors.dart';

/// A stable, user-facing diagnostic code with its default fix hint.
///
/// Codes are dotted (`device.*`, `toolchain.*`, `build.*`) and are never
/// renamed once released.
@internal
final class DiagnosticCode {
  const DiagnosticCode(this.code, this.hint);

  final String code;
  final String hint;
}

/// Every code introduced by feature 002, with the hints from the contract.
@internal
abstract final class XcrossCodes {
  static const deviceIosUnsupported = DiagnosticCode(
    'device.ios_unsupported',
    'Use a device on iOS 15 or later (iOS 15/16 install and open from the '
        'icon; iOS 17+ also supports hot reload).',
  );
  // studio: 005
  static const deviceLegacyDebugUnsupported = DiagnosticCode(
    'device.legacy_debug_unsupported',
    'Run with --release or --profile on iOS 15/16; debug (hot reload) builds '
        'need a debugger, which xcross supports on iOS 17 or later.',
  );
  static const installUnsupportedInput = DiagnosticCode(
    'install.unsupported_input',
    'Pass an .ipa file or a .app bundle directory.',
  );
  static const installNoApp = DiagnosticCode(
    'install.no_app',
    'The IPA must contain exactly one app under Payload/.',
  );
  // studio: 011 — xcross sign
  static const signOutputInvalid = DiagnosticCode(
    'sign.output_invalid',
    'Pass -o <file>.ipa, a path that is not the input file.',
  );
  static const signNoDevice = DiagnosticCode(
    'sign.no_device',
    'Connect the iPhone by USB (or pass --udid <id>) once, so it is '
        'registered on your team; the profile then covers it.',
  );
  static const signVerifyFailed = DiagnosticCode(
    'sign.verify_failed',
    'Run xcross inspect on the input and report the problem with its output.',
  );
  static const signEncryptedApp = DiagnosticCode(
    'sign.encrypted_app',
    'App Store downloads are encrypted for one Apple ID; re-signed they '
        'install but do not start. Use a decrypted or self-built IPA.',
  );
  static const deviceNotFound = DiagnosticCode(
    'device.not_found',
    'Connect the iPhone with a cable, unlock it and tap Trust, then retry '
        '(or pass --wifi for a paired wireless device).',
  );

  /// The hint is host-specific and is supplied by the device host policy.
  static const deviceHostServiceUnavailable = DiagnosticCode(
    'device.host_service_unavailable',
    'Start the host device service, then retry.',
  );
  static const deviceQueryTimeout = DiagnosticCode(
    'device.query_timeout',
    'Unplug and reconnect the iPhone, unlock it, and retry. If it keeps '
        'happening, restart the device service.',
  );
  static const toolchainPathLinkerUnusable = DiagnosticCode(
    'toolchain.path_linker_unusable',
    'Remove this directory from environment.PATH in your xcross '
        'configuration (xcross config); xcross picks an iOS-capable linker by '
        'itself.',
  );
  static const buildPodspecOnlyPlugin = DiagnosticCode(
    'build.podspec_only_plugin',
    'Use a plugin version that ships Package.swift (Swift Package Manager), '
        // studio: 006
        'or add your own: xcross_overrides/<plugin>/Package.swift in the '
        'project (see "Plugin overrides" in the README).',
  );
  static const buildPluginManifestMissing = DiagnosticCode(
    'build.plugin_manifest_missing',
    "Check the plugin's ios/ or darwin/ folder; its platform channels will "
        'not respond at runtime.',
  );
  // studio: 004 — catalogs are compiled now; this is the failure fallback.
  static const buildAssetCatalogSkipped = DiagnosticCode(
    'build.asset_catalog_skipped',
    'The catalog could not be compiled (see the message); fix or remove the '
        'asset it names. Loose PNGs plus CFBundleIcons in Info.plist still '
        'give the app an icon.',
  );
  static const buildAssetUnsupported = DiagnosticCode(
    'build.asset_unsupported',
    'Use PNG (or JPEG) images at 1x/2x/3x, colour sets with explicit '
        'components, and one app icon set; other asset types are left out.',
  );
  static const buildAssetInvalid = DiagnosticCode(
    'build.asset_invalid',
    'Fix the file or its Contents.json entry (open the catalog in an editor '
        'or re-export the image); the rest of the catalog is compiled.',
  );
  static const buildLaunchScreenApproximated = DiagnosticCode(
    'build.launch_screen_approximated',
    'Without Xcode the launch storyboard becomes a UILaunchScreen: one '
        'background colour and one centred image from the asset catalog. '
        'Move the rest into the first Flutter frame.',
  );
  static const buildLaunchScreenUnreadable = DiagnosticCode(
    'build.launch_screen_unreadable',
    'Fix the storyboard XML, or add a UILaunchScreen dictionary to '
        'Info.plist yourself; the app starts with a blank launch screen.',
  );
  static const buildStoryboardSkipped = DiagnosticCode(
    'build.storyboard_skipped',
    'Storyboards cannot be compiled without Xcode; use a UILaunchScreen '
        'dictionary in Info.plist instead.',
  );
  // studio: 003
  static const buildEntitlementsUnreadable = DiagnosticCode(
    'build.entitlements_unreadable',
    'Fix the .entitlements file (it must be an XML property list '
        'dictionary); until then push and associated domains are not applied.',
  );
  // studio: 006
  static const buildPluginOverrideApplied = DiagnosticCode(
    'build.plugin_override_applied',
    'Review the override when you upgrade the plugin; delete the folder to '
        "build the plugin's own package.",
  );
  static const buildPluginOverrideInvalid = DiagnosticCode(
    'build.plugin_override_invalid',
    'An override folder needs a Package.swift; an override.yaml may only set '
        'versions: to a pub-style constraint such as ">=1.2.0 <2.0.0".',
  );
  // studio: 007
  static const buildRunnerProjectFailed = DiagnosticCode(
    'build.runner_project_failed',
    // studio: 016 — `auto` is the default now; `shim` opts out.
    'Fix the error in ios/Runner, or set XCROSS_RUNNER=shim to build with the '
        'generic runner on purpose; until then AppDelegate code does not run '
        '(a Google Maps key it passes is still applied).',
  );
  static const buildRunnerLegacyRegistration = DiagnosticCode(
    'build.runner_legacy_registration',
    'Register plugins in didInitializeImplicitFlutterEngine (Flutter UIScene '
        'migration, as in the current app template).',
  );
  static const buildRunnerSceneDelegateReplaced = DiagnosticCode(
    'build.runner_scene_delegate_replaced',
    'Move that code to AppDelegate (or a plugin); without Xcode the window '
        'cannot come from Main.storyboard, so xcross supplies the scene '
        'delegate.',
  );
  static const buildResourceMissing = DiagnosticCode(
    'build.resource_missing',
    'Remove the stale reference from the Xcode project or restore the file.',
  );

  // studio: 014 — a Flutter SDK whose iOS AOT compiler exists for this host.
  static const buildGenSnapshotUnavailable = DiagnosticCode(
    'build.gen_snapshot_unavailable',
    'Run `xcross flutter sdk auto` to install a Flutter version that has an '
        'iOS compiler for this computer, just for xcross (your own Flutter is '
        'not changed).',
  );
  static const toolchainFlutterSdkInstallFailed = DiagnosticCode(
    'toolchain.flutter_sdk_install_failed',
    'Check the internet connection and free disk space, then run the same '
        'command again; a partial download is cleaned up first.',
  );
  static const toolchainFlutterSdkVersionUnavailable = DiagnosticCode(
    'toolchain.flutter_sdk_version_unavailable',
    'Pick a version from `xcross flutter sdk list`, or pass --force to '
        'install it anyway.',
  );
  static const toolchainGitMissing = DiagnosticCode(
    'toolchain.git_missing',
    'Install Git from https://git-scm.com, open a new terminal, and retry.',
  );

  // studio: 016 — push, Maps and capabilities on the device.
  static const buildPushEntitlementInferred = DiagnosticCode(
    'build.push_entitlement_inferred',
    'Add aps-environment to ios/Runner/Runner.entitlements to make it '
        'explicit.',
  );
  static const buildMapsKeyUnresolved = DiagnosticCode(
    'build.maps_key_unresolved',
    'Pass a string literal, or an Info.plist key read with '
        'Bundle.main.object(forInfoDictionaryKey:), to GMSServices.provideAPIKey.',
  );
  // studio: 018
  static const releaseDsymUnavailable = DiagnosticCode(
    'release.dsym_unavailable',
    'Put dsymutil on PATH (it ships with the Swift toolchain and with the full '
        'LLVM release), then build again.',
  );
  static const signCapabilityNotEnabled = DiagnosticCode(
    'sign.capability_not_enabled',
    'Sign in with `xcross auth --apple-id` (or an Admin team key), or switch '
        'it on at developer.apple.com, then build again.',
  );

  static const all = [
    deviceIosUnsupported,
    deviceNotFound,
    deviceHostServiceUnavailable,
    deviceQueryTimeout,
    deviceLegacyDebugUnsupported,
    installUnsupportedInput,
    installNoApp,
    signOutputInvalid, // studio: 011
    signNoDevice,
    signVerifyFailed,
    signEncryptedApp,
    toolchainPathLinkerUnusable,
    buildPodspecOnlyPlugin,
    buildPluginManifestMissing,
    buildAssetCatalogSkipped,
    buildAssetUnsupported,
    buildAssetInvalid,
    buildLaunchScreenApproximated,
    buildLaunchScreenUnreadable,
    buildStoryboardSkipped,
    buildResourceMissing,
    buildEntitlementsUnreadable,
    buildPluginOverrideApplied, // studio: 006
    buildPluginOverrideInvalid,
    buildRunnerProjectFailed, // studio: 007
    buildRunnerLegacyRegistration,
    buildRunnerSceneDelegateReplaced,
    buildGenSnapshotUnavailable, // studio: 014
    toolchainFlutterSdkInstallFailed,
    toolchainFlutterSdkVersionUnavailable,
    toolchainGitMissing,
    buildPushEntitlementInferred, // studio: 016
    buildMapsKeyUnresolved,
    signCapabilityNotEnabled,
    releaseDsymUnavailable, // studio: 018
  ];
}

/// An [XcrossError] printed as `error: [<code>] <message>` plus a hint line.
@internal
XcrossError codedError(DiagnosticCode code, String message, {String? hint}) =>
    XcrossError('[${code.code}] $message\nhint: ${hint ?? code.hint}');

/// Warning text: `[<code>] <message>` plus an indented hint line.
@internal
String codedWarning(DiagnosticCode code, String message, {String? hint}) =>
    '[${code.code}] $message\n  hint: ${hint ?? code.hint}';
