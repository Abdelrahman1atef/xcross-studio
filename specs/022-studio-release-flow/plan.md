# Implementation Plan: XCross Studio release flow

**Branch**: `022-studio-release-flow` (on `008-json-events-gui`) | **Date**: 2026-11-03 | **Spec**: [spec.md](spec.md)

## Summary

S = `packages/studio_ext/lib`, G = `apps/studio/lib`.

- **S** `shared/release/release_gate_command.dart` (new): `release gate` with an injected `flutter` resolver and
  process runner. `ReleaseCiCommand` (same file) + `src/shared/release/ci_template.dart` (new): `release
  ci` and the workflow text (also written to `docs/ci/github-testflight.yml`). Both are added to `ReleaseCommand`;
  `packages/xcross/lib/src/composition/cli/runner.dart` passes the resolver (`// studio: 022`).
- **G** `features/release/release_page.dart` (new): the ten steps, each a card with a status badge, the command
  preview and its job console; parsing of `release_check`, `publish`, `testflight_status`, `appstore_status`,
  `release_gate` events in `src/cli/xcross_events.dart`; commands in `src/cli/xcross_commands.dart`.
- **G** `features/release/archives_page.dart` (new): reads `*.xcarchive/Info.plist` (XML) for display.
- **G** `app/app_controller.dart` / `app/shell.dart`: destinations `release` and `archives` (after Plugins).

## Constitution Check

I new files + small seams · II the CI template downloads only the user's own `.xip` URL · III gate failures are
shown with the tool's output · IV the GUI runs only `xcross` · V no OS branching (flutter path from the resolver)
· VI AC-named tests · VII no new dependency · VIII secrets stay GitHub secrets. No violations.

## Tests

`packages/studio_ext/test/shared/release/release_gate_test.dart` (AC-022-5, 6), `apps/studio/test/ui/release_test.dart`
(AC-022-1…4, 7).
