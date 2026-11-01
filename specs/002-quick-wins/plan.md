# Implementation Plan: Quick wins — fail fast, correct versions, PATH guard, loud warnings

**Branch**: `002-quick-wins` | **Date**: 2026-11-01 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-quick-wins/spec.md`

## Summary

Four upstreamable fixes inside the existing xcross pipeline:

1. **Fail fast (#147)**: a device precheck (host service socket check, device resolution, iOS version gate) runs
   before the build in `flutter run` / `compose run`, and its device is reused after the build.
2. **Versions**: decided once, in the order flag > pubspec > xcconfig > project file > default, with the source
   logged.
3. **PATH guard (#148)**: xcrun lookups skip clang/ld from directories whose `ld64.lld` cannot link iOS (or has the
   lld < 19 selector-stub defect). Doctor and the build warn about such configured PATH entries.
4. **Loud warnings (#145 warning part)**: coded, deduplicated warnings with hints for podspec-only plugins, skipped
   asset catalogs, uncompiled storyboards and missing resources, plus an end-of-build summary.

Decisions D1–D12 are in [research.md](research.md).

## Technical Context

**Language/Version**: Dart, workspace SDK `^3.10.0` (local 3.13.7)

**Primary Dependencies**: existing workspace packages only: `xcross`, `dart_mobile_device`, `darwin_sdk_kit`,
`cli_kit`. No new third-party packages.

**Storage**: N/A

**Testing**: `package:test` in the existing package test layouts, with fake pymd/process/socket seams. Test names
contain the AC ids. Real-device rows go in `device-check.md`.

**Target Platform**: Windows and Linux hosts (the macOS POSIX path inherits the Linux socket check)

**Project Type**: CLI (fixes in existing packages)

**Performance Goals**: an unsupported, missing or unreachable attached device is rejected in < 5 s, before any build
step (SC-001)

**Constraints**: no new artifacts or exit-code changes for projects without problems (SC-005); `repo_analyzer` rules
(socket code only under `host/**`); small marked diffs in existing upstream files

**Scale/Scope**: about 8 new files, about 12 edited upstream files, 4 user stories, 15 ACs

No open clarification items remain.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Pre | Post | Evidence |
|---|---|---|---|
| I. Minimal diff from upstream | ⚠ | ⚠ justified | The fixes edit upstream packages because they are upstream PR candidates (D1). New logic goes in new files; edits to existing files are small hunks marked `// studio: 002`. See Complexity Tracking. |
| II. Never redistribute Apple material | ✅ | ✅ | No SDK, DDI or Xcode handling changes. |
| III. Fail fast, never skip silently | ✅ | ✅ | This feature implements the principle: device checks before the build; coded warnings for every skip. |
| IV. CLI is the product | ✅ | ✅ | All behaviour is in the CLI; codes are stable for the future `--json` events (008). |
| V. Windows and Linux equal | ✅ | ✅ | The service check has one implementation per host behind the existing `DeviceHostPolicy` split; everything else is shared. |
| VI. Test-first with device evidence | ✅ | ✅ | AC → test map below; `device-check.md` rows for the real iPhone X (iOS 16) on Windows. Linux rows are deferred like feature 001's T045. |
| VII. Simplicity | ✅ | ✅ | Reuses `PymdDeviceResolver`, `OsVersion`, `probeIosSupport`, `selectorStubDefect`, `PubspecInfo`, `XcconfigResolver.parseText`; no new dependencies. |
| VIII. Licence and credential hygiene | ✅ | ✅ | No credential handling changes; device names only (no UDIDs) in new messages. |

**Gate result**: PASS (Principle I deviation justified).

## Project Structure

### Documentation (this feature)

```text
specs/002-quick-wins/
├── spec.md  plan.md  research.md  data-model.md  quickstart.md
├── contracts/diagnostics.md
├── checklists/requirements.md
├── device-check.md      # created during implementation
└── tasks.md             # /speckit-tasks
```

### Source Code

```text
packages/dart_mobile_device/lib/
├── shared/errors/errors.dart                      # + DeviceNotFoundError, PymdTimeoutError (subclasses of TunnelError)
├── shared/device/models/device.dart               # + Device.osVersion
├── shared/host/device_host_policy.dart            # + deviceServiceProblem(usbmuxAddress)
├── host/windows/windows_device_host.dart          # TCP 127.0.0.1:27015 probe
├── host/shared/posix_device_host.dart             # unix socket /var/run/usbmuxd probe
└── target/iphone/device/pymd/
    ├── pymd.dart                                  # _runWithTimeout throws PymdTimeoutError
    ├── pymd_devices.dart                          # parse ProductVersion; 20 s usbmux list timeout
    └── pymd_device_resolver.dart                  # throw DeviceNotFoundError

packages/xcross/lib/src/
├── shared/diagnostics/xcross_diagnostics.dart     # NEW: DiagnosticCode constants + codedError()
├── shared/diagnostics/build_warnings.dart         # NEW: dedupe + summary
├── shared/toolchain/path_linker_guard.dart        # NEW: unusable ld64.lld per directory
├── target/iphone/device/device_precheck.dart      # NEW: service → resolve → version → gate
├── target/iphone/device/device_run_operation.dart # + precheck(); run(prechecked:)
├── composition/cli/flutter_run_command.dart       # precheck before _pack
├── composition/cli/compose_run_command.dart       # precheck before pack
├── shared/cli/basic/doctor_environment_checks.dart# + device service + configured PATH checks
├── composition/cli/doctor_sections.dart / runner.dart (wiring)
├── shared/flutter/build/ios_bundle_versions.dart  # + sources, VersionSource
├── shared/flutter/project/ios_bundle_versions_resolver.dart # new order
├── shared/flutter/build/internal/xcconfig_resolver.dart     # + readDebugConfigurationSync
├── shared/flutter/flutter_build_steps.dart        # pass pubspec + xcconfig values
├── shared/flutter/flutter_bundle_assembler.dart   # pin version vars; report skipped resources
├── shared/flutter/build/ios_bundle_resources.dart # stage() returns SkippedResource list
├── shared/artifact/plist_storyboard_policy.dart   # optional onRemoved callback
├── shared/flutter/flutter_artifact_compiler.dart  # coded plugin warnings
├── shared/flutter/flutter_build_runtime.dart      # + warnings, configuredPath
├── shared/flutter/build/flutter_pack_operation.dart # version line, PATH warning, summary
└── shared/xcrun/cross_xcrun.dart                  # guarded clang/clang++/ld lookup
```

Tests go in the matching `packages/*/test/**` folders.

**Structure Decision**: fixes in place, in the packages that own the behaviour (D1). New concepts get new files.
Composition (`composition/**`) wires the host check function and the configured PATH entries; library code receives
them by injection, as `repo_analyzer` requires.

### Acceptance criteria → tests

| AC | Test (name contains the id) |
|---|---|
| AC-002-1, 2, 4 | `xcross/test/device/device_precheck_test.dart` (fakes; asserts < 5 s and that no build ran) and `flutter_run_command` precheck-ordering test |
| AC-002-3 | `dart_mobile_device/test/device_service_probe_test.dart` (local listener vs closed port) and `xcross/test/cli/doctor_environment_checks_test.dart` |
| AC-002-5, 6, 7 | `xcross/test/flutter/build/ios_bundle_versions_test.dart` (order matrix) and an assembler test with stale `Generated.xcconfig` |
| AC-002-8 | `flutter_pack_operation` version-line test |
| AC-002-9, 10, 11 | `xcross/test/toolchain/path_linker_guard_test.dart`, `xcross/test/xcrun/cross_xcrun_guard_test.dart`, doctor test |
| AC-002-12…15 | `xcross/test/diagnostics/build_warnings_test.dart`, resource-staging and storyboard-policy tests, plugin warning test |

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| Edits in upstream packages instead of `studio_ext` (Principle I) | The fixes change upstream behaviour (build order, version resolution, xcrun lookup, staging) and are meant as upstream PRs; the constitution asks for upstream-first fixes | Hooking them from `studio_ext` would need more seams than the fixes themselves, and could not be upstreamed |
