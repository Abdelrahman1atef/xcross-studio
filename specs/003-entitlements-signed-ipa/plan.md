# Plan: Apply the app's entitlements when signing

**Branch**: `003-entitlements-signed-ipa` | **Spec**: [spec.md](spec.md)

## Summary

A new `FlutterAppEntitlements` helper (`X/shared/flutter/build/flutter_app_entitlements.dart`):

- finds the entitlements file (`runtime.extensions.applicationEntitlements`, else `ios/Runner/Runner.entitlements`)
- parses it with `propertylistserialization`
- returns `{XCrossEntitlements: declared, XCrossCapabilities: AscCapabilities.forEntitlements(declared)}`

`FlutterBundleAssembler._writeInfoPlist` merges these into the final Info.plist (one marked hunk). The existing signing
pipeline (`NativeBackend` → `AscProvisioning`, `BundleSigner`, `SignedBundlePreparer` stripping) does the rest.

## Constitution Check

| Principle | Status |
|---|---|
| I | ✅ one new file plus a small assembler hunk; upstream candidate (#149) |
| II, IV, V, VIII | ✅ |
| III | ✅ an unreadable file produces a coded warning |
| VI | ✅ unit tests plus the `app info` device row |
| VII | ✅ reuses `AscCapabilities`, `AppEntitlements`, `AppCapabilities` and the signer |

## Tests

| AC | Test |
|---|---|
| AC-003-1, 2, 3 | `XT/flutter/build/flutter_app_entitlements_test.dart`: helper and Info.plist merge |
| AC-003-4 | `device-check.md` |
