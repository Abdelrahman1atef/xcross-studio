# Feature Specification: App Store build and release check

**Feature Branch**: `018-app-store-build` (work lands on `008-json-events-gui`) | **Created**: 2026-11-03 |
**Status**: Draft

**Input**: handoff plan `specs/HANDOFF-2026-11-03.md`, feature 018 (US-IOS-001 AC-03, AC-04, AC-05, AC-06, AC-07,
AC-09, AC-11). xcross can build and development-sign an IPA, but cannot sign for App Store distribution, write an
`.xcarchive`, or tell before an upload what Apple will reject. This feature adds `--export-method app-store` (Apple
Distribution certificate, App Store profiles, production entitlements, archive with dSYMs) and `xcross release
check`, which runs the local checks of the story's validation step with coded issues.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A signed App Store IPA and archive from Windows/Linux (Priority: P1)

**Acceptance Scenarios**:

1. **AC-018-1**: `xcross flutter build --release --ipa --export-method app-store` (signed in with an App Store
   Connect team key) signs the app and every extension for distribution and writes
   `build/xcross-ios/ipa/<name>.ipa` and `build/xcross-ios/archive/Runner.xcarchive` (`Info.plist` with
   `ApplicationProperties`, `Products/Applications/<app>.app`, `dSYMs/`). `--export-method` requires `--release`;
   `development` (the default) keeps today's unsigned IPA.
2. **AC-018-2**: The Apple Distribution certificate is reused across runs: the key in `XCROSS_CERTIFICATE_PRIVATE_KEY`
   (PEM) when set, else the one saved under the signing identity; a team certificate whose public key matches is
   reused, otherwise one is created from that key. Apple's certificate limit is reported (no certificate is ever
   revoked). Each bundle gets a new `IOS_APP_STORE` profile named `xcross App Store <time>`; only earlier profiles
   with that prefix are deleted. The App ID is always the real bundle ID.
3. **AC-018-3**: The signed app carries production entitlements: `aps-environment` from the profile (`production`),
   no `get-task-allow`, `beta-reports-active` as the profile grants it. Capabilities follow the entitlements with the
   016 rules (truthful, never fatal).
4. **AC-018-4**: A team key without provisioning rights, or an Apple ID sign-in, stops the export with a clear
   message naming the role needed (Admin or App Manager team key). No saved key or an individual key stops
   `flutter build --export-method app-store` before it compiles. `xcross flutter doctor` reports "App Store
   signing" under Deployment: a warning without a saved team key or with an individual key, success with a team key
   (Apple checks its role when the build signs).
5. **AC-018-5**: dSYMs: `dsymutil` (from `PATH`, LLVM or the Swift toolchain) runs on `Runner` and `App.framework/App`
   into the archive's `dSYMs/`; without one the build warns `release.dsym_unavailable` and continues. Dart symbols
   from `--split-debug-info` stay where Flutter writes them and are listed in the archive `Info.plist`.

### User Story 2 - Toolchain identity Apple expects (Priority: P1)

