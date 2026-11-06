# Tasks: Xcode-inspired IDE workspace

**Input:** [spec.md](spec.md), [plan.md](plan.md), research, data model and contracts.  
**Status:** Foundation work is partial; unchecked tasks remain incomplete. Test-first is required by the constitution. Paths are repository-relative. `[P]` permits concurrent work only after preceding gates; it does not request agents now.

## Setup / Investigation

- [ ] T001 Record the clean implementation baseline, available Flutter/CLI versions and existing Windows/Linux test results in `specs/029-xcode-ide-workspace/quickstart.md`; preserve unrelated working-tree changes. (FR-001–FR-020)
- [ ] T002 Evaluate editor/language tooling against Dart syntax, undo/redo, IME, keyboard/screen-reader, large-file and native Windows/Linux needs; record decision and dependency/license justification in `specs/029-xcode-ide-workspace/research.md` and `plan.md`, updating `NOTICE` only for an adopted dependency. Do not proceed with editor integration without evidence. (FR-004, FR-005, FR-019)
- [ ] T003 Inventory supported selected-binary version/help/options/event modes and safe cancellation/capture/inspection/attachment interactions in `specs/029-xcode-ide-workspace/contracts/workspace.md`; unknown support remains unknown. (FR-011–FR-014)

## Foundation / Shared Safety

- [ ] T004 Add failing AC-029-7/8/9 tests in `apps/studio/test/cli/workspace_contract_test.dart` for stdout/stderr, mixed/new-version events, chunked/multiline secrets, previews/copy/export and Windows shim/metacharacter paths; extend `test/support/fake_launcher.dart` as needed. (FR-009, FR-011, FR-018)
- [ ] T005 Implement `apps/studio/lib/src/cli/secret_redactor.dart` and connect it before retained state in `output_line.dart`, `../state/job.dart`, `../state/log_session.dart` and command display in `xcross_commands.dart`; harden native/shim dispatch at `process_launcher.dart`. No unredacted retained logs; unsupported invocation fails with reason. (FR-009, FR-011)
- [x] T006 Add `apps/studio/lib/src/cli/cli_capabilities.dart`, reuse typed `xcross_events.dart` and register capability state in `app/services.dart`; support is supported/unsupported/unknown and invalidates on executable change. Make T004 fixtures pass before live wiring. (FR-011)

## US1 / Source Phase 1 — Foundation and Shell

Goal: a usable persistent desktop shell. Independent test: gallery, resize and restart with no device.

- [ ] T007 [US1] Write failing AC-029-1/2/10/11 shell, component-state and persistence tests in `apps/studio/test/design_system/workspace_test.dart` and `test/state/workspace_state_test.dart`, using the full viewport matrix in test-plan.md. (FR-001, FR-002, FR-015, FR-019)
- [ ] T008 [US1] Update `apps/studio/lib/design_system/tokens/{colors,spacing,typography}.dart`, add `dimensions.dart`/`radii.dart` and extend `theme/x_theme.dart` with every source2 token and syntax palette, licensed font fallbacks, focus and reduced-motion support. (FR-001)
- [ ] T009 [US1] Extend core widgets in `apps/studio/lib/design_system/components/{x_button,x_fields,x_status,x_build,x_empty_state,x_command_preview}.dart`; add `x_toolbar.dart` for toolbar/icon/segmented/dropdown roles with all applicable states, tooltips and semantics. (FR-001, FR-015)
- [ ] T010 [US1] Add `apps/studio/lib/design_system/components/x_split_pane.dart` and extend `layouts/{app_shell,workspace_layout}.dart` for native chrome, five regions, full-width console, status strip, source minimum sizes and responsive collapse. (FR-002, FR-015)
- [ ] T011 [US1] Add `apps/studio/lib/app/workspace_controller.dart` and extend `src/state/settings.dart`: persist safe per-root layout/context/font/theme values; canonical valid root, viewport clamping, invalid-schema fallback, no build/sign-in on restore. (FR-002)
- [ ] T012 [US1] Adapt `apps/studio/lib/app/{shell,app_controller}.dart` so Workspace is default and all source8 administrative destinations remain reachable without discarding editor state; unknown metadata stays absent. (FR-017)
- [ ] T013 [US1] Add a clearly labeled gallery in `apps/studio/lib/design_system/component_gallery.dart` for all component roles and eight handoff states; validate T007 and record evidence in `specs/029-xcode-ide-workspace/test-plan.md`. (FR-015, FR-020)

