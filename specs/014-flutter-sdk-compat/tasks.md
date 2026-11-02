# Tasks: Flutter SDK for iOS builds

X = `packages/xcross/lib/src`, G = `apps/studio/lib`.

- [X] T001 `X/shared/diagnostics/xcross_diagnostics.dart`: `build.gen_snapshot_unavailable`,
  `toolchain.flutter_sdk_install_failed`, `toolchain.flutter_sdk_version_unavailable`, `toolchain.git_missing`.
- [X] T002 `X/shared/flutter/sdk/ios_compiler_catalog.dart`: catalog, cache, `suggestFlutterSdk`.
- [X] T003 `X/shared/flutter/sdk/managed_flutter_sdks.dart`: install (partial folder, bootstrap, retry), state,
  `withSdk`/`withoutSdk`.
- [X] T004 `X/shared/cli/flutter/subcommands/flutter_sdk_command.dart`: `list|install|use|auto|reset`.
- [X] T005 `X/composition/flutter/flutter_sdk_services.dart` + seams in `flutter_command.dart`,
  `ios_gen_snapshot.dart`, `doctor_sections.dart`, `runner.dart`.
- [X] T006 Resolver: coded error with the suggestion and the `hint:` line.
- [X] T007 CLI tests `test/flutter/sdk/flutter_sdk_test.dart` (AC-014-1…5) and the resolver test (AC-014-6).
- [X] T008 G: `features/common/flutter_sdk_fix.dart`; `XDiagnosticCard` actions/details; readiness area
  `iosCompiler`; Build & Run, Overview, wizard, Settings.
- [X] T009 G tests `test/ui/flutter_sdk_test.dart` (AC-014-7…11 builders).
- [X] T010 Docs: CHANGELOG, ROADMAP, README, runbook step 0.4, `device-check.md`.
- [ ] T011 Device check on the Windows PC with the iPhone X (row 11).
