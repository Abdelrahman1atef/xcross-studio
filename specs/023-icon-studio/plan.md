# Implementation Plan: Icon studio

**Branch**: `023-icon-studio` (on `008-json-events-gui`) | **Date**: 2026-11-03 | **Spec**: [spec.md](spec.md)

## Summary

S = `packages/studio_ext/lib`, G = `apps/studio/lib`. Reuses the 004 asset code (`PngDecoder`, `RgbaImage.resized`,
`PngEncoder`): no new dependency.

- **S** `src/shared/icons/icon_slots.dart` (new): the Flutter template slots (role, idiom, points, scale, file
  name), `Contents.json` writing and reading (`IconSet.read`).
- **S** `src/shared/icons/icon_analysis.dart` (new): `IconAnalyzer.analyze(RgbaImage)` → `IconPlacement`
  (background, logo box, centre offset, share outside the superellipse mask, pre-rounded corners, transparency).
- **S** `src/shared/icons/icon_check.dart` (new): `IconCheck.run(project)` → `IconReport` (slots, placement,
  issues, JSON, text rendering).
- **S** `src/shared/icons/icon_generator.dart` (new): `IconGenerator.compose` (master), `files`, backup and write.
- **S** `src/shared/assets/png_codec.dart`: `PngEncoder.encodeOpaque` (colour type 2) (`// studio: 023`).
- **S** `shared/icons/icons_command.dart` (new): `xcross icons check|generate`; registered in
  `packages/xcross/lib/src/composition/cli/runner.dart` (`// studio: 023`).
- **G** `features/icons/icons_page.dart` (new): previews (home, notification, Settings, Spotlight, App Store),
  safe-area overlay, slot grid, issues, "Make icon set…" panel; `IconsCheckReport` / `IconsGenerateResult` events
  in `src/cli/xcross_events.dart`; commands in `src/cli/xcross_commands.dart`; `Destination.icons` (after Plugins,
  Ctrl+7; Release Ctrl+8, Archives Ctrl+9).

## Research

- **Mask**: iOS app icons use a continuous-corner rounded rectangle (radius ≈ 22.4% of the side). A superellipse
  |x|⁵ + |y|⁵ ≤ 1 cuts the diagonal at 6.5% of the side, the same as that shape (6.55%); measurement only.
  Alternatives: a plain rounded rectangle (cuts less at the diagonal), Apple's exact path (not published).
- **Background**: the most frequent colour of the border ring (outside the corners), at ≥ 85% of the ring; below
  that the icon is full-bleed artwork and placement is not measured.
- **Analysis size**: 256 px (box-filter downscale of the 1024 px master): fast and accurate to 4 px at 1024.
- **Backups**: `.xcross/icon-backups/` in the project, not `build/` (`flutter clean` deletes it).
- **Preview in the GUI**: Flutter's `RoundedSuperellipseBorder` draws the iOS shape; the live preview of the
  "Make icon set" panel composes the image in Flutter, the written files come from the CLI.

## Constitution Check

I new files + two seams · II no Apple material · III every problem is a coded issue with a hint, nothing fatal
except a missing source · IV the GUI runs only `xcross` · V no OS branching · VI AC-named tests · VII no new
dependency · VIII no secrets involved. No violations.

## Tests

`packages/studio_ext/test/shared/icons/icons_test.dart` (AC-023-1…7), `apps/studio/test/ui/icons_test.dart`
(AC-023-8…10).
