# Tasks: Plugin drafts during the build, a check before compiling

**Input**: [spec.md](spec.md), [plan.md](plan.md), [contracts/cli.md](contracts/cli.md)

## Phase 1: User Story 1 - Drafts during the build

- [X] T001 [US1] `PluginDraftWriter` lifted out of the shim command in packages/studio_ext/lib/shared/plugins/plugin_command.dart
- [X] T002 [US1] `PluginAutoDraft` in packages/xcross/lib/src/shared/flutter/build/plugin_auto_draft.dart, called first by packages/xcross/lib/src/shared/flutter/flutter_artifact_compiler.dart
- [X] T003 [US1] Codes `build.plugin_drafted` and `build.plugin_unknown_pods` in packages/xcross/lib/src/shared/diagnostics/xcross_diagnostics.dart
- [X] T004 [US1] Tests in packages/xcross/test/flutter/build/plugin_auto_draft_test.dart

## Phase 2: User Story 2 - The check

- [X] T005 [US2] `xcross plugin check` in packages/studio_ext/lib/shared/plugins/plugin_command.dart
- [X] T006 [US2] Tests in packages/studio_ext/test/shared/plugins/plugin_check_test.dart

## Phase 3: User Story 3 - Stuck builds

- [X] T007 [US3] `ErrorStallWatchdog` in packages/cli_kit/lib/shared/process/error_stall_watchdog.dart and `stallAfterError` in packages/cli_kit/lib/shared/process/process.dart
- [X] T008 [US3] Used by packages/xcross/lib/src/host/windows/flutter/swiftpm/build_execution.dart
- [X] T009 [US3] Tests with a real process in packages/cli_kit/test/process_stall_test.dart

## Phase 4: User Story 4 - Distribution builds

- [X] T010 [US4] `forDistribution` from packages/xcross/lib/src/composition/cli/flutter_build_command.dart to packages/xcross/lib/src/shared/flutter/swiftpm/build_plan.dart
- [X] T011 [US4] Workspace of its own in packages/xcross/lib/src/shared/flutter/build/internal/swiftpm_workspace.dart, cleaned by packages/xcross/lib/src/shared/cli/flutter/subcommands/flutter_clean_command.dart
- [X] T012 [US4] Tests in packages/xcross/test/flutter/build/ios_plugin_package_test.dart and packages/xcross/test/cli/clean_commands_test.dart

## Phase 5: User Story 5 - Registration in time

- [X] T013 [US5] Engine started during launch in packages/xcross/lib/src/shared/flutter/build/runner_shim.dart and packages/xcross/lib/src/shared/flutter/build/project_runner.dart
- [X] T014 [US5] Tests in packages/xcross/test/flutter/build/runner_shim_source_test.dart and packages/xcross/test/flutter/build/project_runner_test.dart

## Phase 6: Polish

- [X] T015 CHANGELOG, README, specs/025-plugin-drafts-check/device-check.md, the codes in specs/002-quick-wins/contracts/diagnostics.md
- [X] T016 Compile checks on a test project (device-check.md rows 1 to 4)
- [ ] T017 Device check of FCM on an iPhone (AC-025-8), needs the iPhone connected