## US2 / Source Phase 2 — Real Workspace

Goal: real file-backed editing. Independent test: temporary Flutter project; no device required.

- [ ] T014 [US2] Write failing AC-029-3/9/10 file, dirty-close, external-change, source-jump and language-action tests in `apps/studio/test/ui/editor_test.dart` and `test/state/project_files_test.dart`; include read-only/missing/symlink cases. (FR-003–FR-006)
- [ ] T015 [US2] Add `apps/studio/lib/features/project/project_file_service.dart` for canonical actual-root discovery/read/write/watch and create/rename/confirmed-delete/reveal/copy-path; mutations cannot escape root, save clears dirty only after success, revision conflict requires resolution. (FR-003, FR-004)
- [ ] T016 [US2] Add `apps/studio/lib/features/project/project_tree.dart` and `design_system/components/x_project_tree.dart`: Files/Search/Issues/Dependencies/tools, virtualized discovered hierarchy, quick open/content search, keyboard/right-click actions and all source4.1 states. Git remains future. (FR-003, FR-015)
- [ ] T017 [US2] After T002, add `apps/studio/lib/features/editor/editor_controller.dart` and `language_service.dart` using the verified editor/tooling choice; model saved revision/dirty/read-only and stale language replies, reconnect/error recovery, completion/format/definition/rename/references/diagnostics. (FR-004, FR-005)
- [ ] T018 [US2] Add `apps/studio/lib/features/editor/editor_pane.dart` and `design_system/components/x_editor_tab.dart`/`x_editor_breadcrumb.dart`: save/discard/cancel, undo/redo, search/replace, line/breakpoint gutters, brace/current-line/selection/indent visuals, wrap/tab settings and gated terminal/debug actions. Minimap stays optional/off on laptops. (FR-004, FR-005, FR-015)
- [ ] T019 [US2] Add `apps/studio/lib/features/inspector/inspector_pane.dart`, `design_system/components/x_inspector_section.dart` and `x_property_row.dart`; implement every source4.4 context/field, validation and read-only distinction. Stale selection becomes unavailable. (FR-006, FR-015)
- [ ] T020 [US2] Connect editor/tree/inspector selections and source jumps through `apps/studio/lib/app/workspace_controller.dart`; run T014 and document real-file evidence in `specs/029-xcode-ide-workspace/test-plan.md`. (FR-003–FR-006)

## US3 / Source Phase 3 — Onboarding and Real Operations

Goal: truthful setup, Run/Stop and console. Independent test: fake sessions; device acceptance follows US4.

