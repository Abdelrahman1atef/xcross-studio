# Feature Specification: App icon and launch screen without a Mac

**Feature Branch**: `004-icon-launch-screen` | **Created**: 2026-11-01 | **Status**: Implemented (device rows pending)

**Input**: ROADMAP 004: "`Assets.xcassets` → `Assets.car` (AssetKit), `CFBundleIcons`, `UILaunchScreen` from
`LaunchScreen.storyboard`"; upstream #149 (assets part). Today `xcross flutter build/run` skips asset catalogs and the
launch storyboard (with the 002 warnings): the app has the blank default icon and an empty launch screen.

## User Story 1 - The app has its icon (P1)

A Flutter developer on Windows or Linux builds their app; the home screen shows the icon from
`ios/Runner/Assets.xcassets/AppIcon.appiconset`, as an Xcode build would.

**Independent Test**: build a project with the Flutter template catalog; the bundle has `Assets.car`, the loose icon
PNGs and the icon keys in Info.plist (`xcross inspect` shows them); on the iPhone the icon shows.

**Acceptance Scenarios**:

1. **AC-004-1** — **Given** an app target with `Assets.xcassets` (app icon set, image sets, colour sets), **When** I
   build, **Then** the bundle has `Assets.car` (CoreUI 970 format), loose icon PNGs named per `CFBundleIconFiles`
   (`AppIcon60x60@2x.png`, `AppIcon76x76@2x~ipad.png`, …) and Info.plist `CFBundleIconName`, `CFBundleIcons`,
   `CFBundleIcons~ipad` and `CFBundleIconFiles`; the icon shows on the home screen (device evidence).
2. **AC-004-5** — **Given** an Xcode 14+ single-size app icon (one 1024-point universal PNG), **When** I build,
   **Then** the iPhone and iPad sizes are generated from it.

## User Story 2 - The app shows its launch screen (P1)

The developer's `LaunchScreen.storyboard` (Flutter's template: an image centred on a background colour, or the shape
`flutter_native_splash` writes) appears while the app starts.

**Acceptance Scenarios**:

1. **AC-004-2** — **Given** the launch storyboard named by `UILaunchStoryboardName` is not compiled (no `ibtool`),
   **When** I build, **Then** Info.plist has `UILaunchScreen` with `UIColorName` (the storyboard's background colour, a
   single-colour full-screen background image, or a colour set it names, compiled into `Assets.car`) and `UIImageName`
   (its centred image, from the catalog), and no `build.storyboard_skipped` warning is printed for it. After deleting
   the app and rebooting (iOS caches launch screens), the splash shows (device evidence).
2. **AC-004-4** — **Given** a storyboard with elements `UILaunchScreen` cannot draw (labels, a second image, a
   multi-colour full-screen image), **When** I build, **Then** `build.launch_screen_approximated` lists them; **Given**
   an unreadable storyboard, **Then** `build.launch_screen_unreadable` is printed and the launch screen stays the empty
   `UILaunchScreen` (today's behaviour).

## User Story 3 - Problems are loud, never fatal (P2)

1. **AC-004-3** — **Given** assets the compiler does not handle (SVG/PDF sources, data sets, symbol sets, system colour
   references, alternate app icons) or broken ones (missing files, bad `Contents.json`, unreadable PNGs), **When** I
   build, **Then** each gets `build.asset_unsupported` or `build.asset_invalid` with a hint, everything else is compiled,
   and the build continues.
2. **AC-004-7** — **Given** the compiler fails unexpectedly, **When** I build, **Then** `build.asset_catalog_skipped`
   names the catalog and the reason, and the build continues as before 004.

## Requirements

- **FR-001**: Compile every `.xcassets` the app target lists into one `Assets.car` in the bundle root (image sets with
  PNG or JPEG at 1x/2x/3x, dark appearance and display-P3; colour sets; the app icon set).
- **FR-002**: Write the app icon's loose PNGs and Info.plist keys as actool does (SpringBoard falls back to the loose
  files).
- **FR-003**: Replace an uncompiled launch storyboard with a `UILaunchScreen` built from it; keep a developer-written
  non-empty `UILaunchScreen`.
- **FR-004**: Unsupported or broken assets produce coded warnings (`build.asset_unsupported`, `build.asset_invalid`,
  `build.launch_screen_approximated`, `build.launch_screen_unreadable`); a compiler failure falls back to
  `build.asset_catalog_skipped`. The build never fails because of assets.
- **FR-005**: Pure Dart, identical on Windows and Linux; no Apple tool or binary is used or shipped.

## Success Criteria

- **SC-001**: The Flutter template app built on Windows shows its icon and its launch image on the iPhone X (iOS 16).
- **SC-002**: `xcross inspect` of the built bundle reports `Assets.car` present, every declared icon resolved and the
  launch image served from the asset catalog.

## Assumptions

- The CAR layout is AssetKit's (xtool-org, MIT), reverse-engineered against actool from Xcode 26 and device-verified
  by its authors on iOS 16+. App Store processing of such catalogs may stall (AssetKit note); store builds still need
  actool.
- Bitmaps are stored as LZFSE *uncompressed* blocks (no compression), so `Assets.car` is larger than actool's.
- `UILaunchScreen` shows one colour and one centred image; richer storyboards are approximated (warned).
