# Implementation Plan: iOS 16 install and launch, and `xcross install`

**Branch**: `005-ios16-install-launch` | **Date**: 2026-11-01 | **Spec**: [spec.md](spec.md)

## Summary

- **Gate**: lower the device gate to iOS 15. iOS 15/16 run a "legacy" path: install over usbmux (already how
  `PymdDevices.install` works with `--udid`), then launch with `mounter mount-developer` + `developer dvt launch`
  when a user-supplied developer disk image is found, else print tap-to-open guidance.
- **Debug builds**: debug runs on legacy devices fail fast before the build.
- **New command**: `xcross install <ipa|app>`, a new composition command reusing `DeviceRunOperation` (precheck →
  sign + install → launch). This is the Sideloadly replacement.

## Technical Context

**Language/Version**: Dart `^3.10.0`

**Primary Dependencies**: existing `xcross` / `dart_mobile_device` / `archive`; pymobiledevice3 (`mounter`,
`developer dvt launch`)

**Testing**: unit tests with fakes (precheck, legacy launcher, DDI locator, install command input handling); real
device rows (iPhone X, iOS 16.7)

**Target Platform**: Windows and Linux hosts; iOS 15+ devices

**Project Type**: CLI

**Constraints**: never download disk images (Principle II); no elevation; iOS 17+ path unchanged

No open clarification items remain.

## Constitution Check

| Principle | Status | Note |
|---|---|---|
| I | ⚠ justified | Upstream PR candidate (#147); new files (`legacy_device_launcher.dart`, `ddi_locator.dart`, `install_command.dart`) plus small marked hunks in the precheck, run operation, run command and runner |
| II | ✅ | only the user's own disk image; `auto-mount` is not used on the legacy path |
| III | ✅ | legacy debug fails before the build; coded errors |
| IV, V | ✅ | CLI; pymobiledevice3 runs on both hosts |
| VI | ✅ | AC → tests; device rows |
| VII | ✅ | reuses `DeviceRunOperation`, `NativeBackend` signing, `PymdDevices.install` |
| VIII | ✅ | no new credential handling |

## Project Structure

```text
packages/xcross/lib/src/target/iphone/device/
├── ddi_locator.dart              # NEW: --ddi / XCROSS_DDI_DIR / ~/.xcross/DeviceSupport
├── legacy_device_launcher.dart   # NEW: mount-developer + dvt launch, or tap guidance
├── device_precheck.dart          # minimum iOS 15 (studio: 005)
└── device_run_operation.dart     # legacy branch after install (studio: 005)
packages/xcross/lib/src/composition/cli/
├── install_command.dart          # NEW: xcross install <ipa|app>
├── flutter_run_command.dart      # legacy debug fail-fast, --ddi (studio: 005)
└── runner.dart                   # register install (studio: 005)
```

## AC → tests

| AC | Test |
|---|---|
| AC-005-1, 4 | `xcross/test/device/legacy_run_test.dart` (precheck accepts 16; legacy debug fail-fast) |
| AC-005-2, 3 | `legacy_device_launcher_test.dart` (mount + launch commands; already mounted; no image → guidance) and `ddi_locator_test.dart` |
| AC-005-5, 6 | `xcross/test/cli/install_command_test.dart` (IPA extraction, input errors) |
| SC-001, SC-002 | `device-check.md` |
