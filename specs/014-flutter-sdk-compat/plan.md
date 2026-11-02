# Implementation Plan: Flutter SDK for iOS builds

**Branch**: `014-flutter-sdk-compat` | **Date**: 2026-11-02 | **Spec**: [spec.md](spec.md)

## Summary

- **Where the lookup lives:** `IosGenSnapshotResolver` (`packages/xcross/lib/src/shared/flutter/gen_snapshot/
  ios_gen_snapshot_resolver.dart`). `_download` asks `<repo>/releases/download/<version>/manifest.json`; a 404
  meant the unexplained `FlutterBuildError`. That error now starts with `[build.gen_snapshot_unavailable]`, adds
  "Newest Flutter with a published compiler for <host>: X." and ends with a `hint:` line. The suggestion comes
  from an injected `suggestVersion` callback (`// studio: 014`), so the resolver's own tests and HTTP calls are
  unchanged.
- **New code (all `@internal`):**
  - `shared/flutter/sdk/ios_compiler_catalog.dart`: GitHub release list (5 pages × 100), host filter, 6-hour
    cache with an offline fallback, `suggestFlutterSdk`.
  - `shared/flutter/sdk/managed_flutter_sdks.dart`: state (`missing`/`cloned`/`ready`), install through a
    `.partial-<pid>` folder, `withSdk`/`withoutSdk` on `XcrossConfig`.
  - `shared/cli/flutter/subcommands/flutter_sdk_command.dart`: `list`, `install`, `use`, `auto`, `reset` with an
    injected `FlutterSdkServices`.
  - `composition/flutter/flutter_sdk_services.dart`: the real config store, `git`, the Flutter runtime and the
    resolver's `availability`.
- **Seams (`// studio: 014`):** `flutter_command.dart` (register `sdk`), `ios_gen_snapshot.dart` (pass
  `suggestVersion`), `doctor_sections.dart` (✗ with the fix, also outside a project), `runner.dart` (`sdk list
  --json` owns stdout), `xcross_diagnostics.dart` (4 codes).
- **GUI:** `features/common/flutter_sdk_fix.dart` (`GenSnapshotProblem`, `FlutterSdkFixCard`,
  `FlutterSdkSettingsCard`). `XDiagnosticCard` gains `actions` and an expandable `details`. Readiness gains the
  `iosCompiler` area, and Build & Run, Overview, the wizard and Settings use the card.

## Decisions

- **Managed SDK location:** `<config root>/xcross/flutter-sdks/<version>`, next to `swift-sdks/`, rather than the
  cache, so `xcross cache prune` never deletes a selected SDK.
- **Config:** writing a config file switches xcross to "configured" mode (it then ignores an inherited
  `FLUTTER_ROOT` and stops searching PATH for xcrun). `use` therefore records `tools.xcrun` when the shim is not
  beside the xcross executable (source checkouts), and `reset` deletes a file that only selected the SDK.
- **Doctor:** a confirmed missing release compiler is ✗, because iOS 15/16 run only release/profile builds. An
  unknown state (offline) stays a warning.

## Constitution Check

| Principle | Status | Note |
|---|---|---|
| I | ✅ | new files plus small marked seams |
| II | ✅ | Flutter (BSD) and the compilers come from their public repositories at the user's request; nothing from Apple |
| III | ✅ | four stable codes with hints; plain wording in the GUI |
| IV | ✅ | GUI runs `xcross flutter sdk …`; events under `XCROSS_EVENTS=ndjson` |
| V | ✅ | host platform from the existing policy (`windows-x64`, `linux-x64`, …) |
| VI | ✅ | AC → tests; device row 11 |
| VIII | ✅ | version strings validated before reaching `git`; the user's Flutter untouched |

## AC → tests

| AC | Test |
|---|---|
| AC-014-1…5 | `packages/xcross/test/flutter/sdk/flutter_sdk_test.dart` |
| AC-014-6 | `ios_gen_snapshot_resolver_test.dart` `AC-014-6 …` (POSIX CI); manual run on Windows (below) |
| AC-014-7…10 | `apps/studio/test/ui/flutter_sdk_test.dart` |
| AC-014-11 | `device-check.md` |

Manual run on Windows (2026-11-02, Flutter 3.47.8):
- `xcross flutter sdk list` reported "✖ no iOS release compiler" and the fix with 3.47.6.
- `flutter doctor` showed "✗ AOT compiler (release) … newest with one: 3.47.6".
- A release build of the template app stopped with `[build.gen_snapshot_unavailable] …` and the `hint:` line.
- `sdk auto` without `--yes` explained and refused to download (exit 64).
