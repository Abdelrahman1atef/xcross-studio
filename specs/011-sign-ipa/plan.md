# Implementation Plan: `xcross sign`

**Branch**: `011-sign-ipa` | **Date**: 2026-11-01 | **Spec**: [spec.md](spec.md)

## Summary

- **Seam** (`target/iphone/device/device_backend.dart`, `// studio: 011`): `NativeBackend.install` now delegates to a
  private `_signBundle(…, deviceUdids, installTo)`. A new public `NativeBackend.sign(appPath, bundleId, deviceUdids)`
  runs the same online/offline provisioning and signing with `installTo: null`, so `_signAndInstall` skips only the
  `PymdDevices.install` call. Device ids are now a list: provisioning registers each one (Apple's profile lists every
  device on the team anyway), and the offline path checks that the cached profile covers each one.
- **Command** (`composition/cli/sign_command.dart`): input → `AppBundleInput.prepare` (copy/extract, binary plists to
  XML) → optional `--bundle-id` → device ids (`--udid` + USB list) → `signApp` → `IpaWriter` → `SignedBundleCheck`
  → summary. `AppleError("No iOS devices are registered…")` becomes `sign.no_device`.
- **Shared input** (`composition/cli/app_bundle_input.dart`): the 005 input code moved out of `InstallCommand`, plus
  plist normalisation, `setBundleId`, `looksEncrypted`. `InstallCommand` gains `--[no-]resign`.
- **studio_ext** (public, fork code): `shared/ipa/ipa_writer.dart` (deterministic zip, Unix modes, made-by patch:
  `package:archive` always writes MS-DOS as the host) and `shared/inspect/signed_bundle_check.dart` (inspector-based
  check + summary).
- **GUI**: "Sign only (.ipa)" button on the Device page (`XcrossCommands.sign`).

## Technical Context

**Language/Version**: Dart `^3.10`; Flutter 3.47 for the GUI button

**Primary Dependencies**: existing `archive`, `propertylistserialization`, `apple_developer_kit` signing, `studio_ext`
inspector. No new dependency.

**Testing**: command tests with a fake signer and fake/real verifier; studio_ext tests with the 001 fixture builder
(certificate-signed bundle with profile, unsigned bundle).

**Constraints**: never touches the user's input; no new Apple account operations beyond what `xcross install` does
(device registration, App ID, development certificate and profile).

## Constitution Check

| Principle | Status | Note |
|---|---|---|
| I | ⚠ justified | marked hunks in `device_backend.dart`, `runner.dart`, `xcross_diagnostics.dart`; new files elsewhere; upstream candidate for #146 |
| II | ✅ | nothing from Apple is downloaded or shipped |
| III | ✅ | `sign.*` codes with hints; verification before success |
| IV, V | ✅ | CLI + GUI button; pure Dart, both hosts |
| VI | ✅ | AC → tests below; device rows in `device-check.md` |
| VIII | ✅ | summary prints no UDIDs or certificate names |

## AC → tests

| AC | Test |
|---|---|
| AC-011-1 | `xcross/test/cli/sign_command_test.dart` `AC-011-1 …`; `apps/studio/test/cli/cli_test.dart` `AC-011-1 …` |
| AC-011-2 | `sign_command_test.dart` `AC-011-2 …` (two tests) |
| AC-011-3 | `studio_ext/test/shared/sign/signed_ipa_test.dart` `AC-011-3 …` (layout, modes, determinism) |
| AC-011-4 | `signed_ipa_test.dart` `AC-011-4 …`; `sign_command_test.dart` `AC-011-4 …` (real inspector) |
| AC-011-5 | `sign_command_test.dart` `AC-011-5 …` |
| AC-011-6 | `xcross/test/cli/install_command_test.dart` `AC-011-6 …` |
| AC-011-7 | `sign_command_test.dart` `AC-011-7 …` |
| AC-011-8 | `sign_command_test.dart` `AC-011-8 …` |
| AC-011-9 | `device-check.md` |