- [ ] T021 [US3] Write failing AC-029-4/5/7/8/9 tests in `apps/studio/test/state/workspace_run_test.dart` and `test/ui/workspace_operations_test.dart`: setup, unsupported CLI, missing checks, stages, exit/done mismatch, cancel, disconnect and detached reload. (FR-007–FR-012, FR-018)
- [ ] T022 [US3] Adapt `apps/studio/lib/features/onboarding/setup_wizard.dart` and `features/common/toolchain_install.dart` for all seven source5.1 stages, prerequisites, user-supplied SDK, Swift compatibility, trust notices, doctor and supported command preview. (FR-010)
- [ ] T023 [US3] Wire project/configuration/device toolbar controls in `apps/studio/lib/app/shell.dart` and `features/build/build_run_page.dart`; validate entrypoint/flavor/defines/mode/signing/output, use command capabilities and measured status metadata. (FR-007, FR-011)
- [ ] T024 [US3] Extend `apps/studio/lib/src/state/job.dart` and `readiness.dart` for validating/starting/running/stopping/terminal lifecycle, independent attachment, one conflicting run per workspace, explicit workspace-switch handling and no false stage success. (FR-007, FR-011, FR-012)
- [ ] T025 [US3] Adapt `apps/studio/lib/design_system/components/x_console.dart`, `x_build.dart`, add `x_issue_row.dart` and extend `src/state/log_session.dart` for five primary/gated optional tabs, timestamped multiline/search/severity/autoscroll/copy/export/clear, real timeline and source jumps. (FR-008, FR-009, FR-015)
- [ ] T026 [US3] Wire guarded reload/restart/stop through `apps/studio/lib/features/build/build_run_page.dart` and `src/state/job.dart` only after verified CLI interaction plus attached session; add actionable failed/unknown/disconnected states to `features/common/job_views.dart`. (FR-012, FR-018)
- [ ] T027 [US3] Run T021 and redaction regression scenarios, recording selected-binary event/command evidence in `specs/029-xcode-ide-workspace/test-plan.md`; block this milestone on missing safety evidence. (FR-007–FR-012, FR-018)

## US4 / Source Phase 4 — Devices, Signing, Artifacts, Preview

Goal: truthful readiness and output inspection. Independent test: fixtures, then native device matrix.

- [ ] T028 [US4] Write failing AC-029-5/6/7/8/9/12 tests in `apps/studio/test/ui/workspace_device_artifact_test.dart` for all readiness checks, auth masking, stale captures, inspection absence, partial artifacts and publication separation. (FR-006, FR-009, FR-012–FR-014, FR-018)
- [ ] T029 [US4] Adapt `apps/studio/lib/features/devices/devices_page.dart` and `src/state/devices.dart`; add `design_system/components/x_device_card.dart` with USB/Wi-Fi, pairing/Developer Mode/tunnel/DDI ready/blocked/unknown, diagnostics and reconnect behavior. (FR-012, FR-015)
- [ ] T030 [US4] Adapt `apps/studio/lib/features/signing/signing_page.dart` and add `design_system/components/x_secure_field.dart`; preserve Apple ID/API-key notices and 2FA, guarded reveal/copy, protected credential references and no raw password persistence. (FR-009, FR-010, FR-015)
- [ ] T031 [US4] Connect plugin and project/device/artifact inspector properties through `apps/studio/lib/features/project/plugins_tab.dart` and `features/inspector/inspector_pane.dart`; expose version/SwiftPM/override/errors honestly and supported edits only. (FR-006, FR-017, FR-018)
- [ ] T032 [US4] Adapt `apps/studio/lib/features/release/{release_page,archives_page}.dart` for release validation, supported build options, existing-output verification, conditional inspection/reveal and artifact metadata; keep publish actions separate and capability gated. (FR-013, FR-017)
- [ ] T033 [US4] Add `apps/studio/lib/features/preview/{preview_state,preview_pane}.dart` and `design_system/components/x_device_preview.dart` for disconnected/metadata/demo/timestamped supported screenshot; zoom/refresh/mode/maximize controls, separate text scale, no live label without verified streaming. (FR-014, FR-015)
- [ ] T034 [US4] Run T028 and record Windows/Linux × iOS16/iOS17+ USB/Wi-Fi/debug/release/cancel/disconnect/preview evidence in `specs/029-xcode-ide-workspace/device-check.md`; unavailable hardware is pending, never passed. (FR-009, FR-012–FR-014)

## US5 / Source Phase 5 — Polished IDE

Goal: keyboard, assistive technology and recovery. Independent test: mapped actions and semantics plus native manual checks.

