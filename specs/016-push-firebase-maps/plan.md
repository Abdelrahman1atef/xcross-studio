# Implementation Plan: Firebase, push and Maps work on the device

**Branch**: `016-push-firebase-maps` (on `008-json-events-gui`) | **Date**: 2026-11-03 | **Spec**: [spec.md](spec.md)

## Summary

Five small changes in the CLI, one command, and two GUI touches. X = `packages/xcross/lib/src`,
K = `packages/apple_developer_kit/lib`, G = `apps/studio/lib`.

- **App ID (AC-016-1):** `X/target/iphone/device/internal/bundle_identity_resolver.dart`. With no override and no
  saved choice: real ID if the team has it; prefixed if the team has only that (logged note); otherwise register the
  real ID (asked first on a terminal, default `[1]` = real). Another team owning the real ID → prefixed with a
  stronger warning. Only an answered question is saved.
- **`xcross project bundle-id` (AC-016-2):** new `X/shared/cli/basic/project_command.dart` (`ProjectCommand` →
  `bundle-id [original|prefixed] [--json]`), using `ProjectSettings` and `IosBundleId`; registered in
  `X/composition/cli/runner.dart` (`// studio: 016`).
- **Push inference (AC-016-4):** new `X/shared/flutter/build/push_entitlement.dart` (`PushSignals` from
  `.flutter-plugins-dependencies`/`pubspec.yaml` and `UIBackgroundModes`). The assembler's
  `_withDeclaredEntitlements` adds `aps-environment: development` when a signal exists and the key is not declared,
  and warns `build.push_entitlement_inferred`. Capabilities (`PUSH_NOTIFICATIONS`) follow from the existing
  `withSigningKeys`.
- **Truthful capabilities (AC-016-5):** `K/shared/appstoreconnect/appstoreconnect.dart` `_ensureCapabilities`:
  per-capability try/catch (401 rethrown), then a second `listEnabledCapabilities`; "Enabled …" only for verified
  ones; everything else goes to a new `onCapabilityRefused(type, reason)` callback (default: `onProgress`). The
  device backend formats it as the coded warning `sign.capability_not_enabled`.
- **Doctor and GUI push readiness (AC-016-6/7):** new `X/shared/flutter/project/push_readiness.dart`
  (`PushReadiness.checks()`); `doctor_sections.dart` adds the "Push notifications" section when
  `PushReadiness.applies`. GUI `ReadinessArea.push` from check names (`Push entitlement`, `Push App ID`,
  `Firebase config`); Overview card shown only when such checks exist.
- **Maps key (AC-016-8):** new `X/shared/flutter/build/maps_api_key.dart` (`MapsApiKeyLocator`): literal and
  Info.plist forms in Swift and Objective-C, `$(VAR)` resolved with `XcconfigResolver.readDebugConfigurationSync`
  (the same configuration the Info.plist substitution uses). `RunnerShim.runnerObjcSource` gains `mapsApiKey`: a
  `NSClassFromString(@"GMSServices")` + `objc_msgSend` call before `super`. `flutter_artifact_linker.dart` passes
  it (`// studio: 016`).
- **Runner mode (AC-016-9/10):** `RunnerMode.auto` (default) in `project_runner_sources.dart`;
  `ProjectRunnerSources.appDelegateHasCustomCode` (whitespace-free comparison against the Swift and Objective-C
  templates). `ProjectRunner.build()` returns null for `shim`, and for `auto` without custom code.
  `ProjectRunnerBuilder` adds `-Xcc -fmodule-map-file=<products>/<T>.build/module.modulemap` and the umbrella's
  include folder for every SwiftPM C-family target, on top of the kept xcframework search paths.
- **GUI App ID switch (AC-016-3):** G `features/signing/signing_page.dart` card + `XcrossCommands.projectBundleId`.

## Technical Context

**Language/Version**: Dart 3 (CLI packages), Flutter 3.47 (GUI) · **Primary Dependencies**: existing only
(`args`, `yaml_edit`, `propertylistserialization`, `http`) · **Storage**: project `pubspec.yaml` /
`xcross_project.yaml` (`bundle_id`) · **Testing**: `dart test` (xcross, apple_developer_kit), `flutter test` (GUI)
· **Target Platform**: Windows and Linux hosts, iOS 15+ devices · **Project Type**: CLI + desktop GUI ·
**Constraints**: no key or UDID in logs or files; `dart analyze --fatal-warnings` and the repo analyzer clean.

## Constitution Check

| Principle | Status |
|---|---|
| I Minimal diff | New files for the locator, signals, readiness and command; seams marked `// studio: 016` in the resolver, assembler, linker, shim, provisioning, doctor and runner. |
| II No Apple material | Nothing downloaded. |
| III Fail fast | Three new codes: `build.push_entitlement_inferred`, `build.maps_key_unresolved`, `sign.capability_not_enabled`; the doctor flags push blockers before a build. |
| IV CLI is the product | The GUI switch runs `xcross project bundle-id`; readiness comes from doctor events. |
| V Windows = Linux | No OS branching; paths through `p.Context`. |
| VI Test-first | Tests named with AC ids (below); device rows in `device-check.md`. |
| VII Simplicity | No new dependency; regex scans over the two AppDelegate languages only. |
| VIII Credentials | The Maps key goes only into the generated `Runner.m` in the build folder (the app already embeds it); logs name its source. |

Post-design re-check: unchanged, no violations.

## Tests

- `packages/xcross/test/target/iphone/bundle_identity_resolver_test.dart` (extend): AC-016-1.
- `packages/xcross/test/cli/project_command_test.dart`: AC-016-2.
- `packages/xcross/test/flutter/build/push_entitlement_test.dart`: AC-016-4.
- `packages/apple_developer_kit/test/...capabilities` (extend the provisioning test): AC-016-5.
- `packages/xcross/test/flutter/project/push_readiness_test.dart`: AC-016-6.
- `packages/xcross/test/flutter/build/maps_api_key_test.dart` + runner shim source test: AC-016-8.
- `packages/xcross/test/flutter/build/project_runner_test.dart` (extend): AC-016-9, AC-016-10.
- `apps/studio/test/ui/push_app_id_test.dart`: AC-016-3, AC-016-7.

## Project Structure

```text
specs/016-push-firebase-maps/  spec.md plan.md research.md data-model.md contracts/cli.md quickstart.md tasks.md device-check.md
```

## Complexity Tracking

None.
