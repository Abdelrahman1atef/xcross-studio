---

description: "Task list for feature 002-quick-wins"
---

# Tasks: Quick wins — fail fast, correct versions, PATH guard, loud warnings

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/diagnostics.md](contracts/diagnostics.md), [quickstart.md](quickstart.md)

**Tests**: Required (constitution Principle VI). Test names contain the `AC-002-n` ids. Write each story's tests first.

**Organization**:

| Story | Priority | Scope |
|---|---|---|
| US1 | P1 | fail fast on an unusable device (#147) |
| US2 | P2 | versions from pubspec |
| US3 | P3 | PATH guard (#148) |
| US4 | P4 | loud warnings (#145 warning part) |

Paths: X = `packages/xcross/lib/src`, XT = `packages/xcross/test`, DMD = `packages/dart_mobile_device/lib`,
DMDT = `packages/dart_mobile_device/test`.

## Rules for every task

- Mark every edited hunk in an existing upstream file with `// studio: 002`. Put new logic in new files.
- Library code: no `dart:io` acquisition outside `host/**`, no `Platform`/stdio, `@internal` on public declarations
  in `lib/src`, no barrels.
- After each phase, run `dart analyze --fatal-warnings` (repo root) and the touched packages' tests.

## Phase 1: Setup

- [X] T001 Create `X/shared/diagnostics/xcross_diagnostics.dart`:
  - `final class DiagnosticCode { code, hint }`
  - `abstract final class XcrossCodes` with every code and hint from
    [contracts/diagnostics.md](contracts/diagnostics.md): `deviceIosUnsupported`, `deviceNotFound`,
    `deviceHostServiceUnavailable`, `deviceQueryTimeout`, `toolchainPathLinkerUnusable`, `buildPodspecOnlyPlugin`,
    `buildPluginManifestMissing`, `buildAssetCatalogSkipped`, `buildStoryboardSkipped`, `buildResourceMissing`. The
    service hint is passed per call.
  - `XcrossError codedError(DiagnosticCode code, String message, {String? hint})` with the message
    `[<code>] <message>\nhint: <hint>`
  - `String codedWarning(DiagnosticCode code, String message)` with the text `[<code>] <message>\n  hint: <hint>`

  Add unit tests in `XT/diagnostics/xcross_diagnostics_test.dart` (format; codes unique and dotted).

## Phase 2: Foundational

- [X] T002 Create `X/shared/diagnostics/build_warnings.dart`:
  - `final class BuildWarnings(Log log)` with `void warn(DiagnosticCode code, {required String subject,
    required String message})`. It prints via `log.logWarn(codedWarning(...))` only the first time a (code, subject)
    pair is seen, and counts per code.
  - `String? takeSummary()` returns `Build finished with N warning(s): <code> ×n, …` with codes sorted, or null when
    there are none, and resets.

  Tests in `XT/diagnostics/build_warnings_test.dart`: test `AC-002-15 dedupe and summary` (same pair twice → one
  line; summary counts; reset).
- [X] T003 In `X/shared/flutter/flutter_build_runtime.dart`, add `late final BuildWarnings warnings =
  BuildWarnings(runner.log);` and an optional constructor parameter `this.configuredPath = const []`
  (`List<String>`: the configured `environment.PATH` entries).

## Phase 3: User Story 1 — fail fast (P1) 🎯 MVP

**Goal**: an unusable device is rejected before the build, in < 5 s. **Independent test**: the precheck tests and
ordering tests below; device row in `device-check.md`.

### Tests first

- [X] T004 [P] [US1] `DMDT/device_service_probe_test.dart`, test `AC-002-3 service probe`. A local
  `ServerSocket.bind` listener counts as reachable; a closed port, or a missing unix socket path on POSIX, returns a
  hint. It covers `WindowsDeviceHost` (TCP address) and `PosixDeviceHost` (path) with explicit addresses, and the
  `USBMUXD_SOCKET_ADDRESS` forms `host:port` and a path. Skip the unix-socket case on Windows.
- [X] T005 [P] [US1] `DMDT/pymd_devices_os_version_test.dart`: `PymdDevices.parseDevices` reads `ProductVersion`
  into `Device.osVersion` (and null when absent).
- [X] T006 [P] [US1] `XT/device/device_precheck_test.dart`, with fakes for the service probe, resolver and OS
  version:
  - `AC-002-1 iOS 16 is rejected before the build within 5 s` (code `device.ios_unsupported`, device name, version)
  - `AC-002-2 no device → device.not_found`
  - `AC-002-3 USB search with service down → device.host_service_unavailable`; `all` search with service down and no
    device → same code; `all` with a tunnel device → proceeds; Wi-Fi only → probe not called
  - `device.query_timeout` on `PymdTimeoutError`
  - unreadable version → warning and proceed
  - osVersion from the listing is used without calling the OS-version lookup
- [X] T007 [P] [US1] `XT/cli/flutter_run_precheck_order_test.dart`, test `AC-002-4 device is prechecked once before
  the build and reused`. Using `FlutterRunCommand.withSeams` with a precheck seam, record the call order (precheck,
  then pack, then runDevice with the same device). A failing precheck means pack is never called. Do the same for
  `ComposeRunCommand.withSeams` in `XT/cli/compose_run_precheck_order_test.dart`.

### Implementation

- [X] T008 [US1] In `DMD/shared/errors/errors.dart`, add `final class DeviceNotFoundError extends TunnelError` and
  `final class PymdTimeoutError extends TunnelError` (`// studio: 002`). Throw `PymdTimeoutError` in
  `DMD/target/iphone/device/pymd/pymd.dart` `_runWithTimeout`. Throw `DeviceNotFoundError` in
  `DMD/target/iphone/device/pymd/pymd_device_resolver.dart` for "No connected device matching" and the non-wireless
  "No devices connected" cases.
- [X] T009 [US1] Add `final String? osVersion` (optional constructor parameter) to `Device` in
  `DMD/shared/device/models/device.dart`. Set it from `ProductVersion` in `PymdDevices.parseDevices`, and pass
  `timeout: const Duration(seconds: 20)` to the `usbmux list` call in `PymdDevices.devices`.
- [X] T010 [US1] Add `Future<String?> deviceServiceProblem(String? usbmuxAddress)` to `DeviceHostPolicy`:
  - **Windows** (`WindowsDeviceHost`): TCP connect with a 2 s timeout, default `127.0.0.1:27015`, else the parsed
    `host:port`. Return the Windows hint from the contract on failure.
  - **POSIX** (`PosixDeviceHost`): unix socket connect, default `/var/run/usbmuxd`, else the given path or
    `host:port`. Return the Linux hint on failure.
  - Update the two test implementers in `DMDT/device_roles_test.dart` and `DMDT/wireless_device_preparation_test.dart`.
- [X] T011 [US1] Create `X/target/iphone/device/device_precheck.dart`:
  - `final class PrecheckedDevice { Device device; int? osMajor }`
  - `final class DevicePrecheck({required Log log, required Future<String?> Function() serviceProblem,
    required Future<Device> Function({String? selector, required DeviceSearchMode mode}) resolveDevice,
    required Future<int?> Function(Device) osMajor, int minimumIos = 17})` with
    `Future<PrecheckedDevice> run({String? selector, required DeviceSearchMode mode})`
  - Apply the rules in [data-model.md](data-model.md) and throw `codedError` with the contract codes. The OS version
    comes from the major part of `device.osVersion`, else `osMajor(device)`.
- [X] T012 [US1] In `X/target/iphone/device/device_run_operation.dart`:
  - add `Future<PrecheckedDevice> precheck({String? selector, required DeviceSearchMode mode})`, built from
    `backend.resolveDevice`, the existing `_osMajorVersion` and a service-problem function passed through `resolve(...)`
    (`pymd.hostPolicy.deviceServiceProblem(pymd.resolvedUsbmuxAddress())`)
  - add an optional `PrecheckedDevice? prechecked` to `run(...)`: when it is given, skip resolution and the gate
  - keep the old in-`run` gate for callers without a precheck
- [X] T013 [US1] In `X/composition/cli/flutter_run_command.dart`:
  - add a typedef `FlutterRunPrecheck = Future<PrecheckedDevice?> Function({String? selector,
    required DeviceSearchMode mode})`
  - add an optional `precheck` parameter to `withSeams`; the default precheck is skipped when a `runDevice` seam is
    given without a precheck seam
  - in `run()`, call the precheck before `_pack`, store the result, and pass it to `operation.run(prechecked: …)`
    in `_runOnDevice`
- [X] T014 [US1] Make the same change in `X/composition/cli/compose_run_command.dart`: precheck before the first
  `_packOperation`, reused for `--watch` rebuilds.
- [X] T015 [US1] Doctor:
  - add an optional `Future<String?> Function()? deviceServiceProblem` to `DoctorEnvironmentChecks`
    (`X/shared/cli/basic/doctor_environment_checks.dart`)
  - in `deployment()`, add a "Device service" check: success "Reachable", or a failure with
    `[device.host_service_unavailable] <hint>`
  - wire it in composition (`X/composition/cli/runner.dart` / `doctor_sections.dart`, where
    `DoctorEnvironmentChecks` is built)
  - add a test in `XT/cli/doctor_environment_checks_test.dart` named `AC-002-3 doctor reports the device service`

**Checkpoint**: the US1 tests are green; the existing device_run_operation and command tests are still green.

## Phase 4: User Story 2 — versions (P2)

**Goal**: flag > pubspec > xcconfig > project file > default, with the source logged.

### Tests first

- [X] T016 [P] [US2] In `XT/flutter/build/ios_bundle_versions_test.dart`, add an order matrix:
  - `AC-002-5 pubspec wins over stale xcconfig`
  - `AC-002-6 flags win`
  - `AC-002-7 no pubspec version → xcconfig, then pbxproj, then default`, name and number independently
  - pubspec `1.2.3` without a build number → number from the next source
  - an invalid pubspec version falls through
  - the sources are reported
- [X] T017 [P] [US2] Add an assembler-level test (extend `XT/flutter/build/flutter_packer_test.dart` or add
  `XT/flutter/build/plist_version_order_test.dart`): a stale `Generated.xcconfig` plus pubspec `1.0.7+7` gives
  Info.plist 1.0.7 / 7 for both the `$(FLUTTER_BUILD_NAME)` and `$(MARKETING_VERSION)` templates (AC-002-5).
  _Done in `XT/flutter/build/version_order_test.dart`. The file-based case is `!windows`, like the existing
  packer tests (the simulated POSIX host), so it runs on Linux CI. The precedence matrix runs on every OS._
- [X] T018 [P] [US2] Version line test, `AC-002-8`: `FlutterPackOperation` (or a small `describeVersions` helper)
  formats `Version 1.0.7 (7) · name: pubspec.yaml · number: pubspec.yaml`.

### Implementation

- [X] T019 [US2] In `X/shared/flutter/build/ios_bundle_versions.dart`, add `enum VersionSource { flag, pubspec,
  xcconfig, projectFile, fallback }` with labels from the contract, plus the fields `shortVersionSource` /
  `bundleVersionSource` (defaulting to `fallback`).
- [X] T020 [US2] Add `Map<String, String> readDebugConfigurationSync({required String debugPath,
  required String generatedPath, String sdk = 'iphoneos'})` to `X/shared/flutter/build/internal/xcconfig_resolver.dart`.
  It inlines `#include`/`#include?` recursively with a cycle guard and evaluates the result with `parseText`. Add
  unit tests.
- [X] T021 [US2] Extend `IosBundleVersionsResolver.resolve` with `pubspecBuildName`, `pubspecBuildNumber`,
  `xcconfigBuildName`, `xcconfigBuildNumber` and apply the order with sources. In `X/shared/flutter/flutter_build_steps.dart`
  (`FlutterBuildRequest`), pass the pubspec values and the sync xcconfig values: `FLUTTER_BUILD_NAME` ??
  `MARKETING_VERSION` and `FLUTTER_BUILD_NUMBER` ?? `CURRENT_PROJECT_VERSION`, all `$`-free.
- [X] T022 [US2] In `X/shared/flutter/flutter_bundle_assembler.dart` `buildSubstitutionMap`, pin `FLUTTER_BUILD_NAME`
  and `MARKETING_VERSION` to `_versions.shortVersion`, and `FLUTTER_BUILD_NUMBER` and `CURRENT_PROJECT_VERSION` to
  `_versions.bundleVersion`, for both the xcconfig overrides and the final map. Update the doc comment.
- [X] T023 [US2] In `X/shared/flutter/build/flutter_pack_operation.dart`, log the version line (T018) via
  `runtime.runner.log.logInfo('Version', …)` before `packer.pack()`.

**Checkpoint**: the US2 tests and the existing versions/packer/assembly tests are green (update expectations only
where they encoded the old order, and say so in the commit).

## Phase 5: User Story 3 — PATH guard (P3)

**Goal**: an unusable linker on a configured PATH never wins; doctor and the build warn.

### Tests first

- [X] T024 [P] [US3] `XT/toolchain/path_linker_guard_test.dart`, test `AC-002-9 unusable ld64.lld in a directory is
  reported`. A fake `ld64.lld` script prints the unsupported-platform text (or a version < 19); directories without
  `ld64.lld` and with a good linker are reported as fine; results are cached.
- [X] T025 [P] [US3] `XT/xcrun/cross_xcrun_guard_test.dart`, test `AC-002-10 xcrun skips clang/ld from an unusable
  directory`: two PATH directories, the first with a bad `ld64.lld` plus `clang`, the second with the shim `clang`.
  `xcrun --find clang` returns the second.
- [X] T026 [P] [US3] Doctor test, `AC-002-9 doctor warns for a configured PATH entry`, and a pack-operation test,
  `AC-002-10 warning once before the build`.

### Implementation

- [X] T027 [US3] Create `X/shared/toolchain/path_linker_guard.dart`: `PathLinkerGuard({required
  DarwinToolchainResolver toolchain, required HostFileSystemInterface fileSystem, required p.Context paths})` with
  `Future<String?> directoryProblem(String directory)` (cached; `probeIosSupport(ld) ?? selectorStubDefect(ld)`)
  and `Future<List<(String, String)>> configuredProblems(List<String> entries)`.
- [X] T028 [US3] In `X/shared/xcrun/cross_xcrun.dart` `_resolveTool`, for `clang`, `clang++` and `ld`, iterate
  `runner.whichAll(name, useConfiguration: false)`. Skip this executable and any candidate whose directory has a
  problem; return the first remaining candidate, otherwise fall through to the existing switch. Other tools keep the
  first-hit behaviour.
- [X] T029 [US3] Doctor:
  - add an optional `List<String> configuredPath` to `DoctorEnvironmentChecks`
  - add a `configuredPathLinkers()` check to `flutterToolchain()`, giving a warning per problem with
    `[toolchain.path_linker_unusable] <entry>: <reason>` and the hint; no row when there is no problem
  - wire `runtime.config.config?.environment['PATH']` (as `List<String>`) in composition
- [X] T030 [US3] Before the build, `FlutterPackOperation.pack` checks `runtime.configuredPath` with the guard and
  emits `runtime.warnings.warn(toolchainPathLinkerUnusable, subject: entry, …)`. Composition passes
  `configuredPath` to `FlutterBuildRuntime` (in `X/composition/flutter/*_flutter_feature_services.dart`).

## Phase 6: User Story 4 — loud warnings (P4)

### Tests first

- [X] T031 [P] [US4] Resource staging test (`XT/flutter/build/ios_bundle_resources_skips_test.dart`):
  `AC-002-13 asset catalog reported`, `AC-002-14 uncompiled storyboard reported`, plus a missing resource being
  reported (`stage` returns `SkippedResource`s).
- [X] T032 [P] [US4] Storyboard policy test: `onRemoved` is called for `UILaunchStoryboardName` /
  `UIMainStoryboardFile` / `UISceneStoryboardFile` removals (AC-002-14).
- [X] T033 [P] [US4] Plugin warning test, `AC-002-12 podspec-only plugin warning has code and hint`, at the
  `_buildPlugins` level (use the existing artifact-compiler test seams, or a project fixture with a podspec-only
  plugin).
  _Partial: `_buildPlugins` has no test seam for plugin discovery. The warning goes through `BuildWarnings` (code,
  hint and dedupe are unit-tested) and is checked manually via quickstart §5._
- [X] T034 [P] [US4] Assembler/pack test, `AC-002-15 one warning per subject and a summary`: a storyboard skipped by
  staging and removed from the plist produces a single `build.storyboard_skipped`, and the summary line is printed
  even when a later step throws.
  _Partial: dedupe across staging and the plist, and the summary, are unit-tested at `BuildWarnings` level and in
  the storyboard/resources tests. The summary-on-throw path (`try/finally` in `FlutterPackOperation.pack`) has no
  unit test because the pack needs a full runtime._

### Implementation

- [X] T035 [US4] In `X/shared/flutter/build/ios_bundle_resources.dart`, add `SkippedResource {path, reason}` and
  make `stage()` return `List<SkippedResource>`: `.xcassets` → assetCatalog, an uncompiled storyboard →
  uncompiledStoryboard, not found and not relocatable → missing.
- [X] T036 [US4] In `X/shared/artifact/plist_storyboard_policy.dart`, add an optional
  `void Function(String key, String name)? onRemoved` parameter to `stripUnsatisfiableStoryboards`.
- [X] T037 [US4] In `X/shared/flutter/flutter_bundle_assembler.dart`, turn skipped resources and plist removals into
  `runtime.warnings.warn(...)` with the contract codes. The subject for storyboards is the storyboard base name.
- [X] T038 [US4] In `X/shared/flutter/flutter_artifact_compiler.dart` `_buildPlugins`, use
  `runtime.warnings.warn(buildPodspecOnlyPlugin / buildPluginManifestMissing, subject: plugin.name, …)`, keeping the
  existing message text.
- [X] T039 [US4] In `X/shared/flutter/build/flutter_pack_operation.dart`, wrap the pack in `try/finally` and print
  `runtime.warnings.takeSummary()` with `logWarn` when it is non-null.

## Phase 7: Polish

- [X] T040 [P] Create `specs/002-quick-wins/device-check.md` with rows for an iPhone X on iOS 16 on Windows:
  - the `device.ios_unsupported` timing (< 5 s)
  - `device.not_found` with no cable
  - `device.host_service_unavailable` with the service stopped
  - doctor's "Device service" check

  Linux rows are deferred (as in 001 T045).
- [X] T041 [P] Docs: README (warning codes, version order note) and a CHANGELOG fork entry.
- [X] T042 Run `dart format` on the touched files, `dart analyze --fatal-warnings`, and the full `dart test` in
  `packages/dart_mobile_device`, `packages/darwin_sdk_kit` and `packages/xcross` (note the known environmental clang
  test failure).
- [X] T043 Real-device run (quickstart §2) on the connected iPhone X from Windows (needs `pymobiledevice3` on PATH),
  recording the results in `device-check.md`. If `pymobiledevice3` is missing, record that and leave the row open.
  _Done on the real iPhone X (iOS 16.7.16) from Windows; see `device-check.md`:
  - rows 1–6 pass (`device.ios_unsupported` with a 1.4 s net precheck; `device.not_found`;
    `device.host_service_unavailable`; doctor "Device service")
  - row 7 needs an iOS 17+ device
  - Linux is deferred_
- [X] T044 Update `specs/ROADMAP.md` (002 status) and `specs/HANDOFF.md`.

## Dependencies & Execution Order

- **Setup**: T001 comes first.
- **Foundational**: T002 and T003 block US2–US4 (warnings); US1 needs only T001.
- **US1**: T004–T007 tests, then T008 → T009 → T010 → T011 → T012 → T013/T014 → T015.
- **US2**: tests T016–T018, then T019 → T020 → T021 → T022 → T023. Independent of US1.
- **US3**: tests T024–T026, then T027 → T028 → T029 → T030. Needs T002/T003.
- **US4**: tests T031–T034, then T035 → T036 → T037 → T038 → T039. Needs T002/T003.
- **Polish**: last.

Stories US2, US3 and US4 touch disjoint files except `flutter_pack_operation.dart` (T023, T030, T039) and
`flutter_bundle_assembler.dart` (T022, T037). Edit those sequentially.

## Parallel Example

```text
T004 device_service_probe_test.dart · T005 pymd_devices_os_version_test.dart · T006 device_precheck_test.dart · T016 ios_bundle_versions_test.dart · T024 path_linker_guard_test.dart
```

## Implementation Strategy

MVP = US1 (fail fast), which saves the most time on real devices. Then US2 (correct versions), US3 (PATH) and US4
(warnings), each with its tests green before the next.
