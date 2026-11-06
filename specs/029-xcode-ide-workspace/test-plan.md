# Test Plan and Traceability

**Status:** Implementation started. Most proposed test files/names below do not yet exist. Every automated test name must include its AC ID; manual evidence uses matching rows in device-check.md. Write behavioral tests before implementation, rather than token-only tests mirroring code.

2026-11-06 Windows baseline: `flutter test` passed (170 tests); `flutter analyze` passed. The new `cli/workspace_contract_test.dart` AC-029-9 stdin-retention case failed before the fix and passed after it; post-fix analysis passed. This narrow case does not establish the full AC-029-9 or redaction acceptance. Linux, device and other 029 acceptance evidence remain pending.

Additional Windows foundation evidence: AC-029-7 focused tests first reproduced password leakage from stdout, stderr, typed log events, JSON labels and inline command previews, then passed after redaction changes. `flutter test test/cli test/state` passed (45 tests). Chunked/multiline secrets and Windows shim invocation remain untested, so T004/T005 stay open.

Windows dispatch evidence: AC-029-8 focused tests now cover explicit batch-shim rejection and `.exe`-only PATH resolution. Six focused contract tests and `flutter analyze` passed after the change. Process-level metacharacter cases and selected-binary capability negotiation remain pending.

Post-change full Windows suite: `flutter test --reporter compact` passed with 176 tests and 1 skipped test (1 minute 47 seconds); `flutter analyze` reported no issues. This is a Windows regression result, not evidence for the unfinished 029 acceptance matrix.

## Acceptance Coverage

| Source13 / ID | Automated proof (under apps/studio/test/) | Tasks | Manual evidence |
|---|---|---|---|
| 1 / AC-029-1 | `design_system/workspace_test.dart`: hierarchy and demo isolation | T007–T013 | UI-1 |
| 2 / AC-029-2 | `workspace_test.dart`: boundary resize/collapse; `state/workspace_state_test.dart`: safe restore | T007,T010,T011,T035 | UI-1 |
| 3 / AC-029-3 | `state/project_files_test.dart`, `ui/editor_test.dart`: disk-backed edits/conflicts/search | T014–T020 | UI-2 |
| 4 / AC-029-4 | `state/workspace_run_test.dart`: real stage/exit/attachment/cancel transitions | T021,T023–T027 | DV-1,DV-2 |
| 5 / AC-029-5 | `workspace_run_test.dart`, `ui/workspace_device_artifact_test.dart`: unknown/disconnect checks | T021,T024,T028,T029 | DV-1,DV-2 |
| 6 / AC-029-6 | `workspace_device_artifact_test.dart`: modes, timestamp, unavailable capture | T028,T033 | DV-3 |
| 7 / AC-029-7 | `cli/workspace_contract_test.dart`: secret sentinels across all sinks; auth UI | T004,T005,T025,T028,T030 | SEC-1 |
| 8 / AC-029-8 | `workspace_contract_test.dart`: supported/unsupported/unknown dialects | T003,T004,T006,T021,T028 | CLI-1 |
| 9 / AC-029-9 | contract/editor/operations/accessibility tests: reason+next action, no fake codes | T004,T014,T021,T026,T028,T035 | DV-2,UI-2 |
| 10 / AC-029-10 | shell/editor/accessibility tests: actions, focus, semantics and mappings | T007,T014,T035–T039 | UI-3 |
| 11 / AC-029-11 | shell/accessibility tests on both CI hosts; native chrome manual check | T007,T035,T039,T040 | UI-1,UI-3 |
| 12 / AC-029-12 | `workspace_device_artifact_test.dart`: IPA result never publication success | T028,T032 | DV-4 |

## Functional Coverage

| Requirements | Delivery tasks |
|---|---|
| FR-001 | T007–T009,T037 |
| FR-002 | T007,T010,T011 |
| FR-003 | T014–T016,T020,T038 |
| FR-004 | T014,T015,T017,T018,T020 |
| FR-005 | T002,T014,T017,T018,T020 |
| FR-006 | T014,T019,T020,T028,T031 |
| FR-007 | T021,T023,T024,T027 |
| FR-008 | T021,T025,T027,T038 |
| FR-009 | T004,T005,T025,T028,T030,T034 |
| FR-010 | T021,T022,T030 |
| FR-011 | T003–T006,T021,T023,T024,T027 |
| FR-012 | T021,T024,T026,T028,T029,T034 |
| FR-013 | T003,T028,T032,T034 |
| FR-014 | T003,T028,T033,T034 |
| FR-015 | T009,T010,T013,T016,T018,T019,T025,T029,T030,T033,T036 |
| FR-016 | T035,T036,T039 |
| FR-017 | T012,T031,T032,T036 |
| FR-018 | T004,T021,T026,T028,T031,T035,T038 |
| FR-019 | T002,T007,T035,T037–T039 |
| FR-020 | T013,T039,T041 |

