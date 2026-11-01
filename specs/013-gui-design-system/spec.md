# Feature Specification: XCross Studio design system ("XCross Forge") for the desktop app

**Feature Branch**: `013-gui-design-system` | **Created**: 2026-11-01 | **Status**: Implemented (phases 1–2; most of 3–4)

**Input**: the user asked: "i want change in design system of the desktop use this file". The file is
[docs/XCross_Studio_Design_System.md](../../docs/XCross_Studio_Design_System.md), cited below as "the doc".

## User Story 1 - A purpose-built developer workspace (P1)

A Flutter developer opens XCross Studio and immediately sees whether the machine is ready, what to do next, the
project, the iPhone, and the command output, in a calm dark workspace that still shows every CLI command.

**Acceptance Scenarios**:

1. **AC-013-1**: The shell follows the doc's §5: top bar (project, iPhone selector), a sidebar with the 7
   destinations (Overview, Build & Run, Devices, Signing, Logs & Debug, Plugins, Settings), main workspace, a
   collapsible and resizable console dock, and a status bar. Every destination opens.
2. **AC-013-2**: Keyboard: `Ctrl+,` opens Settings, `Ctrl+L` opens Logs & Debug, `Ctrl+J` toggles the console,
   `Ctrl+1…7` open the destinations, and `Ctrl+K` opens a quick-command palette.
3. **AC-013-3**: Below 1100 px the sidebar becomes an icon rail with tooltips, and the top and status bars compact
   without overflow.
4. **AC-013-4**: Readiness (Overview cards: Flutter, Swift, LLVM, Darwin SDK, Authentication, Device; status bar:
   Toolchain, Signing, Device) comes only from real `flutter doctor` `check` events. An area without checks shows
   "Not checked", never a guess. The status bar also shows running tasks and `xcross --version`.
5. **AC-013-5**: The first-run wizard (§7: Environment, Darwin SDK, Authentication, Device, First build; each with
   Retry, Show details and Copy command; required and optional marked) opens on launch while the doctor reports a
   failure, and stays closed once dismissed. It can be opened from Overview, Settings, the top bar and `Ctrl+K`.
6. **AC-013-6**: Overview without a project shows an explanatory empty state with **Open Flutter Project**. The
   recommended action is Fix Setup (checks failed), then Open Project, then Build & Run.
7. **AC-013-7**: Sign out / clear credentials is a destructive action behind a confirmation dialog.
8. **AC-013-8**: Signing explains the Apple ID risks (non-standard sign-in, account lock, a secondary Apple ID is
   recommended, 2FA) and that public anisette servers are third parties. It shows the anisette URL the CLI will
   use (field, `XCROSS_ANISETTE_URL`, or the CLI default from `xcross auth --help`). The API key is presented as
   the preferred credential for supported workflows.
9. **AC-013-9**: The console dock shows the newest or a chosen command with Stop (only while running, since it
   really ends the process tree) and Copy. It collapses, resizes, and remembers its state.
10. **AC-013-10**: Design-system components (`lib/design_system`) import no CLI, state or `dart:io` code; feature
    adapters translate jobs into component models (§13).
11. **AC-013-11**: Tokens are the doc's exact values (§3.1 colours, §3.3 type scale, §3.4 spacing and radii). Every
    text and status colour has at least 4.5:1 contrast on canvas, surface, elevated surface and console (tested).
12. **AC-013-12**: Status badges always pair an icon with text (never colour alone).
13. **AC-013-13**: The build stepper shows only the steps the CLI reported, in waiting, active, passed, failed or
    skipped states.
14. **AC-013-14**: Diagnostic cards show the CLI's stable code only when it printed one, the message, the
    suggested fix, and Copy command / View logs.
15. **AC-013-15**: The command preview masks `--password` values in the view and in copied text.
16. **AC-013-16**: A loading button keeps the operation label ("Signing…") and ignores taps. A disabled button
    explains why in a tooltip.
17. **AC-013-17**: Progress is determinate only with a real fraction from the CLI.
18. Every AC-008 and AC-012 behaviour still holds on the new screens: device list, app info badges, run from
    source, NDJSON steps and artifacts, install from the artifact, doctor checklist, and no xcross package imports.

## Out of scope / deferred

Live Wi-Fi pairing and RSD-tunnel progress (the Devices page runs `xcross tunnel` and explains the admin
requirement); flavors, Dart-define and entrypoint fields; provisioning-profile and expiry status; credential
storage in the OS keychain (xcross owns credentials); a Flutter-semantics audit with a real screen reader; and
reduced-motion settings beyond the console dock.
