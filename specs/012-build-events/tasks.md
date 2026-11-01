# Tasks: NDJSON build events

K = `packages/cli_kit`, S = `packages/studio_ext`, X = `packages/xcross/lib/src`, G = `apps/studio`.

- [X] T001 K `shared/logging/logging.dart`: `LogEventLevel`, `LogEvents`; `Log(events:)`; status/trace/warn/error
  and `Step` start/output/finish go to the observer; no fancy drawing with an observer (`// studio: 012`).
- [X] T002 K `shared/progress/progress.dart`: `progress` events (one per whole percent, or every 250 ms without a
  total; 1.0 on finish); no bar drawing with an observer.
- [X] T003 K test `test/log_events_test.dart` (AC-012-1).
- [X] T004 `contracts/events.schema.json` (step, progress, log, warning, error, artifact, device, check, done).
- [X] T005 S `lib/shared/events/ndjson_events.dart`: `NdjsonEvents` (+ `fromEnvironment`, `parseCoded`,
  `stripAnsi`) and `NdjsonLogOutput`; S test `test/shared/events/ndjson_events_test.dart` with
  `JsonSchemaLite.buildEventsContract()` (AC-012-2).
- [X] T006 X seams: `native_runtime.dart`, `runner.dart` (`reportFailure`, `done`), `flutter_pack_operation.dart`,
  `flutter_build_command.dart`, `device_precheck.dart` (`reportDevice`), `device_run_operation.dart`,
  `doctor_command.dart`.
- [X] T007 X test `test/cli/build_events_test.dart` (AC-012-3, 4, 5).
- [X] T008 G `xcross_events.dart`: `split`, `BuildStep`, `BuildProgress`, `BuildLog`, `BuildIssue`, `BuildArtifact`,
  `DoctorCheckResult`, `BuildDone`.
- [X] T009 G `job.dart`: `structured`, `XCROSS_EVENTS`, steps/progress/artifacts/checks/device/exit code;
  `JobCenter.run(structured:)`.
- [X] T010 G widgets `StepsPanel`, `IssueList`, `DoctorReport`; pages use structured jobs; Install uses the artifact;
  Setup doctor runs `flutter doctor`.
- [X] T011 G test `test/state/build_events_test.dart` (AC-012-6, 7, 8).
- [X] T012 Docs (CHANGELOG, ROADMAP, README, device-check); analyze; tests; commit; push.
