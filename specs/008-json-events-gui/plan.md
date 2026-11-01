# Implementation Plan: XCross Studio desktop GUI (MVP)

**Branch**: `008-json-events-gui` | **Date**: 2026-11-01 | **Spec**: [spec.md](spec.md)

## Summary

- **CLI (studio_ext)**: two new commands. `xcross devices [--json]` (new `DevicesCommand`, backed by
  `DeviceLogBackend.usbDevices()`) and `xcross app list [--json]` (`AppListCommand`). Both become `device` and `app`
  events in the 010 NDJSON contract (additive; `v` stays 1). Seams: `runner.dart` (registration, `_deviceJson`) and
  `bin/xcross.dart` (`XCROSS_OUTPUT_ENCODING=utf-8`).
- **GUI (`apps/studio`)**: a Flutter desktop app for Windows and Linux.
  - `lib/src/cli`: invocation, command builders, NDJSON events, output-line classification, process launcher.
  - `lib/src/host`: `HostPlatform`.
  - `lib/src/state`: `Job`/`JobCenter`, `LogSession`, `Settings`, `ProjectInfo`.
  - `lib/src/ui`: Setup, Project & Build, Device & Install, Device logs, Console.
  - State uses `ChangeNotifier`; no state-management package.

## Technical Context

**Language/Version**: Dart `^3.13` / Flutter 3.47 (stable)

**Primary Dependencies**: Flutter SDK, `file_selector` (flutter.dev), `path`. No xcross package is imported.

**Testing**: `flutter test` (unit tests with a fake process launcher, widget tests). `dart test` covers the CLI
commands, using the fake device backend and the NDJSON schema.

**Target Platform**: Windows 10/11 and Linux (Ubuntu 22.04/24.04) desktops.

**Constraints**: the GUI holds no build logic (Principle IV). The GUI package sits outside the Dart workspace with
its own `pubspec.lock`, so the CLI packages and CI loops are unchanged.

## Constitution Check

| Principle | Status | Note |
|---|---|---|
| I | ✅ | CLI additions in `studio_ext`; two marked seams (`runner.dart`, `bin/xcross.dart`) |
| II | ✅ | the GUI never downloads Apple material; notice on Setup |
| III | ✅ | coded errors surface as issues with their hints |
| IV | ✅ | GUI = thin shell over `xcross … --json` |
| V | ✅ | `HostPlatform` covers Windows and Linux; not yet run on Linux (deferred like the other Linux checks) |
| VI | ✅ | AC → tests below; device rows in `device-check.md` |
| VIII | ✅ | password masked in displayed commands; UDIDs come only from `xcross devices` |

## AC → tests

| AC | Test |
|---|---|
| AC-008-1 | `studio_ext/test/target/iphone/device/picker_commands_test.dart`; `apps/studio/test/ui/app_test.dart` |
| AC-008-2 | `picker_commands_test.dart` |
| AC-008-3 | `apps/studio/test/cli/cli_test.dart` `AC-008-3 NDJSON events` |
| AC-008-4 | `cli_test.dart` `AC-008-4 command lines` |
| AC-008-5 | `cli_test.dart` `AC-008-5 output lines`; `state_test.dart` `AC-008-5 jobs` |
| AC-008-6 | `state_test.dart` `AC-008-6 device log session` |
| AC-008-7 | `app_test.dart` `AC-008-7 …` |
| AC-008-8 | `app_test.dart` `AC-008-8 …` |
| AC-008-9 | `app_test.dart` `AC-008-9 …`; `flutter build windows`; device-check |
