# Implementation Plan: App Store build and release check

**Branch**: `018-app-store-build` (on `008-json-events-gui`) | **Date**: 2026-11-03 | **Spec**: [spec.md](spec.md)

## Summary

K = `packages/apple_developer_kit/lib`, X = `packages/xcross/lib/src`, S = `packages/studio_ext/lib`.

- **K** `shared/appstoreconnect/asc_client.dart`: `AscClient.listCertificates(types)`, `createCertificate(type,
  csr)`, `createAppStoreProfile(name, bundleId, certificateIds)` (interface `DistributionProvisioningClient`, only the
  API-key client). `appstoreconnect.dart`: `provisionDistributionIdentity` (key from PEM or saved, matching team
  certificate by public key or new from CSR, capabilities via the 016 code, xcross-prefixed App Store profiles only).
- **X** `target/iphone/device/app_store_export.dart` (new): team-key session (`AscCredentialsLoader` + `AscClient`),
  real bundle ID, extensions renamed under it, provisioning per bundle, `SigningAssetLoader` + `BundleSigner`, then
  `IpaPackager` into `build/xcross-ios/ipa/`, the archive writer (`.xcarchive` + dSYMs through `dsymutil`).
  `composition/cli/flutter_build_command.dart`: `--export-method development|app-store` (`// studio: 018`).
- **X** DT keys: `shared/sdk/xcode_build_info.dart` (new) reads `SystemVersion.plist` of the iOS SDK and
  `xcross-xcode-version.plist` recorded by `sdk install` (`sdk_archive_extraction.dart` seam);
  `target/shared/flutter/ios_plist_metadata.dart` writes the keys. Export compliance from project settings in the
  assembler.
- **X** doctor: Darwin SDK version below 26 is a failure (`doctor_environment_checks.dart` seam).
- **S** `shared/release/release_check_command.dart` + `src/shared/release/release_checks.dart` (new): runs on
  `InspectSource` + `BundleInspector` (feature 001) plus project files; `src/shared/release/macho_build_version.dart`
  reads `LC_BUILD_VERSION`; tables for plugin permissions, required-reason symbols and SDKs needing manifests.

## Technical Context

Dart 3 · existing deps (`basic_utils` for RSA/CSR, `archive`, `propertylistserialization`) · tests: fake ASC client,
fixture `.app` directories · Windows/Linux.

## Constitution Check

I new files + seams · II SDK version data comes from the user's own `.xip` · III every check coded, export failures
explain the role · IV CLI only · V `dsymutil` located through PATH/toolchain, no OS branch · VI AC-named tests ·
VII no new dependency · VIII private keys owner-only via `SecureFile`, never logged. No violations.

## Tests

`packages/apple_developer_kit/test/appstoreconnect/distribution_test.dart` (AC-018-2, 4),
`packages/xcross/test/flutter/build/app_store_export_test.dart` (AC-018-1, 3, 5),
`packages/xcross/test/flutter/build/xcode_build_info_test.dart` (AC-018-6, 8),
`packages/studio_ext/test/shared/release/release_check_test.dart` (AC-018-9…14).
