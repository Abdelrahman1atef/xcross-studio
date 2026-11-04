# Tasks: Icon and splash studio

**Input**: [spec.md](spec.md), [plan.md](plan.md), [contracts/cli.md](contracts/cli.md)

## Phase 1: Foundation

- [ ] T001 Design model and option parsing in packages/studio_ext/lib/src/shared/icons/icon_design.dart
- [ ] T002 Composer with its tests in packages/studio_ext/lib/src/shared/icons/icon_composer.dart
- [ ] T003 [P] Drawn textures in packages/studio_ext/lib/src/shared/icons/icon_textures.dart

## Phase 2: User Story 1 - Design (P1)

- [ ] T004 [US1] Trim, per-side padding, foreground, effects, background types, texture, badge in the composer
- [ ] T005 [US1] Options on `icons generate` in packages/studio_ext/lib/shared/icons/icons_command.dart
- [ ] T006 [US1] Look at generated images for every effect, background and texture

## Phase 3: User Story 3 - Android and notification (P1)

- [ ] T007 [US3] Android and notification tables in packages/studio_ext/lib/src/shared/icons/icon_targets.dart
- [ ] T008 [US3] Shapes, adaptive layers, themed layer, notification silhouette, with size tests

## Phase 4: User Story 4 - Other targets (P2)

- [ ] T009 [P] [US4] Web, macOS, watchOS, tvOS and banner tables in packages/studio_ext/lib/src/shared/icons/icon_targets.dart
- [ ] T010 [US4] Backups, `--targets`, `--zip`, manifest update in packages/studio_ext/lib/shared/icons/icons_command.dart

## Phase 5: User Story 2 - Splash (P1)

- [ ] T011 [US2] Logo canvas and files in packages/studio_ext/lib/src/shared/splash/splash_design.dart
- [ ] T012 [US2] Storyboard read back through LaunchStoryboard.parse in packages/studio_ext/test/shared/splash/splash_test.dart
- [ ] T013 [US2] `xcross splash generate|check` in packages/studio_ext/lib/shared/splash/splash_command.dart, registered in the runner

## Phase 6: Saved settings and preview

- [ ] T014 `--config` and `--save-config` for icons and splash (AC-024-20) in packages/studio_ext/lib/src/shared/icons/icon_design.dart
- [ ] T015 `icons preview --serve` in packages/studio_ext/lib/shared/icons/icons_command.dart

## Phase 7: User Story 5 - Desktop app (P1)

- [ ] T016 [US5] Commands and events in apps/studio/lib/src/cli/xcross_commands.dart
- [ ] T017 [US5] Source rendering and clipart in apps/studio/lib/features/icons/source_render.dart
- [ ] T018 [US5] Design controls in apps/studio/lib/features/icons/studio_panel.dart
- [ ] T019 [US5] Target strip and device previews in apps/studio/lib/features/icons/target_previews.dart
- [ ] T020 [US5] Splash tab in apps/studio/lib/features/icons/splash_panel.dart
- [ ] T021 [US5] Widget tests in apps/studio/test/ui/icons_test.dart

## Phase 8: Polish

- [ ] T022 CHANGELOG, README and specs/024-icon-splash-studio/device-check.md
- [ ] T023 Device check on a test project (AC-024-21)
