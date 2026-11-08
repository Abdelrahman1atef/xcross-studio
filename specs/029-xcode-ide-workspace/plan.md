# Implementation Plan: Xcode-inspired IDE workspace

**Branch:** `codex/029-xcode-ide-workspace` | **Date:** 2026-11-06 | **Spec:** [spec.md](spec.md)  
**Status:** Requirements review approved; foundation implementation has started. Remaining milestone gates still apply.

## Summary

Evolve the existing Flutter desktop shell into the source document's persistent IDE. Reuse services, command builders, typed events and workflow screens. Add real file editing and language tooling, adaptive panes and workspace persistence. Establish capability and secret-handling boundaries before wiring live actions. Implement the five source phases with acceptance evidence at each milestone.

Read [tasks.md](tasks.md) for ordered work, [test-plan.md](test-plan.md) for traceability, [quickstart.md](quickstart.md) for future validation, [research.md](research.md) for decisions, [data-model.md](data-model.md) and [contracts/workspace.md](contracts/workspace.md) for interfaces, and [design-handoff.md](design-handoff.md) for visual review coverage.

## Technical Context

- Dart constraint currently `>=3.13.0 <4.0.0`; Flutter desktop; current CI pins Flutter 3.47.8. These are repository observations, not claims about latest versions.
- Existing dependencies: Flutter, `file_selector`, `path`. Tests: `flutter_test`, fake launcher and CLI/state tests. Retain current composition/ChangeNotifier architecture.
- Storage: extend Settings with versioned per-workspace preferences; project files stay on disk. Secrets remain in OS credential storage or CLI protected storage.
- Platforms: native Windows/Linux; no WSL device support. Existing GUI CI uses Windows 2022 / Ubuntu 24.04.
- Performance: virtualize trees/logs, retain bounded logs and batched notifications. Source specifies no numeric throughput/latency target; profile representative workloads before defining a release budget.
- Editor/language-tooling dependencies are not selected or installed during planning. A bounded investigation must prove license, accessibility and both-host behavior before adoption; record justification here and license attribution in NOTICE.

## Constitution Check

| Principle | Before research / after design disposition |
|---|---|
| I Minimal upstream diff | Design pass: use `apps/studio`; any necessary CLI extension belongs in `studio_ext` with documented small seams. |
| II Apple material | Design pass: original controls, licensed fonts, user-supplied Xcode/SDK/DDI; preserve first-run acknowledgement and non-affiliation notices. |
| III Fail fast | Design pass: readiness/capability checks before Run, explicit reason and recovery. |
| IV CLI authority | Design pass: reuse subprocess adapter and typed events; no signing/build logic in widgets or internal imports. |
| V Both hosts | Design pass: HostPlatform boundary, both CI platforms and manual matrix. |
| VI Test-first/evidence | Design pass: every AC maps to named tests or device rows; tests precede implementation. No runtime evidence claimed. |
| VII Simplicity | Design pass: extend existing files/classes; dependency choice requires justification. |
| VIII Licensing/credentials | Design pass: AGPL notices, licensed fonts, no telemetry, protected credential references and ingestion redaction. |

Release still requires actual tests/device evidence, docs/CHANGELOG and legal review before 1.0. Design compliance is not release approval.

## Project Structure and Reuse

All paths are repository-relative. Proposed files below are future work, not created by this planning change.

| Area | Existing seam | Proposed additions |
|---|---|---|
| Composition | `apps/studio/lib/app/{app,app_controller,services,shell,quick_commands}.dart` | `app/workspace_controller.dart` |
| Tokens/theme | `apps/studio/lib/design_system/tokens/{colors,spacing,typography}.dart`, `theme/x_theme.dart` | `tokens/dimensions.dart`, `tokens/radii.dart` |
| Layout | `apps/studio/lib/design_system/layouts/{app_shell,workspace_layout}.dart` | `components/x_split_pane.dart` |
| Files/editor | project selection and `apps/studio/lib/src/state/settings.dart` | `features/editor/{editor_controller,editor_pane,language_service}.dart`, `features/project/{project_tree,project_file_service}.dart` |
| Inspector/preview | existing project/device/signing/artifact state | `features/inspector/inspector_pane.dart`, `features/preview/{preview_state,preview_pane}.dart` |
| Operations | `apps/studio/lib/src/cli/{xcross_commands,xcross_events,output_line,process_launcher}.dart`, `src/state/{job,readiness,devices,log_session}.dart` | `src/cli/{cli_capabilities,secret_redactor}.dart` |
| Workflows | `apps/studio/lib/features/{onboarding,build,devices,signing,project,release,settings}/` | adapt screens as secondary/docked tools |
| Tests | `apps/studio/test/{cli,state,design_system,ui}/`, `test/support/fake_launcher.dart` | test files listed in tasks and test plan |

