# Tasks: Firebase, push and Maps work on the device

X = `packages/xcross/lib/src`, XT = `packages/xcross/test`, K = `packages/apple_developer_kit/lib`,
KT = `packages/apple_developer_kit/test`, G = `apps/studio/lib`, GT = `apps/studio/test`.
Tests are part of every story (Constitution VI: each AC maps to a test named with its id).

## Phase 1: Setup

- [X] T001 Add codes `build.push_entitlement_inferred`, `build.maps_key_unresolved`,
  `sign.capability_not_enabled` (hints from contracts/cli.md) to `X/shared/diagnostics/xcross_diagnostics.dart`
  and `XcrossCodes.all`.

## Phase 2: Foundational

- [X] T002 Normalize the kept outside edit `X/shared/flutter/build/project_runner.dart` and
  `XT/flutter/build/project_runner_test.dart` to LF line endings without changing their content.

## Phase 3: User Story 1 — real App ID (P1)

Independent test: a non-interactive first build registers and signs the real ID; the command switches the saved
choice.

- [X] T003 [US1] `X/target/iphone/device/internal/bundle_identity_resolver.dart`: order of AC-016-1 (real by
  default, prefixed when only it exists with a note, prompt default `[1]` = real, stronger warning on another
  team's ID, save only an answered question).
- [X] T004 [P] [US1] `X/shared/cli/basic/project_command.dart`: `xcross project bundle-id [original|prefixed]
  [--json]` per contracts/cli.md ("saved"/"override" `null` when absent; exit 64 on an invalid value).
- [X] T005 [US1] Register `ProjectCommand` in `X/composition/cli/runner.dart` (`// studio: 016`); `--json` owns
  stdout like the other JSON commands.
- [X] T006 [P] [US1] Tests: `XT/target/iphone/device/bundle_identity_resolver_test.dart` (AC-016-1) and
  `XT/cli/project_command_test.dart` (AC-016-2).
- [X] T007 [US1] G: `XcrossCommands.projectBundleId`, App ID card with the switch in
  `G/features/signing/signing_page.dart` (AC-016-3); test in `GT/ui/push_app_id_test.dart`.

## Phase 4: User Story 2 — push (P1)

Independent test: an app with `firebase_messaging` and no entitlements file is signed with `aps-environment`.

- [X] T008 [P] [US2] `X/shared/flutter/build/push_entitlement.dart`: `PushSignals.read(projectRoot, plistXml)`
  (plugin list from `.flutter-plugins-dependencies`, else `pubspec.yaml` dependencies; `UIBackgroundModes`) and
  `withInferredPush(declared, signals)`.
- [X] T009 [US2] Seam in `X/shared/flutter/flutter_bundle_assembler.dart` `_withDeclaredEntitlements`: infer, warn
  `build.push_entitlement_inferred` once, keep declared values (`// studio: 016`).
- [X] T010 [US2] `K/shared/appstoreconnect/appstoreconnect.dart` `_ensureCapabilities`: per-capability catch
  (401 rethrown, `CapabilitiesUnsupported` caught), verify with a second list, "Enabled …" only when verified,
  `onCapabilityRefused` callback (default `onProgress`) on `provisionDevelopmentIdentity`.
- [X] T011 [US2] `X/target/iphone/device/device_backend.dart`: pass `onCapabilityRefused` for the app and its
  extensions, formatted as `sign.capability_not_enabled` (`// studio: 016`).
- [X] T012 [P] [US2] `X/shared/flutter/project/push_readiness.dart`: `applies` and `checks()` (`Push entitlement`,
  `Push App ID`, `Firebase config`); section in `X/composition/cli/doctor_sections.dart` (`// studio: 016`).
- [X] T013 [US2] G: `ReadinessArea.push` in `G/src/state/readiness.dart` and an Overview card shown only when push
  checks exist (`G/features/overview/overview_page.dart`).
- [X] T014 [P] [US2] Tests: `XT/flutter/build/push_entitlement_test.dart` (AC-016-4),
  `KT/.../provisioning capabilities` (AC-016-5), `XT/flutter/project/push_readiness_test.dart` (AC-016-6),
  `GT/ui/push_app_id_test.dart` (AC-016-7).

## Phase 5: User Story 3 — AppDelegate code and Maps (P1)

Independent test: a project calling `GMSServices.provideAPIKey("…")` gets a generic `Runner.m` that calls
`provideAPIKey:`; `XCROSS_RUNNER` unset on a template app uses the shim.

- [X] T015 [P] [US3] `X/shared/flutter/build/maps_api_key.dart`: `MapsApiKeyLocator.locate(projectRoot)` (Swift and
  Objective-C literal, Info.plist key, `let x = …` indirection; `$(VAR)` through
  `XcconfigResolver.readDebugConfigurationSync`).
- [X] T016 [US3] `X/shared/flutter/build/runner_shim.dart`: `mapsApiKey` parameter → `XcrossProvideMapsKey()` before
  `super`; escape the literal; `X/shared/flutter/flutter_artifact_linker.dart` locates the key, logs its source
  (never the key), warns `build.maps_key_unresolved` (`// studio: 016`).
- [X] T017 [US3] `X/shared/flutter/build/project_runner_sources.dart`: `RunnerMode.auto` default,
  `appDelegateHasCustomCode`; `X/shared/flutter/build/project_runner.dart`: `auto` decision and status line.
- [X] T018 [US3] `X/shared/flutter/build/project_runner.dart`: module maps of `<products>/*.build/module.modulemap`
  and umbrella include folders for swiftc (`-Xcc`) and clang.
- [X] T019 [P] [US3] Tests: `XT/flutter/build/maps_api_key_test.dart` (AC-016-8), runner shim source in
  `XT/flutter/build/runner_shim_test.dart` (AC-016-8), `XT/flutter/build/project_runner_test.dart` (AC-016-9,
  AC-016-10).

## Phase 6: User Story 4 — device evidence (P2)

- [X] T020 [US4] Rebuild the CLI (`dart run tool/build_xcross.dart`), switch app A to the real ID, build and run app A
  and app B on the iPhone X, capture logs; record rows in `specs/016-push-firebase-maps/device-check.md`
  (AC-016-11). Rows that need a tap on the iPhone or a backend push stay ⏳ in device-check.md.

## Phase 7: Polish

- [X] T021 `dart analyze --fatal-warnings` (xcross, apple_developer_kit, studio_ext), repo analyzer, `dart test`
  for touched suites, `flutter analyze` + `flutter test` (GUI).
- [X] T022 Docs: CHANGELOG, `docs/release/US-IOS-001-xcross.md` (status lines for AC-01, AC-08), runbook note.

## Dependencies

T001 → T009, T011, T016. T002 → T018. US1, US2 and US3 are independent of each other; US4 needs all three.
Parallel: T004/T006, T008/T012/T014, T015/T019.

## Implementation strategy

MVP = US1 + US2 (push and Firebase depend on the real ID); US3 next; then the device run.