- [ ] T035 [US5] Write failing AC-029-2/9/10/11 tests in `apps/studio/test/ui/workspace_accessibility_test.dart` for all source7 bindings, conflicts/customization, focus restoration, screen-reader labels, scaled text, reduced motion and themes. (FR-016, FR-018, FR-019)
- [ ] T036 [US5] Extend `apps/studio/lib/app/quick_commands.dart`, add `design_system/components/x_command_palette.dart` and adapt `features/settings/settings_page.dart` for file/action search, all source7 shortcuts, user mappings and OS conflict handling; buttons/menus/palette use identical guards. (FR-015–FR-017)
- [ ] T037 [US5] Complete semantic light theme and text/motion preferences in `apps/studio/lib/design_system/theme/x_theme.dart` and `features/settings/settings_page.dart`; audit color-independent status, contrast, scalable controls and focus without traps. (FR-001, FR-019)
- [ ] T038 [US5] Profile large trees/files/log streams and interrupted processes; improve virtualization/bounded state/recovery at `apps/studio/lib/features/project/project_tree.dart`, `features/editor/editor_pane.dart`, `src/state/{job,log_session}.dart`; record measured workloads/results in `specs/029-xcode-ide-workspace/test-plan.md`, not invented performance claims. (FR-003, FR-008, FR-018, FR-019)
- [ ] T039 [US5] Run T035, native screen-reader/keyboard/scaling/window-chrome checks and all gallery states; record host-specific evidence in `specs/029-xcode-ide-workspace/device-check.md` and `design-handoff.md`. (FR-016, FR-019, FR-020)

## Final Verification and Handoff

- [ ] T040 Run `flutter analyze` and `flutter test` in `apps/studio` on both native hosts; extend `.github/workflows/studio-gui.yml` only if required for new acceptance tests, and record all12 AC results in `specs/029-xcode-ide-workspace/test-plan.md`. (FR-001–FR-020)
- [ ] T041 Update `docs/XCross_Studio_Xcode_Inspired_IDE_Design_System.md` capability/status notes, `CHANGELOG.md` and `NOTICE` with actual delivered behavior/licenses; preserve separate publishing and optional-feature boundaries. (FR-001, FR-011, FR-013, FR-014, FR-020)
- [ ] T042 Audit `specs/029-xcode-ide-workspace/tasks.md`, `test-plan.md` and `device-check.md`; tick only evidenced completion, resolve requirements review and release constitution gates before merge; keep deferred optional capabilities visibly disabled. (FR-001–FR-020)

## Dependencies and Execution

T001–T003 → T004–T006 → US1 → US2 → US3 → US4 → US5 → final verification. T002 gates T017; T003/T006 gate every live action; T005 gates log retention and authentication; T024 gates T026; T032/T033 need respective capability evidence. Tests within each story precede its implementation; evidence task ends each story.

Stories are independently demonstrable using fixtures after shared foundations, but production integration follows this order. Visual MVP is US1; a file-backed workspace requires US2; complete source acceptance requires all five. Optional streaming/advanced debugger/Git do not block completion if honestly unavailable, while required semantic editor actions do.

Parallel opportunities after prerequisites: US1 token work and persistence tests; US2 file-service tests and semantic-tooling investigation; US3 onboarding and console tests; US4 device-card and release-page work; US5 accessibility test authoring and performance profiling. Coordinate shared shell/settings files sequentially. No task is marked `[P]` because this handoff's default is sequential execution with explicit gates.

Task totals: setup3, foundation3, US1=7, US2=7, US3=7, US4=7, US5=5, final3; **42 total**, all unchecked.

## Requirements review integration

[Requirements review resolutions](requirements-review.md) R1–R12 are normative clarifications from the 2026-11-06 review. Apply them within the existing tasks and gates. Checklist approval does not complete implementation tasks.

Review continuation: all 12 requirements-quality checks passed; T002 has a Windows LSP capability spike recorded in research.md but remains incomplete. T004/T005 still require stream and native dispatch evidence. No implementation task was checked solely because the review passed.
