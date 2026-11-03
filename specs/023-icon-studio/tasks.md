# Tasks: Icon studio

S = `packages/studio_ext/lib`, G = `apps/studio/lib`.

## Phase 1: Foundation

- [X] T001 S `src/shared/assets/png_codec.dart`: `PngEncoder.encodeOpaque` (8-bit RGB, colour type 2).
- [X] T002 S `src/shared/icons/icon_slots.dart`: slots, roles, `Contents.json` text, `IconSet.read`.
- [X] T003 S `src/shared/icons/icon_analysis.dart`: `IconAnalyzer`, `IconPlacement`, superellipse mask.

## Phase 2: Check (US1)

- [X] T004 [US1] S `src/shared/icons/icon_check.dart`: `IconCheck`, `IconReport` (AC-023-1…4).
- [X] T005 [US1] S `shared/icons/icons_command.dart`: `icons check`; registration in
  `packages/xcross/lib/src/composition/cli/runner.dart`.

## Phase 3: Generate (US2)

- [X] T006 [US2] S `src/shared/icons/icon_generator.dart`: compose, files, backup, write (AC-023-5…7).
- [X] T007 [US2] S `icons generate` in `shared/icons/icons_command.dart`.
- [X] T008 [P] Tests `packages/studio_ext/test/shared/icons/icons_test.dart`.

## Phase 4: App icon page (US3)

- [X] T009 [US3] G events `IconsCheckReport`, `IconsGenerateResult`; commands `iconsCheck`, `iconsGenerate`.
- [X] T010 [US3] G `features/icons/icons_page.dart`: previews, safe-area overlay, slots, issues (AC-023-8, 9).
- [X] T011 [US3] G "Make icon set…" panel (AC-023-10).
- [X] T012 [US3] G `Destination.icons` in `app/app_controller.dart`, `app/shell.dart` (Ctrl+7…9).
- [X] T013 [P] Tests `apps/studio/test/ui/icons_test.dart`; sidebar count in `test/ui/app_test.dart`.

## Phase 5: Evidence and polish

- [X] T014 Rebuild the CLI, run `icons check` and `icons generate --output` on app A (`device-check.md`).
- [X] T015 Analyze, CHANGELOG, README.