Addition paths in the table are relative to `apps/studio/lib/` unless their full prefix is shown. Extend existing classes rather than introducing a second `XColors`, parser or services stack.

## Milestones and Exit Gates

### M0 — Planning and investigation

This delivery supplies specification, clarified assumptions, local research, architecture, contracts, test design and ordered tasks. At implementation start record baseline tests and verify editor candidates and selected CLI behavior before dependent work. No CLI setup/auth/device operation runs during planning.

### M1 — Design-system foundation (source phase 1 / US1)

Adopt all palette, typography, spacing and dimension tokens. Extend component roles, full-width console, editor/preview/inspector split panes, keyboard split controls, persistence and native chrome. Demo gallery must be labeled. Exit: layout/persistence tests pass, including narrow-window collapse. This is the visual MVP, not a complete IDE.

### M2 — Real workspace (source phase 2 / US2)

Discover actual folders; implement guarded file writes, tabs, search, editor and inspector. Integrate Dart language tooling and handle server absence. Exit: real saved files, resolved external conflicts, issue jumps and semantic actions pass fixture tests. A breakpoint gutter alone is not working debugging.

### M3 — XCross operations (source phase 3 / US3)

Probe commands/event modes; reuse lifecycle and typed events. Redact at ingestion before retention. Adapt onboarding, configuration, target selection, readiness, console and timeline. Verify VM attachment before reload/restart. Exit: success/failure/cancel/unknown fixtures pass with selected-binary evidence.

### M4 — Device, signing and preview (source phase 4 / US4)

Adapt guarded authentication, pairing/tunnels, release/IPA inspection and device metadata. Screenshot capture is conditional; absent capture means metadata mode. Preserve existing publishing routes separately without adding uploader scope. Exit: fixture tests and native device matrix, no secret leakage or publication confusion.

### M5 — Polished IDE (source phase 5 / US5)

Palette/custom shortcuts, context actions, accessible light theme, screen-reader/scaling review, profiling and process recovery. Optional Git/live/debugger/minimap remain deferred unless separately verified and scoped. Exit: twelve source ACs have passing evidence, both hosts validated and regressions green.

## Component Coverage

All 22 source roles must be covered: `XAppShell`, `XToolbar`, `XIconButton`, `XButton`, `XSegmentedControl`, `XDropdown`, `XProjectTree`, `XEditorTab`, `XEditorBreadcrumb`, `XInspectorSection`, `XPropertyRow`, `XDeviceCard`, `XDevicePreview`, `XStatusChip`, `XBuildTimeline`, `XConsole`, `XIssueRow`, `XEmptyState`, `XCommandPreview`, `XSplitPane`, `XCommandPalette`, `XSecureField`. Reuse existing equivalents; source section 6 governs variants and naming.

## Branch, Tracking and Rollback

Created from `008-json-events-gui` at `c7b477514a5737a1abe602b15029ad2a455d88d5`. Existing uncommitted pubspec/lock/analysis-options and Android files belong to the user and must not be staged incidentally. The supplied source was untracked at start and remains unchanged.

Keep implementation task boxes unchecked until code and evidence are complete. Future commits should group the five milestones with focused verification. No push, merge or issue creation is included. Roll back a future milestone by reverting its own commits; versioned preference readers must tolerate absent/newer fields without executing operations. Do not delete project files or credentials for a UI rollback.

## Complexity Tracking

Branch prefix is `codex/029-...` per active Codex instructions; the feature directory remains `029-...`. This naming-only deviation from the constitution's unprefixed convention changes no workflow gates. The source's illustrative folder structure is adapted to existing seams to avoid duplicate services/tokens. No architecture exceptions proposed.

## Requirements review integration

[Requirements review resolutions](requirements-review.md) R1–R12 are normative clarifications from the 2026-11-06 review. Apply them within the existing tasks and gates. Checklist approval does not complete implementation tasks.

T002 continuation: the native Dart LSP initialize/shutdown spike passed on Windows; see research.md. Editor candidate evaluation remains open, with no dependency adoption or license change. Native Linux, IME, screen-reader and large-file proof are still required before T017.
