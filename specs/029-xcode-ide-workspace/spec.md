# Feature Specification: Xcode-inspired IDE workspace

**Feature branch:** `codex/029-xcode-ide-workspace`  
**Created:** 2026-11-06  
**Status:** Requirements review approved; implementation in progress, acceptance incomplete  
**Source:** [Design system v2.0](../../docs/XCross_Studio_Xcode_Inspired_IDE_Design_System.md)

## Scope

Deliver the source document's Windows/Linux workspace and five build phases. The source is the only product-requirements authority for this feature; repository inspection supplies implementation seams and the constitution supplies engineering gates. Existing features do not automatically expand this scope. No application code, dependencies, test implementations, external design files, uploads or publishing are part of this planning change.

## Clarifications

### Review 2026-11-06

No user answers were needed or invented. Planning interpretations:

- Source sections 3.1 and 9 are complementary: at 1360–1599 px show one auxiliary pane; at 1180–1359 px permit one toggled auxiliary pane only when minimum widths fit; below 1180 px start with navigator/editor. At every size preserve editor minimum width, collapsing other panes as needed.
- The entire five-phase roadmap is planned. Light theme belongs to phase 5; Git integration, live streaming, advanced debugging and optional minimap remain explicitly optional/future. Capability-gated screenshot and breakpoint actions never imply backend availability.
- Section 7 defines Studio shortcuts; console examples using R/Shift+R are illustrative CLI hints, not competing application bindings.
- Section 14 is a suggested handoff: document its pages/states and naming now; do not create a Figma library without a separate request.
- Illustrative commands are not executable contracts until support is established for the selected binary. Unknown support disables affected actions with an explanation.
- Source has no numeric performance budget or editor-package choice. These are implementation investigation gates, not invented product promises.

## User Scenarios & Testing

### US1 — Navigate a persistent desktop workbench (P1)

Value: a coherent workspace that remains usable at supported desktop sizes.
Independent test: use a labeled demo gallery, resize all panes, navigate by keyboard and restart without a device.

1. Given an empty workspace, when opened, then show toolbar, navigator, editor, honest preview, inspector, console and status strip with source-defined tokens and empty actions.
2. Given resized/hidden panes, when reopened, then restore safe workspace preferences without starting an operation.
3. Given a compact window, when resized, then auxiliary panes collapse before the editor falls below its minimum.

### US2 — Work on real project files (P1)

Value: open, navigate, edit and diagnose a real Flutter project.
Independent test: temporary project with nonstandard folders and Dart errors; edit/save/reopen and navigate an issue without a device.

1. Given an actual project, when opened, then discover its actual tree and expose search, tabs, breadcrumbs and contextual properties.
2. Given unsaved edits or an externally changed file, when closing/saving/switching project, then resolve changes explicitly without silent data loss.
3. Given available language tooling, when requesting formatting, completion, definitions, symbol rename or references, then show real results; unavailable tooling explains disabled actions.

### US3 — Prepare, run and stop a project (P1)

Value: select a valid target and execute a truthful build/debug session.
Independent test: fake process fixtures covering success, failure, unsupported CLI and cancellation; real-host evidence follows separately.

1. Given first launch, when setting up, then guide prerequisite detection, user-supplied SDK, authentication, device checks, project doctor and Ready with a supported command preview.
2. Given a ready project/device, when Run is selected, then reflect compile, sign, install, launch and attach only from actual operation evidence.
3. Given an attached session, when reload/restart/stop is requested, then dispatch only supported actions and reflect actual results; failure includes reason and next step.

### US4 — Manage devices, signing, artifacts and preview (P2)

Value: understand readiness and safely inspect a successful output.
Independent test: fixtures for disconnected, unknown, paired, unsupported, screenshot and artifact states; device matrix verifies real behavior.

1. Given a selected iPhone, when checks complete, then distinguish USB/Wi-Fi, pairing, Developer Mode, tunnel and DDI; unknown is never success.
2. Given authentication setup, when entering credentials, then present trust/2FA/anisette notices, mask secrets and exclude them from all display/export paths.
3. Given a release configuration, when build succeeds, then verify and inspect supported output and reveal it; IPA creation does not imply publication.
4. Given preview mode, when displayed, then label disconnected, metadata, timestamped screenshot or demo truthfully; live mode requires verified streaming.

### US5 — Operate an accessible, polished IDE (P2)

Value: complete major workflows with keyboard, assistive technology and configurable appearance.
Independent test: shortcut/focus/semantics tests plus manual Windows/Linux screen-reader and scaling runs.

1. Given a mapped shortcut or palette action, when invoked, then execute the same guarded action as menus and show current mappings.
2. Given scaling, reduced motion or light theme, when navigating, then retain readable controls, visible focus and diagnostic meaning independent of color.
3. Given heavy output or process failure, when interacting, then retain usable navigation and expose recovery without false success or unintended restart.

## Functional Requirements

