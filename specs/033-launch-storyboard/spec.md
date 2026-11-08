# Feature Specification: a compiled launch storyboard instead of `UILaunchScreen`

**Feature Branch**: `033-launch-storyboard` (work lands on `codex/029-xcode-ide-workspace`) | **Created**: 2026-11-08 | **Status**: Implemented, not yet seen on a device

**Input**: An app built with xcross showed its launch logo stretched over the whole screen on an iPhone X installed from
TestFlight, on every open and after a restart (2026-11-08, build 1.0.12 (1)). The same app installed straight from xcross
looked right. The build already held a launch image drawn on a screen-shaped canvas (feature 004), and a photo of the
launch showed a square logo, not the canvas, stretched to the screen. Apple's forums describe the same problem for
`UILaunchScreen` images. Xcode's own apps do not use that path: they ship `LaunchScreen.storyboardc` and name it in
`UILaunchStoryboardName`.

## Scope

- xcross compiles the project's `LaunchScreen.storyboard` itself, without a Mac, when it only holds one background colour and
  at most one image view (centred or any non-filling mode). The compiler is a port of upstream xcross' `storyboardc` writer
  (its `Info.plist` is byte for byte what Interface Builder writes).
- The bundle gets `<Name>.storyboardc/` at its root; Info.plist keeps `UILaunchStoryboardName` and gets no `UILaunchScreen`.
- The image is not read from `Assets.car`: its PNGs are copied to the bundle root as `XCrossLaunchLogo[@2x|@3x][~ipad].png` and
  the storyboard loads that name, so the launch screen does not depend on how Apple slices the catalog.
- A storyboard that needs more (labels, several images, a full-screen image, a colour that differs in dark mode, Display P3)
  keeps today's `UILaunchScreen` path with its warnings.
- `XCROSS_LAUNCH_STORYBOARD=off` forces the old path.

## Acceptance Scenarios

1. **AC-033-1** The ported compiler writes the three files Interface Builder writes (two nibs and `Info.plist`), substitutes the
   colour and image name, encodes the content mode, and refuses a content mode it does not know.
2. **AC-033-2** (build step) A colour and a centred image become `LaunchScreen.storyboardc` plus loose logo PNGs; no
   `UILaunchScreen`; `UILaunchStoryboardName` stays.
3. **AC-033-3** A storyboard with something a storyboard of this kind cannot hold keeps the `UILaunchScreen` and writes no
   `storyboardc`.
4. **AC-033-4** `XCROSS_LAUNCH_STORYBOARD=off` keeps the `UILaunchScreen`.

## Tests

`packages/studio_ext/test/shared/launch_storyboard/launch_storyboard_compiler_test.dart` and
`packages/xcross/test/flutter/build/flutter_asset_catalogs_test.dart`.

## Not checked

Nothing here was seen on a phone. A `.storyboardc` that iOS cannot read would show a blank launch screen, and the Flutter
engine also loads the named storyboard until its first frame, so a bad file could stop the app from starting. Check on an
iPhone from TestFlight: the first open and a reopen, light and dark, and record the result here. If the app does not start,
set `XCROSS_LAUNCH_STORYBOARD=off` and tell me. A Display P3 or dark-mode-specific colour was not compiled (fallback).