1. **AC-018-6**: Every built app's `Info.plist` has `DTPlatformName`, `DTPlatformVersion`, `DTSDKName`,
   `DTSDKBuild`, `DTPlatformBuild` (from the SDK's `SystemVersion.plist`), `DTCompiler`, and `DTXcode` /
   `DTXcodeBuild` from the Xcode the SDK came from (`xcross sdk install` records `Contents/version.plist` from the
   `.xip`; for an SDK installed before, `DTXcode` is derived from the SDK version and `DTXcodeBuild` is left out with
   a `release check` warning).
2. **AC-018-7**: `xcross flutter doctor` fails the Darwin SDK check when the iOS SDK is older than 26 (App Store
   Connect's minimum since April 2026) and says to install an Xcode 26+ `.xip`.
3. **AC-018-8**: `ITSAppUsesNonExemptEncryption` is written from `uses_non_exempt_encryption: true|false` in the
   project settings (`xcross:` in `pubspec.yaml`); `release check` warns when it is not set.

### User Story 3 - `xcross release check` (Priority: P1)

`xcross release check [<ipa|app>] [--json]` (default: the newest IPA under `build/xcross-ios/`) prints the app's
configuration and coded issues (errors first), exits 1 when there is an error.

1. **AC-018-9** (signing): `release.not_signed`, `release.profile_not_app_store`, `release.profile_expired`,
   `release.get_task_allow`, `release.aps_development`, `release.extension_profile`.
2. **AC-018-10** (toolchain and identity): `release.sdk_too_old` (`LC_BUILD_VERSION` sdk or `DTPlatformVersion`
   below 26), `release.dt_keys_missing`, `release.deployment_target`, `release.version_invalid`,
   `release.bundle_id_mismatch` (signed ID differs from the project's).
3. **AC-018-11** (permissions, AC-05): `release.permission_missing` (a plugin that needs a usage description
   without it, from a plugin → key table), `release.permission_placeholder` (empty, short or "TODO"),
   `release.ats_arbitrary_loads`, background modes listed with the plugin that explains them.
4. **AC-018-12** (privacy, AC-06): `release.privacy_manifest_missing` (no app `PrivacyInfo.xcprivacy`; a bundled SDK
   from Apple's list without one; for a plugin in `xcross_overrides/`, the hint asks for a new draft with
   `xcross plugin shim <plugin> --force`, otherwise for an update), `release.required_reason_undeclared` (a
   required-reason API category used by a
   binary but declared in no manifest), `release.encryption_unset`, `release.secret_in_bundle` (private keys or AWS
   keys in bundle files).
5. **AC-018-13** (store assets, AC-07): `release.marketing_icon` (no 1024 px icon in the app icon set, or one with an
   alpha channel), `release.launch_screen_missing`, `release.ipad_multitasking` (iPad support without all four
   orientations or `UIRequiresFullScreen`).
6. **AC-018-14**: `--json` prints one `{"v":1,"type":"release_check", …}` object (configuration, issues with code,
   severity, message, path, hint).
7. **AC-018-15** (device/store evidence, `device-check.md`): app A exported with a team key passes `release check`
   without errors (the upload itself is feature 019).
8. **AC-018-16** (SwiftSupport, App Store Connect 90426): an App Store IPA whose binaries load Swift runtime libraries
   (`libswift*.dylib`) carries them in `SwiftSupport/iphoneos/` at its root, and in the archive. The build takes them
   from the installed SDK, which keeps `usr/lib/swift-5.0/iphoneos`, `swift-5.5/iphoneos` and `swift-6.2/iphoneos` of
   Xcode's toolchain (first folder wins; the libraries' own Swift dependencies come too). A library loaded through
   `@rpath` that the SDK lacks stops the build before signing and says to run `xcross sdk install` again.
   `release check` reports `release.swift_support_missing` (error) when an `.ipa` loads Swift libraries and has no
   SwiftSupport, or lacks an `@rpath` one.
9. **AC-018-17** (purpose strings from the code, 90683): `release check` reads every binary for calls Apple has warned
   about and reports `release.permission_missing_for_call` (warning) when Info.plist lacks the keys: today
   `requestAlwaysAuthorization` (`NSLocationAlwaysAndWhenInUseUsageDescription` and `NSLocationWhenInUse…`) and
   `requestWhenInUseAuthorization`. A rule is added only with an Apple message behind it.
10. **AC-018-18** (`release check --online`, read-only): with the saved key it asks App Store Connect and reports
    `release.asc_no_app` (no record for the bundle ID), `release.asc_build_exists` and `release.asc_build_not_higher`
    (this version's builds), `release.asc_version_closed` (the version, or a lower one, has shipped),
    `release.asc_capability_missing` (warning: an entitlement's capability is off on the App ID) and
    `release.asc_unavailable` (warning: no key, refused key or no network; the IPA checks still stand). Only GET requests
    are made. `configuration.online` says whether it was asked; the Studio's step 6 always passes `--online`.

### Edge Cases

- No project folder around the IPA: project-based checks (permissions table, icon source, bundle ID) are skipped
  with an info line.
- A universal (fat) binary: the arm64 slice's `LC_BUILD_VERSION` is used.
- An IPA from another tool: every check still runs on what is inside.

## Requirements *(mandatory)*

- **FR-001**: Distribution signing lives in `apple_developer_kit` (`AscProvisioning.provisionDistributionIdentity`) and
  `xcross` (`AppStoreExport`); the release check in `studio_ext` (`xcross release check`).
- **FR-002**: No certificate is revoked and no profile not created by xcross is deleted.
- **FR-003**: Private keys are written owner-only and never printed.

## Success Criteria *(mandatory)*

- **SC-001**: A developer with a team key gets an App Store IPA and archive from Windows in one command.
- **SC-002**: Every issue in the original story's validation-failure list that can be seen locally is reported by
  `release check` before an upload.

## Assumptions

- App Store signing needs an App Store Connect **team** key with Admin or App Manager role (as the reference
  workflow); Apple ID distribution signing is not part of this feature.
- Apple's server-side validation (ITMS codes) remains the final word; new codes found on uploads are added to the
  story's failure table (feature 019).
