# Tasks: App Store submission from the CLI

S = `packages/studio_ext/lib`, ST = `packages/studio_ext/test`.

## Phase 1: Setup

- [X] T001 `S/src/shared/appstore/app_store_project.dart`: bundle ID, display name, SKU suggestion.

## Phase 2: User Story 1 — app record and version (P1)

- [X] T002 [US1] `S/src/shared/appstore/app_store_versions.dart`: editable states, find/create version, find build.
- [X] T003 [US1] `S/shared/appstore/appstore_command.dart`: `appstore app`, `appstore version` (AC-021-1, 2).

## Phase 3: User Story 2 — metadata folder (P1)

- [X] T004 [US2] `S/src/shared/appstore/app_store_metadata.dart`: folder model, pull, push with changes
  (AC-021-3, 4); subcommands `metadata pull|push`.

## Phase 4: User Story 3 — screenshots (P1)

- [X] T005 [US3] `S/src/shared/appstore/app_store_screenshots.dart`: size table, PNG reader, reserve → upload
  operations → commit, `--replace` (AC-021-5, 6); subcommand `screenshots push`.

## Phase 5: User Story 4 — attach, submit, status (P1)

- [X] T006 [US4] `S/src/shared/appstore/app_store_review.dart`: attach, blockers, review submission, status
  (AC-021-7…10); subcommands `attach`, `submit`, `status`.
- [X] T007 [US4] `packages/xcross/lib/src/composition/cli/appstore_commands.dart`: register the group with
  `openAscApi` (`// studio: 021`).

## Phase 6: Tests and polish

- [X] T008 [P] `ST/shared/appstore/appstore_test.dart` with `FakeAsc` (AC-021-1 … AC-021-10).
- [X] T009 Analyze studio_ext and xcross; `device-check.md` (AC-021-11 ⏳ without a team key); CHANGELOG paragraph in
  `specs/021-app-store-submission/changelog.md`.

## Dependencies

T001 → T003; T002 → T003…T006; T007 after the command exists.