## Viewport / Interaction Matrix

On both Windows and Linux test1600×900,1599×900,1360×768,1359×768,1180×700,1179×700,1100×700. Check the editor remains at least360 px, pane minima, console120 minimum when open, visible toolbar/status, and fit including split handles. Attempt below-minimum host resize and verify bounds handling. Repeat representative large/compact states at100%,150%,200% text scale (engineering test matrix, not additional product-size promises). Persist/restore each pane preference after restart and monitor changes; restore never starts a build/sign-in.

Exercise all22 components and applicable hover/focus/pressed/disabled/busy/error states. Verify all 12 shortcut table rows (14 actions counting Alt+1/2/3 separately), remapping/conflicts and OS-reserved handling. Run keyboard-only through panes/dialogs, focus restoration after close, visible focus, semantic diagnostic announcement, reduced motion and light/dark contrast. Check actual native chrome manually, not solely via widget screenshots.

## Fixtures and Adversarial Cases

- Files: nonstandard folders, missing/read-only/deleted/renamed active files, dirty close/project switch, external revision conflict, symlink escape, invalid project root, Unicode/spaced paths, line endings/encoding.
- Language: syntax errors, stale replies, server absent/crash/restart, completion/format/definition/rename/references; no data loss after server failure.
- CLI: full support, legacy plain text, unknown support/new version, missing binary, mixed output, split UTF-8/NDJSON, stderr, done/exit disagreement, exit without done, concurrent conflicting run, cancellation failure, unsupported cancellation and reconnect.
- Secrets: synthetic password/token/Apple credential/private-key sentinels in argv, JSON fields, stdout/stderr, errors, split chunks and multiline PEM; assert absence in retained state, rendered text, command preview, clipboard and export. Never use live credentials in test fixtures.
- Device: USB/Wi-Fi, unknown/blocked/ready checks, unsupported iOS, disconnect during install/attachment, stale target and capture, denied capture, failed inspect, partial artifact. Unsupported operations must remain unavailable.
- Performance: large discovered tree/file and sustained output, bounded log retention, scrolling/filtering responsiveness, process cleanup on close/restart. Record hardware/workload/frame/memory observations; source has no numerical budget to claim as passed.

## Evidence Rules

Use fake launcher for deterministic CI tests and real device matrix for actual support. Record commit, host/toolchain/CLI version, command, expected/actual, sanitized evidence and pass/fail/pending. Device-affecting paths require native Windows/Linux with iOS16 (iPhone X) and iOS17+ per constitution. Where artifact/build logic changes, retain golden normalized IPA inspection comparison across hosts. Otherwise record unchanged artifact logic and validate GUI reveal/inspection independently. Only dated execution records above claim executed tests; all other coverage is planned and native/device rows remain pending.

## Review-derived required cases (planned)

| Resolution | Required proof | Tasks / acceptance |
|---|---|---|
| R1–R2 | Minimum fit including titlebar/scale, collapse precedence, keyboard split handles, every gallery fixture isolated from real commands | T007–T013; AC-029-1/2/10/11 |
| R3–R4 | Save failure preserves dirty text; repeat external edit invalidates overwrite; missing/read-only files; multi-file rename preview/revision guard; every inspector field/state; invalid Apply blocked | T014–T020; AC-029-3/9/10 |
| R5 | Duplicate Run, failed/unsupported cancellation, switch waits for termination, done/exit disagreement, reconnect invalidates readiness and attachment | T021–T027; AC-029-4/5/8/9 |
| R6–R7 | Byte/UTF-8/line-split secrets, PEM, unknown events, callbacks, paused logs, errors, previews, rendered text, clipboard and exports; no raw credential Copy; reveal resets on blur/deactivation; failed protected storage has no plaintext fallback | T004–T005,T025,T028,T030; AC-029-7/9; SEC-1 |
| R8 | Executable identity invalidation, probe failure, stale screenshot target/request, unavailable inspect, partial artifact and publication separation | T003,T006,T028,T032–T034; AC-029-6/8/12 |
| R9 | Traversal/symlink/junction/changed-parent, changed target after confirmation, shell metacharacters and native exe/shim handling; preserve original file on failed save | T004–T005,T014–T015,T028; AC-029-3/7/8/9 |
| R10 | Every named workflow, editor focus escape, remap collision/reserved-key rejection, secret-free semantics, measured contrast, 100/150/200% scale, both themes, native screen readers | T035–T039; AC-029-10/11; UI-3 |
| R11–R12 | All 12 AC IDs uniquely mapped; optional features do not waive required semantics; pending host/device evidence remains pending | T040–T042 |
