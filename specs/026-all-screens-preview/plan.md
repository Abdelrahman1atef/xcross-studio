# Implementation Plan: All-screens preview, full splash control, signing status

**Branch**: `026-all-screens-preview` (work lands on `008-json-events-gui`) | **Date**: 2026-11-04 |
**Spec**: [spec.md](spec.md)

## Summary

The CLI reports how the user signed in (`xcross auth status`), draws what each platform really shows, and takes a logo
size per kind of device. The GUI draws device frames and places the CLI's images in them, in each device's own points,
on the App icon page and in the studio. A full-screen iOS splash is researched first ([research.md](research.md)).

## Technical Context

Dart 3.13 in `packages/studio_ext`, `packages/xcross`; Flutter desktop in `apps/studio`. No new dependency. Tests:
`package:test`, `flutter_test`, plus a scratch render with the real CLI (never committed).

## Constitution Check

| Principle | How this holds |
|-----------|----------------|
| I Minimal diff | `SavedSignIn` is new, in `studio_ext`; `auth_command.dart` has a `// studio: 026` seam. The asset fixes in `flutter_assets_compiler.dart` are general fixes, marked and worth proposing upstream |
| II Apple material | The research item decides this before any file is committed: see research.md, Decision 3 |
| III Never skip silently | A package's missing asset warns `build.asset_invalid`; a name clash warns; controls a platform cannot honour say so |
| IV CLI is the product | The GUI only places images and reads saved values through `--json`. The device list is display data |
| V Windows and Linux | Pure Dart and Flutter. New CLI tests run on both hosts; the fixes were hit on Windows paths (`\\?\`) |
| VI Tests | Each `AC-026-n` is in a test name or a `device-check.md` row |
| VII Simplicity | A small `StudioBoard` shares images and actions between tabs, instead of moving both tabs' state up |
| VIII Credentials | `auth status` never holds a token, password or key contents, and a test asserts it |

## Decisions

- **Frames draw in device points**: a `FittedBox` scales a `SizedBox` of the device's size, so an image at its own
  scale has its true size against the screen, and one too big is cut off, as on the device. All frames share one scale,
  so an iPad is larger than a phone by what it really is.
- **Tabs share a board, not state**: each tab keeps its design and preview process and publishes images and actions to
  `StudioBoard`. The gallery is built only while its tab is shown.
- **A splash that follows the icon** starts a second preview process when the studio opens. It idles when nothing
  changes, and the gallery needs both.
- **Only what is saved is shown**: nothing is remembered past sign-out (AC-026-7).
- **The launch image is flattened at build time** (fixed outside this feature), so previews can keep showing the real
  transparent files.

## Project Structure

```text
packages/studio_ext/lib/shared/auth/saved_sign_in.dart       new: the report
packages/studio_ext/lib/shared/splash/splash_command.dart    new options
packages/studio_ext/lib/src/shared/splash/splash_design.dart sizes per device, branding
packages/studio_ext/lib/src/shared/splash/splash_check.dart  splash.branding_clipped
packages/studio_ext/lib/shared/icons/icons_generate_command.dart  preview variants
packages/xcross/lib/src/shared/cli/basic/auth_command.dart   seam: `auth status`
apps/studio/lib/features/icons/device_catalog.dart           new: the screens
apps/studio/lib/features/icons/device_gallery.dart           new: frames, filters, sizes
apps/studio/lib/features/icons/studio_board.dart             new: shared between tabs
apps/studio/lib/features/icons/{studio_panel,splash_panel,icons_page,studio_model,studio_controls}.dart
apps/studio/lib/features/signing/signing_page.dart           status, pre-filled form
apps/studio/lib/src/{cli/xcross_commands,cli/xcross_events,state/readiness}.dart
```

## Contracts

[contracts/cli.md](contracts/cli.md).
