# Tasks: Upload to App Store Connect and follow processing

S = `packages/studio_ext/lib`, X = `packages/xcross/lib/src`.

## Phase 1: Foundational

- [X] T001 Shared API client, session helpers, `FakeAsc`, composition files (commit `0936a3f`).

## Phase 2: User Story 1 — upload (P1)

- [X] T002 [US1] S `src/shared/appstore/build_upload.dart`: create, reserve, send operations with retries, commit,
  resume state (AC-019-1, AC-019-3).
- [X] T003 [US1] S duplicate check in `src/shared/appstore/build_processing.dart` (AC-019-2).
- [X] T004 [US1] S `shared/appstore/publish_command.dart`: input IPA, Info.plist, app lookup, errors (AC-019-4);
  register in X `composition/cli/publish_commands.dart`.

## Phase 3: User Story 2 — processing (P1)

- [X] T005 [US2] S `BuildProcessing.wait` (AC-019-5) and the `--json` events (AC-019-6).

## Phase 4: User Story 3 — build numbers and record (P2)

- [X] T006 [US3] S `shared/appstore/build_numbers.dart`; X `--build-number auto` seam in
  `composition/cli/flutter_build_command.dart` (AC-019-7).
- [X] T007 [US3] S `src/shared/appstore/release_record.dart` (AC-019-8).

## Phase 5: User Story 4 — Transporter (P3)

- [X] T008 [US4] S `src/shared/appstore/transporter.dart`, `--transporter` and `--validate` (AC-019-9).

## Phase 6: Tests, evidence, docs

- [X] T009 Tests `packages/studio_ext/test/shared/appstore/publish_test.dart` (AC-019-1…9).
- [X] T010 Rebuild the CLI; try the individual key against `/v1/apps` and a publish dry path; `device-check.md`
  (AC-019-10).
- [X] T011 Analyze, CHANGELOG, README, user story (AC-02, AC-11…AC-13, §11; TC-19…21, 29…31).
