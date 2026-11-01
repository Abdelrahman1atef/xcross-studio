import 'package:meta/meta.dart';

/// A stable `inspect.*` code with its fix hint.
///
/// The codes and hints are the contract in
/// `specs/001-inspect/contracts/cli.md`; codes are never renamed.
@internal
final class InspectCode {
  const InspectCode(this.code, this.hint);

  /// Stable machine-readable code, e.g. `inspect.no_app`.
  final String code;

  /// One concrete fix for the user.
  final String hint;
}

/// Every fatal and issue code reported by `xcross inspect`.
@internal
abstract final class InspectCodes {
  // Fatal (exit code 1).

  static const inputNotFound = InspectCode(
    'inspect.input_not_found',
    'Check the path; for a build output use build/xcross-ios/<name>.ipa.',
  );
  static const unsupportedInput = InspectCode(
    'inspect.unsupported_input',
    'Pass an .ipa file or a .app bundle directory.',
  );
  static const corruptArchive = InspectCode(
    'inspect.corrupt_archive',
    'Rebuild or re-download the IPA.',
  );
  static const noApp = InspectCode(
    'inspect.no_app',
    'The IPA must contain exactly one app under Payload/.',
  );
  static const multipleApps = InspectCode(
    'inspect.multiple_apps',
    'Repackage with a single app under Payload/.',
  );

  // Issues (reported in issues[], exit code 0).

  static const infoPlistUnreadable = InspectCode(
    'inspect.info_plist_unreadable',
    'Check ios/Runner/Info.plist and rebuild.',
  );
  static const plistUnreadable = InspectCode(
    'inspect.plist_unreadable',
    'Rebuild the framework or extension; its Info.plist is damaged.',
  );
  static const executableMissing = InspectCode(
    'inspect.executable_missing',
    'Rebuild; check that the build did not skip this binary.',
  );
  static const machoInvalid = InspectCode(
    'inspect.macho_invalid',
    'Rebuild; the binary is damaged or not a Mach-O file.',
  );
  static const signatureInvalid = InspectCode(
    'inspect.signature_invalid',
    'Re-sign the app.',
  );
  static const entitlementsUnreadable = InspectCode(
    'inspect.entitlements_unreadable',
    'Re-sign with a valid entitlements file.',
  );
  static const entitlementsDerOnly = InspectCode(
    'inspect.entitlements_der_only',
    'Re-sign with a signer that also writes XML entitlements.',
  );
  static const profileUnreadable = InspectCode(
    'inspect.profile_unreadable',
    'Re-download the provisioning profile and re-sign.',
  );
  static const symlinkSkipped = InspectCode(
    'inspect.symlink_skipped',
    'iOS bundles should not contain symlinks; copy the target instead.',
  );
  static const noIcon = InspectCode(
    'inspect.no_icon',
    'Add an asset catalog icon (feature 004) or loose PNGs plus '
        'CFBundleIcons.',
  );
  static const iconFileMissing = InspectCode(
    'inspect.icon_file_missing',
    'Ship <name>@2x.png and <name>@3x.png in the bundle root.',
  );
  static const noLaunchScreen = InspectCode(
    'inspect.no_launch_screen',
    'Add a UILaunchScreen dictionary (feature 004).',
  );
  static const launchScreenEmpty = InspectCode(
    'inspect.launch_screen_empty',
    'Provide UIImageName/UIColorName from an asset catalog (feature 004).',
  );
  static const launchImageMissing = InspectCode(
    'inspect.launch_image_missing',
    'Add the launch image to the asset catalog.',
  );
  static const launchImageNotInCatalog = InspectCode(
    'inspect.launch_image_not_in_catalog',
    'iOS does not show loose PNGs as a launch image; put it in Assets.car.',
  );
  static const launchStoryboardMissing = InspectCode(
    'inspect.launch_storyboard_missing',
    'Storyboards are not compiled off-Mac; use UILaunchScreen instead.',
  );
  static const xcrossPrivateKeysInSignedBundle = InspectCode(
    'inspect.xcross_private_keys_in_signed_bundle',
    'Re-sign with xcross; these build-time keys should be stripped.',
  );
}
