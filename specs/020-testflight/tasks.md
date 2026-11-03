# Tasks: TestFlight from the CLI

S = `packages/studio_ext/lib`, ST = `packages/studio_ext/test`.

## Phase 1: Foundational

- [X] T001 S `src/shared/appstore/testflight_api.dart`: `TestFlightApi`, `TestFlightBuild`, `TestFlightGroup`,
  `TestFlightTester` (R1 paths).

## Phase 2: User Story 1 — status (P1)

- [X] T002 [US1] S `shared/appstore/testflight_command.dart`: `testflight` group, `--app-id`, app and build
  resolution, `status [--json]` (AC-020-1, AC-020-2).

## Phase 3: User Story 2 — internal testing (P1)

- [X] T003 [US2] `groups`, `group create`, `add`, `what-to-test`, `testers add|list`, `compliance` (AC-020-3…7).

## Phase 4: User Story 3 — external testing (P2)

- [X] T004 [US3] `app-info`, `review-info`, `submit`, `public-link` (AC-020-8, AC-020-9).

## Phase 5: Wiring, tests, docs

- [X] T005 `packages/xcross/lib/src/composition/cli/testflight_commands.dart`: register with `openAscApi(runtime)`.
- [X] T006 [P] ST `shared/appstore/testflight_test.dart` with `FakeAsc` (AC-020-1…9).
- [X] T007 Analyze studio_ext and xcross; `specs/020-testflight/changelog.md` (paragraph for the main session);
  `device-check.md` (AC-020-10 rows ⏳ until a team key is available).

## Dependencies

T001 → T002 → T003 → T004 → T005; T006 alongside T002–T004.
