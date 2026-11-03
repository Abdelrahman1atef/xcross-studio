# Tasks: XCross Studio release flow

S = `packages/studio_ext/lib`, G = `apps/studio/lib`.

## Phase 1: CLI (US2)

- [X] T001 [US2] S `shared/release/release_gate_command.dart` and its registration (AC-022-5).
- [X] T002 [US2] S `src/shared/release/ci_template.dart`, `ReleaseCiCommand` in `shared/release/release_gate_command.dart`;
  `docs/ci/github-testflight.yml` (AC-022-6).
- [X] T003 [US2] Wire both into `ReleaseCommand` and `packages/xcross/lib/src/composition/cli/runner.dart`.
- [X] T004 [P] [US2] Tests `packages/studio_ext/test/shared/release/release_gate_test.dart`.

## Phase 2: Release page (US1)

- [X] T005 [US1] G events and commands for release check, publish, TestFlight, App Store status, gate.
- [X] T006 [US1] G `features/release/release_page.dart` (ten steps, record card) (AC-022-1…4).
- [X] T007 [US1] G destinations in `app/app_controller.dart`, `app/shell.dart`.

## Phase 3: Archives (US3)

- [X] T008 [US3] G `features/release/archives_page.dart` (AC-022-7).
- [X] T009 [P] Tests `apps/studio/test/ui/release_test.dart`.

## Phase 4: Evidence and polish

- [X] T010 Rebuild the CLI, repackage the desktop app, check the pages on app A (`device-check.md`, AC-022-8).
- [X] T011 Analyze, CHANGELOG, README, user story (AC-08, AC-10, §11, §12; TC-13, 14, 17, 31; IOS-24).
