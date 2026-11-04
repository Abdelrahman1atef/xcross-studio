# Tasks: All-screens preview, full splash control, signing status

**Input**: [spec.md](spec.md), [plan.md](plan.md), [contracts/cli.md](contracts/cli.md)

## Phase 1: User Story 1 - See how I signed in (P1)

- [X] T001 Report in packages/studio_ext/lib/shared/auth/saved_sign_in.dart (AC-026-1…4)
- [X] T002 `auth status` seam in packages/xcross/lib/src/shared/cli/basic/auth_command.dart
- [X] T003 Tests in packages/xcross/test/cli/auth_status_test.dart
- [X] T004 `AuthStatusReport`, `XcrossCommands.authStatus`, `ReadinessController.readSavedSignIn`
- [X] T005 Status section and pre-filled form in apps/studio/lib/features/signing/signing_page.dart (AC-026-5…7)
- [X] T006 Tests in apps/studio/test/ui/signing_status_test.dart

## Phase 2: User Story 2 - See the icon and splash on every screen (P1)

- [X] T007 Screens in apps/studio/lib/features/icons/device_catalog.dart, sizes checked on 2026-11-04 (AC-026-8)
- [X] T008 Frames, filters, custom size, icon sizes in device_gallery.dart (AC-026-9…13)
- [X] T009 Preview variants in icons_generate_command.dart (AC-026-12, AC-026-17)
- [X] T010 `StudioBoard`, `All screens` tab, write and export both, logo follows the icon (AC-026-14, AC-026-15)
- [X] T011 Splash tab draws real frames, not the iOS image for Android (AC-026-12)
- [X] T012 Gallery on the App icon page from the project's files (AC-026-16)
- [X] T013 Tests in apps/studio/test/ui/device_gallery_test.dart and icons_test.dart
- [X] T014 Render with the real CLI on a real project, as images (device-check row 6)

## Phase 3: User Story 3 - Control everything that can work (P2)

- [X] T015 Sizes per device, Android 12 icon background, branding width and height in the CLI (AC-026-19…21, AC-026-23)
- [X] T016 `splash.branding_clipped` (AC-026-22)
- [X] T017 Controls in splash_panel.dart and studio_panel.dart: zip, every target, badge image, decimals, ranges
      (AC-026-18…21, AC-026-23)
- [X] T018 Tests in packages/studio_ext/test/shared/splash/splash_test.dart and icons_test.dart

- [X] T026 Padding and margin show on every platform, Android 12's size is used as chosen, and the iPad shows on the
      Splash tab, after the user found they did nothing (AC-026-28…31)

## Phase 4: User Story 4 - A full-screen iOS splash (P3), research first

- [X] T019 research.md, with what Constitution II allows (AC-026-24, in part)
- [ ] T020 The user agrees to a push and CI run for the template
- [ ] T021 Compile the template on a macOS runner and inspect the output
- [ ] T022 Test on the iPhone: device-check row 13
- [ ] T023 Then AC-026-25 and AC-026-27, or AC-026-26

## Phase 5: Finish

- [X] T024 `CHANGELOG.md`, `README.md`
- [ ] T025 Device checks: device-check.md rows 1–4, 7–12 (the user's iPhone and devices)
