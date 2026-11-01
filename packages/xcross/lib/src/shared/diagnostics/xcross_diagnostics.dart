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
        'or an override (feature 006).',
  );
  static const buildPluginManifestMissing = DiagnosticCode(
    'build.plugin_manifest_missing',
    "Check the plugin's ios/ or darwin/ folder; its platform channels will "
        'not respond at runtime.',
  );
  static const buildAssetCatalogSkipped = DiagnosticCode(
    'build.asset_catalog_skipped',
    'Asset catalogs are not compiled yet (feature 004); add loose PNGs plus '
        'CFBundleIcons for the app icon meanwhile.',
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
  static const buildResourceMissing = DiagnosticCode(
    'build.resource_missing',
    'Remove the stale reference from the Xcode project or restore the file.',
  );

  static const all = [
    deviceIosUnsupported,
    deviceNotFound,
    deviceHostServiceUnavailable,
    deviceQueryTimeout,
    deviceLegacyDebugUnsupported,
    installUnsupportedInput,
    installNoApp,
    toolchainPathLinkerUnusable,
    buildPodspecOnlyPlugin,
    buildPluginManifestMissing,
    buildAssetCatalogSkipped,
    buildStoryboardSkipped,
    buildResourceMissing,
    buildEntitlementsUnreadable,
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