| ID | Requirement | Source sections | Story |
|---|---|---|---|
| FR-001 | Use the complete semantic palette, syntax palette, typography, spacing, geometry and applicable interaction states; original assets and licensed/system fonts. | 1, 2, 6 | US1 |
| FR-002 | Provide five workspace regions plus status strip, native host chrome, specified default/minimum dimensions, adaptive collapse and safe per-workspace persistence. | 3, 9 | US1 |
| FR-003 | Provide real tree discovery, Files/Search/Issues/Dependencies/tools modes, file actions, quick open, content search and meaningful empty/error states; delete requires confirmation. | 4.1 | US2 |
| FR-004 | Provide real file open/edit/save, dirty tabs, breadcrumbs, undo/redo, search/replace, indentation, wrap, gutters and external-change handling. | 4.2 | US2 |
| FR-005 | Connect actual language tooling for semantic editor actions and diagnostics; capability-gate breakpoints and terminal actions; optional minimap stays off on laptops. | 4.2 | US2 |
| FR-006 | Render file/project/device/build/artifact/plugin inspector contexts with labeled editable or read-only properties and validated supported edits. | 4.4 | US2, US4 |
| FR-007 | Provide project/configuration/device selectors, guarded Run/Stop, measured status, duration and available status metadata. | 3.2, 4.6, 5.2 | US3 |
| FR-008 | Provide timestamped multiline console tabs, severity/text filtering, autoscroll, copy/export/clear, real stages and source navigation; optional tabs require support. | 4.5 | US3 |
| FR-009 | Redact secrets before display, retained diagnostic logs, command previews, clipboard and export; never store raw passwords. | 4.5, 5.1, 10 | US3, US4 |
| FR-010 | Complete the seven-stage onboarding flow including notices, user-supplied SDK, compatibility checks, supported auth and project validation. | 5.1 | US3 |
| FR-011 | Detect selected binary capabilities and structured-event support; use supported commands only and provide safe process lifecycle, cancellation and truthful unknown/error states. | 5.2, 10 | US3 |
| FR-012 | Distinguish connection/readiness checks and actionable recovery; block unsupported target states and support verified reload/restart only when attached. | 5.2, 5.4 | US3, US4 |
| FR-013 | Validate release settings and dependencies, build, verify output, inspect where supported and reveal artifacts; keep publishing separate. | 5.3 | US4 |
| FR-014 | Expose honest preview modes, timestamp screenshot captures, gate refresh/live capabilities and keep preview zoom separate from text scaling. | 4.3 | US4 |
| FR-015 | Provide all 22 X-prefixed component roles and status content rules from section 6, with applicable hover/focus/pressed/disabled/busy/error variants. | 6 | US1–US5 |
| FR-016 | Provide all section 7 shortcuts, custom mappings, OS-conflict handling, visible menu mappings and palette action/file search. | 7 | US5 |
| FR-017 | Keep Workspace default and provide Welcome, Build configurations, Devices, Signing & Accounts, Plugins, Artifacts and Settings without discarding editor state. | 8 | US1–US5 |
| FR-018 | Every failed operation exposes title, actual code/cause when available, useful fix and relevant settings/diagnostic/log actions; no fabricated runtime codes. | 6.1, 8, 13 | US3–US5 |
| FR-019 | Support keyboard focus order, semantic labels, screen readers, text scaling, contrast, reduced motion and phase-5 light theme. | 2, 7, 9, 12 | US5 |
| FR-020 | Provide a labeled component demo gallery and handoff coverage for the eight section-14 states; never use demo data as live results. | 12, 14 | US1, US5 |

## Edge Cases

Invalid/non-Flutter root; inaccessible/read-only/missing file; external edit while dirty; renamed/deleted active file; symlink leaving root; workspace switch during a job; stale device selection; disconnect during install; absent CLI/toolchain; unsupported event version; malformed/mixed output; process exits without done; conflicting exit/done results; cancellation not supported; partial artifact; secret split across output chunks; stale screenshot; corrupt preferences; high text scale; unavailable language server. Recovery must preserve user edits, distinguish unknown from failed and never automatically run a project script or resume authentication/builds.

## Key Entities

Workspace, editor document, selection/inspector context, build configuration, CLI capabilities, operation session, device readiness, preview state, artifact, diagnostic/log entry and shortcut binding. See [data model](data-model.md) for planning contracts.

## Success Criteria

The source's twelve acceptance criteria map one-to-one below. All are required; testing details are in [test plan](test-plan.md). Success is zero failing applicable acceptance checks, with unsupported optional features visibly gated.

| ID | Measurable acceptance outcome |
|---|---|
| AC-029-1 | Default workspace presents the specified navigator/editor/preview/inspector/console hierarchy. |
| AC-029-2 | Every tested supported viewport preserves editor minimum width and core controls through resize/collapse. |
| AC-029-3 | Tree/editor operations use actual fixture files, with saved changes verified on disk. |
| AC-029-4 | Run/Stop/status transitions correspond to recorded backend/session evidence. |
| AC-029-5 | All unknown readiness fixtures display unknown and never a success indication. |
| AC-029-6 | Each available preview mode has its correct label; screenshots include capture time. |
| AC-029-7 | Secret sentinel values are absent from UI, retained logs, copy and export. |
| AC-029-8 | Every unsupported-command fixture disables/hides the affected operation with an explanation. |
| AC-029-9 | Every failure fixture exposes a reason and useful next action where possible. |
| AC-029-10 | Major pane flows are keyboard reachable, visibly focused and screen-reader understandable. |
| AC-029-11 | Required layout/platform checks pass on native Windows and Linux without fake macOS controls. |
| AC-029-12 | Successful IPA creation is described as an artifact, never successful publication. |

## Assumptions and Boundaries

Target native Windows/Linux only; no web/mobile delivery. No Apple asset redistribution or silent project scripts. No new uploader, Git backend, live device streaming or advanced debugger is introduced by this plan. Existing optional functionality may be reused only after capability/evidence checks. Exact visual values remain in the source tables rather than being approximated in this specification. Performance must be profiled during implementation; no unsupported latency promise is inferred.

## Requirements review integration

[Requirements review resolutions](requirements-review.md) R1–R12 are normative clarifications from the 2026-11-06 review. Apply them within the existing tasks and gates. Checklist approval does not complete implementation tasks.
