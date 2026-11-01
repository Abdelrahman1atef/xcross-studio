# Implementation Plan: Compile the project's own Runner code

**Branch**: `007-native-runner-code` | **Date**: 2026-11-01 | **Spec**: [spec.md](spec.md) | **Research**: [research.md](research.md)

## Summary

`XCROSS_RUNNER=project` makes the Flutter link step compile the app target's own sources (AppDelegate, …) into
`Runner`. xcross adds a support file containing a `GeneratedPluginRegistrant` that forwards to the plugins library,
and an `XcrossSceneDelegate` that creates the window. Any problem falls back to the generic runner with a coded
warning.

## Technical Context

**Language**: Dart `^3.10`. **Dependencies**: existing xcross toolchain (Darwin clang, host `swiftc`, ld64.lld, Darwin
SDK). **Testing**: unit tests for discovery, command lines, support source, plist, fallback (all hosts) plus an
assembler test (Linux CI). **Constraints**: default builds unchanged; the build never fails because of this feature.

## Design

- `shared/flutter/build/project_runner_sources.dart` (new):
  - `RunnerMode` (from `XCROSS_RUNNER`);
  - `ProjectRunnerSources.discover`, which reads the pbxproj application target or lists `ios/Runner`, and detects
    the bridging header, module name, implicit-engine vs. launch registration and a non-empty `SceneDelegate`.
- `shared/flutter/build/project_runner.dart` (new):
  - `ProjectRunner`: decides, warns and falls back. Its dependencies are injected, so it is testable on every host.
  - `ProjectRunnerBuilder`: compiles and links. Its argument builders are `@visibleForTesting` statics. It also holds
    the support source and `withSceneDelegate`.
- Seams (`// studio: 007`):
  - `flutter_artifact_linker.dart`: try the project runner before the shim, and pass the plugin modules directory.
  - `internal/runner_binary.dart`: optional `sceneDelegateClass`.
  - `flutter_bundle_assembler.dart`: apply `withSceneDelegate` after the existing plist normalization.
  - `xcross_diagnostics.dart`: three `build.runner_*` codes.

## Constitution Check

| Principle | Status | Note |
|---|---|---|
| I | ⚠ justified | The compile path needs `@internal` xcross runtime pieces (toolchain, SDK repository, engine slice), as features 003, 005 and 006 did; new files plus four small marked seams. Upstream PR candidate (#149) |
| II | ✅ | Uses only the user's own SDK and toolchain |
| III | ✅ | Coded warnings with hints; never a silent skip |
| IV, V | ✅ | Same tools on Windows and Linux; no host-specific code |
| VI | ✅ | AC → tests below; device row in `device-check.md` |

## AC → tests

| AC | Test (`packages/xcross/test/flutter/build/`) |
|---|---|
| AC-007-1 | `project_runner_test.dart` `AC-007-1 by default the generic runner is kept, nothing runs` |
| AC-007-2 | `AC-007-2 source discovery` group; `AC-007-2 XCROSS_RUNNER=project compiles the template quietly` |
| AC-007-3 | `AC-007-3 compiler and linker command lines` group |
| AC-007-4 | `AC-007-4 xcross support code and Info.plist` group; `project_runner_assembly_test.dart` (Linux CI) |
| AC-007-5 | `AC-007-5 a compile failure …`, `AC-007-5 no sources …` |
| AC-007-6 | `AC-007-6 legacy registration and scene delegate code warn` |
| AC-007-7 | `device-check.md` |
