# Research: 002 quick wins

Phase 0 output for [plan.md](plan.md). Paths: X = `packages/xcross/lib/src`, DMD = `packages/dart_mobile_device/lib`.
Every decision lists Decision / Rationale / Alternatives.

## D1 — Where the code lives (constitution Principle I)

- **Decision**: these fixes go into the upstream packages (`xcross`, `dart_mobile_device`, `darwin_sdk_kit`) as
  upstream-quality changes, with new logic in **new files** and each edited hunk in an existing file marked
  `// studio: 002`. They are prepared as upstream pull requests (#145 warning part, #147, #148).
- **Rationale**: Principle I says generally useful fixes are proposed upstream first, and the ROADMAP marks 002
  "Upstreamable: yes". `studio_ext` cannot hold them: they change behaviour inside the build and device pipeline, and
  `studio_ext` must stay a leaf package with no dependency on xcross internals.
- **Alternatives**: hooks from `studio_ext` into xcross (rejected: would need many more seams than the fixes
  themselves).

## D2 — Coded diagnostics without a new error type

- **Decision**: a new file `X/shared/diagnostics/xcross_diagnostics.dart` holds `DiagnosticCode(code, hint)`
  constants and a helper `codedError(code, message, {hint})` that returns an `XcrossError` whose message is
  `[<code>] <message>\nhint: <hint>`. `formatFailure` already prints `XcrossError` as `error: <message>` without a
  stack trace, so no runner change is needed.
- **Rationale**: the same `[code] message` + `hint:` shape as feature 001; no new error class means no edit to
  `formatFailure`.
- **Alternatives**: add `code`/`hint` fields to `XcrossError` (rejected: every construction site and `formatFailure`
  would change).

## D3 — Device precheck before the build (US1)

- **Decision**:
  - A new `DevicePrecheck` (`X/target/iphone/device/device_precheck.dart`) runs these steps:
    1. host service check, unless the search is Wi-Fi only
    2. device resolution, through the existing `PymdDeviceResolver`, with the existing picker
    3. OS version, from the device listing when it is present, else the existing `OsVersion` lookup
    4. the minimum-version gate (iOS 17)
  - The result is a `PrecheckedDevice`.
  - `DeviceRunOperation` gains `precheck(...)`, and `run(...)` accepts an optional `PrecheckedDevice`. When one is
    given, `run` skips resolution and the gate.
  - `FlutterRunCommand.run` and `ComposeRunCommand.run` call the precheck **before** the build and hand the result
    to the device run after it.
  - The commands' test seams (`withSeams`) get an optional precheck seam. When a test injects `runDevice` without a
    precheck, no precheck runs, so existing tests keep working.
- **Rationale**: reuses every existing device component, adds no new device protocol, and keeps the multi-device
  picker and `--udid` semantics. Building the operation (`DeviceBackend.resolve`) is cheap: it only constructs
  objects.
- **Alternatives**:
  - resolve the device twice, before and after the build (rejected: two prompts, and two slow listings)
  - move the whole run before the build (rejected: signing needs the built app)

## D4 — OS version from the listing

- **Decision**: `Device` gets an optional `osVersion` (String?), parsed from the `ProductVersion` field that
  `pymobiledevice3 usbmux list` already prints. The precheck uses it first and falls back to `OsVersion` (lockdown
  info, then ideviceinfo).
- **Rationale**: saves one pymobiledevice3 start-up (1–2 s on Windows), which keeps an iOS 16 rejection under the
  5-second target (SC-001).
- **Alternatives**: always call `lockdown info` (rejected: an extra process for every run).

## D5 — Host device service check

- **Decision**:
  - `DeviceHostPolicy` gains `Future<String?> deviceServiceProblem(String? usbmuxAddress)`. It returns null when the
    service accepts a connection, otherwise an OS-specific explanation and fix.
  - **Windows** (`WindowsDeviceHost`): TCP connect to `127.0.0.1:27015`, where Apple Mobile Device Service listens,
    or to the `USBMUXD_SOCKET_ADDRESS` override.
  - **Linux/macOS** (`PosixDeviceHost`): connect to the unix socket `/var/run/usbmuxd`, or the override /
    `Pymd.resolvedUsbmuxAddress()`.
  - Timeout 2 s.
  - The precheck calls it with `pymd.resolvedUsbmuxAddress()`, and doctor gets the same check through an optional
    function parameter on `DoctorEnvironmentChecks`.
- **Rules**:

  | Search mode | Service down | Result |
  |---|---|---|
  | USB only | yes | stop with `device.host_service_unavailable` |
  | both (default) | yes, and no device found | stop with `device.host_service_unavailable` instead of `device.not_found` |
  | both (default) | yes, but a tunnel device is found | proceed (Linux usbmuxd only knows USB devices) |
  | Wi-Fi only | — | check skipped |

- **Rationale**: a socket connect is the most direct, fastest check (< 50 ms), needs no admin rights and no service
  names (iTunes and the Microsoft Store "Apple Devices" app name the service differently). Socket code lives in
  `DMD/host/**`, where `repo_analyzer` allows native access.
- **Alternatives**:
  - `sc query` / `systemctl is-active` (rejected: service names differ by installer and distro, and it is slower)
  - parse the pymobiledevice3 error text (rejected: brittle)

## D6 — Typed device errors and bounded listing

- **Decision**:
  - `DMD/shared/errors/errors.dart` gains two subclasses of the existing `TunnelError`:
    - `DeviceNotFoundError`, thrown by `PymdDeviceResolver` where it throws "No devices connected" / "No connected
      device matching"
    - `PymdTimeoutError`, thrown by `Pymd._runWithTimeout`
  - `PymdDevices.devices` gets a 20 s timeout for `usbmux list`.
  - The precheck maps `DeviceNotFoundError` → `device.not_found` and `PymdTimeoutError` → `device.query_timeout`.
- **Rationale**: subclasses keep every existing `on TunnelError` catch and `formatFailure` working (it matches
  `TunnelError(:message)`), while letting the precheck pick the right code without matching message text.
- **Alternatives**: string matching on messages (rejected: fragile).

## D7 — Version order (US2)

- **Decision**:
  - `IosBundleVersions` gains `shortVersionSource` / `bundleVersionSource` (`VersionSource` enum: flag, pubspec,
    xcconfig, projectFile, fallback; both default to fallback).
  - `IosBundleVersionsResolver.resolve` takes the pubspec build name/number and the xcconfig build name/number, and
    applies flag > pubspec > xcconfig > project file > default, independently for name and number.
  - The xcconfig values are read **synchronously** by a new `XcconfigResolver.readDebugConfigurationSync`, which
    inlines `#include`/`#include?` files (relative to the including file, with a cycle guard) and evaluates them with
    the existing `XcconfigResolver.parseText`.
  - Keys: `FLUTTER_BUILD_NAME`, else `MARKETING_VERSION`; `FLUTTER_BUILD_NUMBER`, else `CURRENT_PROJECT_VERSION`.
  - `FlutterBuildRequest` passes `pubspec.buildName/buildNumber` (already parsed by `PubspecInfo`) and the xcconfig
    values.
  - In `FlutterBundleAssembler.buildSubstitutionMap`, the four version variables are pinned to the decided values,
    replacing today's flag-only overrides, so `$(FLUTTER_BUILD_NAME)` and `$(MARKETING_VERSION)` both expand to the
    decided version.
  - The forced-key rule in `_writeInfoPlist` is unchanged: a missing key is written; a literal key is overwritten
    only by a flag.
- **Rationale**:
  - One decision point keeps the app and its extensions on the same version pair (an `IosBundleVersions`
    invariant).
  - The sync xcconfig read avoids turning the build request into an async object.
  - pubspec is what `flutter build` uses on a Mac (Flutter regenerates `Generated.xcconfig` from it on every build),
    so the stale-file bug disappears.
- **Alternatives**:
  - decide versions inside the async assembler (rejected: extensions and the linker read `context.versions`
    earlier)
  - rewrite `Generated.xcconfig` from pubspec before building (rejected: writes into the user's project)

## D8 — Version reporting (FR-009)

- **Decision**: `FlutterPackOperation.pack` logs one info line before building, for example
  `Version 1.0.7 (7) · name: pubspec.yaml · number: pubspec.yaml`.
- **Rationale**: the user sees the source immediately; it costs one line.

## D9 — PATH guard (US3, #148)

- **Root cause (from code reading, see the spec's assumption)**:
  1. `RuntimeConfig` prepends config `environment.PATH` entries to the inherited PATH for every child process.
  2. During native-asset builds, `flutter assemble` puts xcross's linker-pinning clang shim first on PATH.
  3. But the `xcrun` mode of xcross (`CrossXcrun._resolveTool`) rebuilds its environment from the config, so the
     configured Swift toolchain directory comes **before** the shim.
  4. `xcrun clang` / `xcrun ld` then returns that toolchain's clang/lld. A Swift-bundled lld is older than 19, so it
     either cannot link iOS or miswires Objective-C selector stubs (see the CHANGELOG for 2.0.9).
- **Decision**:
  - A new `PathLinkerGuard` (`X/shared/toolchain/path_linker_guard.dart`) reports why a directory's `ld64.lld` is
    unusable, using the existing `DarwinToolchainResolver.probeIosSupport` **and** `selectorStubDefect`, with a
    per-directory cache.
  - **(a)** `CrossXcrun._resolveTool` for `clang`, `clang++` and `ld` walks `runner.whichAll(...)` and skips
    itself and any candidate whose directory has an unusable `ld64.lld`. If nothing is left it falls through to the
    existing vetted resolvers.
  - **(b)** Doctor adds the check "Configured PATH": warning `toolchain.path_linker_unusable` per offending entry.
  - **(c)** `FlutterPackOperation.pack` emits the same warning once before building. It uses the configured PATH
    entries, which composition passes to `FlutterBuildRuntime` (new optional `configuredPath`, default empty) and
    `DoctorEnvironmentChecks`.
- **Rationale**: evidence-based (the same probes setup already trusts), works for any PATH order, and keeps the shim
  path intact. No test needs a real Swift toolchain: a fake `ld64.lld` script that prints the unsupported-platform
  text reproduces the case.
- **Alternatives**:
  - ignore configured PATH for xcrun lookups (rejected: users rely on PATH for other tools)
  - always return the vetted clang (rejected: bypasses the shim that pins `--ld-path`)

## D10 — Build warnings with codes, dedupe and summary (US4)

- **Decision**:
  - A new `BuildWarnings` (`X/shared/diagnostics/build_warnings.dart`) is held by `FlutterBuildRuntime` as a
    `late final` field, the pattern the runtime already uses.
  - `warn(code, subject, message)` prints `[<code>] <message>` + `hint:` once per (code, subject).
  - `takeSummary()` returns `Build finished with N warning(s): code ×n, …` and resets.
  - `FlutterPackOperation.pack` prints the summary in a `finally`, so it also shows when the build fails.
- **Rationale**: one per-build collector; nothing global; no constructor changes for its users.
- **Alternatives**: a decorator around `Log` (rejected: `Log` is a concrete cli_kit class, and dedupe needs
  subjects).

## D11 — Silent skips made loud

- **Decision**:
  - **Podspec-only plugins**: `_buildPlugins` (`X/shared/flutter/flutter_artifact_compiler.dart`) replaces its
    `logWarn` with `runtime.warnings.warn(build.podspec_only_plugin, …)`. The existing message is kept and a hint
    added. The "declares native code but no manifest" warning gets `build.plugin_manifest_missing`.
  - **Resources**: `IosBundleResources.stage` returns the resources it skipped (`SkippedResource{path, reason}`,
    where reason is assetCatalog, uncompiledStoryboard or missing). The assembler turns them into
    `build.asset_catalog_skipped`, `build.storyboard_skipped` and `build.resource_missing`.
  - **Storyboard references**: `PlistStoryboardPolicy.stripUnsatisfiableStoryboards` gains an optional
    `onRemoved(key, name)` callback. The assembler reports the removal as `build.storyboard_skipped` with the
    storyboard name as subject, so it dedupes with the resource warning.
  - App extensions already warn; they are unchanged.
- **Rationale**: the staging and policy classes stay free of logging, which keeps their diffs small and the
  assembler (which owns `runtime`) the single place that reports.

## D12 — Testing approach

- **Decision**: unit tests in the existing xcross / dart_mobile_device test layout, with names containing the AC ids:
  - precheck with fake resolver, version and service functions (AC-002-1…4)
  - host policy socket checks against a real local listener and a closed port (AC-002-3)
  - version resolver matrix and an assembler test with stale `Generated.xcconfig` (AC-002-5…8)
  - `PathLinkerGuard` and `CrossXcrun` lookup with fake `ld64.lld` scripts (AC-002-9, 10)
  - `BuildWarnings` and assembler warnings with fixture projects (AC-002-12…15)

  The 5-second budget is asserted in the precheck test with fakes that answer immediately. Real-device timing is a
  `device-check.md` row (iPhone X, iOS 16, Windows; Linux deferred like T045 of feature 001).
- **Rationale**: Principle VI; the existing suites already use fakes for pymd and processes.
