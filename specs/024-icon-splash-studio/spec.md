# Feature Specification: Icon and splash studio

**Feature Branch**: `024-icon-splash-studio` (work lands on `008-json-events-gui`) | **Created**: 2026-11-04 |
**Status**: Draft

**Input**: user request (2026-11-04): "in app icon studio … complete all requirement from it: native splash, the
padding and margin, inspired by all features of these websites" (IconKitchen, appicon.co, Android Asset Studio).
Today the App icon page (feature 023) takes one PNG, one background colour and one margin, and writes only the iOS
set. A Flutter project also needs Android, web and macOS icons, notification icons and a native splash screen, and
today those are made with separate tools, on the web or by hand.

The implementation is original: the sites inform which options exist, and no artwork or code is copied.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Design the icon, not just resize it (Priority: P1)

A developer without a designer starts from a logo, a few letters or a stock symbol, and adjusts it until it looks
right: margins on each side, colours, a shadow, a gradient or textured background, a small badge.

**Independent Test**: `xcross icons generate logo.png --padding 10,14,18,14 --trim --background-type gradient
--background "#0A84FF" --background2 "#5E5CE6" --effect drop-shadow --texture polka --output out`
writes a set whose 1024 px icon shows each option, with no change to the project.

**Acceptance Scenarios**:

1. **AC-024-1**: **Padding** takes one value (all sides), or four (`top,right,bottom,left`), each 0–45% of the side;
   the logo is fitted inside the remaining box. **Trim** (`--trim`) first removes transparent or one-colour borders
   from the source, so padding is measured from the logo itself. The existing `--padding <n>` keeps working.
2. **AC-024-2**: **Foreground**: `--foreground <#RRGGBB>` recolours the logo, keeping its transparency;
   `--effect none|drop-shadow|cast-shadow|score` adds a soft shadow below it, a long diagonal shadow, or a fold
   shading its lower half.
3. **AC-024-3**: **Background**: `--background-type color|gradient|mesh|image`. A gradient takes two colours and an
   angle, a mesh takes four corner colours, an image fills the square (cropped, not stretched). `--texture
   none|argyle|concentric|contour|coral|fabric|halftone|maze|mosaic|polka|stipple|waves` draws a subtle pattern over
   the background and under the logo.
4. **AC-024-4**: **Badge**: `--badge-image <png>` draws a corner ribbon from an image, which the desktop app renders
   from the badge text. **Filename**: `--name <name>` names the Android and notification files (default
   `ic_launcher`).
5. **AC-024-5**: The same options on the same source always give byte-identical files. Icons for platforms that
   reject transparency (iOS App Store, 023) still have no alpha channel.

### User Story 2 - A native splash screen, light and dark (Priority: P1)

The developer sets the splash background and logo, with padding and margin, sees it on a phone, and writes it to the
project. The app opens with that screen on iOS and Android instead of a white flash.

**Independent Test**: `xcross splash generate logo.png --background "#FFFFFF" --dark-background "#101014" --logo-width
140 --output out` writes the iOS and Android files; `xcross splash check` in a project with them passes; an app
built with xcross shows the logo and colour at launch.

**Acceptance Scenarios**:

1. **AC-024-6**: `xcross splash generate <logo.png> [--background <#RRGGBB>] [--dark-background <#RRGGBB>]
   [--dark-logo <png>] [--logo-width <points, default 120>] [--padding <1 or 4 values, % of the logo>] [--margin
   <top,right,bottom,left, points>] [--branding <png>] [--dark-branding <png>] [--platforms ios,android] [--output
   <dir>] [--json] [--project <dir>]`.
2. **AC-024-7**: **iOS**: writes `LaunchImage.imageset` (1x, 2x, 3x, with dark variants) and `LaunchBackground.colorset`
   (light and dark) and a `LaunchScreen.storyboard` showing them. xcross reads that storyboard into its launch
   screen at build time, so the same files work with xcross and with Xcode on a Mac. An uneven margin is part of the
   logo image's transparent canvas, so it moves the logo on every screen size; padding makes the logo smaller
   (AC-026-28 replaced the first meaning, which could not show). A branding image
   is placed near the bottom of the same image, because an iOS launch screen shows one centred image.
3. **AC-024-8**: **Android**: writes `drawable` and `drawable-night` `launch_background.xml` with the logo at five
   densities, and `values-v31` and `values-night-v31` styles using the Android 12 splash attributes (background, icon,
   branding). The older `values` styles are not rewritten (see AC-024-10). The Android 12 icon follows its safe zone: a 288 dp canvas with
   the logo inside the 192 dp circle, reported as `splash.android12_clipped` when a logo at the chosen size would be
   cut.
4. **AC-024-9**: `xcross splash check [--json] [--project <dir>]` reports, per platform, what the app shows at launch
   (colours, logo, sizes, dark variant) and problems: `splash.missing` (no custom splash), `splash.logo_missing`
   (referenced, not there), `splash.logo_too_large` (wider than the smallest supported screen),
   `splash.android12_missing` (older style only), `splash.low_contrast` (logo too close to its background).
5. **AC-024-10**: Only the splash files named above change. The project's `AndroidManifest.xml` and `Info.plist`
   are not edited; when they do not use the splash (a project that removed the template's launch theme or storyboard
   reference), `splash.not_referenced` says what to add.

### User Story 3 - Android icons and notification icons (Priority: P1)

The developer gets the Android launcher icons, the adaptive parts Android masks into any shape, the themed icon, the
Play Store image and notification icons from the same design.

**Independent Test**: `xcross icons generate logo.png --targets android,notification --output out` writes all
densities with correct pixel sizes; the XML names the files it refers to.

**Acceptance Scenarios**:

1. **AC-024-11**: **Android**: `mipmap-mdpi`…`mipmap-xxxhdpi` launcher icons (48–192 px) in the chosen `--shape
   square|squircle|circle`, adaptive foreground and background layers (108–432 px, keeping the logo in the adaptive
   safe zone), `mipmap-anydpi-v26/<name>.xml`, and a 512 px Play Store image.
2. **AC-024-12**: **Themed**: `--themed` adds a monochrome layer and the `<monochrome>` entry, so Android 13+ can tint
   the icon.
3. **AC-024-13**: **Notification**: `drawable-mdpi`…`drawable-xxxhdpi/ic_stat_<name>.png` (24–96 px), white on
   transparent, as Android requires. A source with no transparency uses its one-colour border as the transparent
   part; a source with neither gives `icons.notification_no_shape` rather than a white square.

### User Story 4 - Every other platform, and a download (Priority: P2)

**Acceptance Scenarios**:

1. **AC-024-14**: `--targets` also takes `web` (favicon, 192 and 512 px, maskable 192 and 512 px, and the manifest's
   icon list), `macos` (16–1024 px, Contents.json, the macOS rounded shape with its margin), `watchos` (every case
   size, Contents.json), `tvos` (app icon and top-shelf sizes), `android-tv` (320×180 banner) and `play-banner`
   (1024×500).
2. **AC-024-15**: Default targets: those the project has a folder for (`ios`, `android`, `web`, `macos`). `watchos`,
   `tvos`, `android-tv` and `play-banner` are written only with `--output`, since a Flutter project has no place for
   them. `--zip <file>` writes everything as one archive and touches nothing in the project.
3. **AC-024-16**: Writing into a project first copies every file it replaces to `.xcross/icon-backups/<timestamp>/`,
   for icons and for splash, and prints the path.

### User Story 5 - See it before writing it (Priority: P1)

1. **AC-024-17**: The App icon page has **Source** (Image, Text with font, bold and italic, Clipart with search and
   filled, outline and round styles), **Foreground**, **Padding** (one value with a button that splits it into four),
   **Background**, **Texture**, **Badge**, and **Android** options (filename, shape, themed). The preview follows
   every change.
2. **AC-024-18**: A target strip (iOS, Android, Web, macOS, Notification, and the others from AC-024-14) switches the
   preview to that device: phone home screen, notification, browser tab, Dock. Android shows square, squircle and
   circle.
3. **AC-024-19**: A **Splash** tab has the same kind of controls and previews the launch screen on an iPhone and on an
   Android phone (older and Android 12 styles), light and dark, with safe-zone guides.
4. **AC-024-20**: The settings are saved in `xcross_assets.json` in the project, and reloaded when it is opened, so a
   team can commit them and regenerate later: `xcross icons generate --config` and `xcross splash generate --config`
   take the same file, and "Copy command" shows the command for the current settings.
5. **AC-024-21** (device, `device-check.md`): on a test project, generate icons and splash, build and install; the
   home-screen icon and the launch screen match the preview, light and dark. Existing projects are changed only when
   the user asks.

### Edge Cases

- No project open: the page still designs and exports with `--output`, and "Write to project" is disabled.
- A source that is not a readable PNG stops with `icons.source_unreadable`; JPEG and other formats are converted by
  the desktop app before the command runs.
- Text or clipart with transparent padding: Trim applies to it like any image.
- A padding that leaves no room (left + right ≥ 100%) is a usage error, not a tiny logo.
- A project with a hand-written `LaunchScreen.storyboard` is replaced only after the backup, and the command says so.
- A target folder missing from the project (no `android/`): the target is skipped with a note, or an error if named
  explicitly in `--targets`.
- A `flutter_native_splash` setup in `pubspec.yaml`: `splash.other_tool` warns that running it again will overwrite
  these files.
- An older CLI without these options: the job's error is shown as is.

## Requirements *(mandatory)*

- **FR-001**: All image composition and file writing is in the CLI; the desktop app only renders text and clipart into
  a source PNG, shows previews and starts `xcross` commands (Constitution IV).
- **FR-002**: Commands with `--output` or `--zip` change nothing in the project; commands writing into it back up first.
- **FR-003**: Every generated PNG has the exact pixel size its target requires; targets that reject transparency get
  none, and notification icons and adaptive foregrounds keep it.
- **FR-004**: Every problem has a stable code and a fix hint (Constitution III); JSON output is versioned like the
  other commands.
- **FR-005**: No third-party artwork is bundled except symbols from the Material icon set that already ships with
  Flutter under its open licence; textures are drawn by code.
- **FR-006**: The `xcross icons check` behaviour of feature 023 is unchanged; 023's `generate` options keep working.
- **FR-007**: Windows and Linux behave the same (Constitution V).

### Key Entities

- **Icon design**: source, trim, padding, foreground, effect, background, texture, badge, Android options.
- **Target**: a platform's list of files with exact sizes and shape rules.
- **Splash design**: colours, logo and dark logo, width, padding, margin, branding.
- **Assets file** (`xcross_assets.json`): the saved designs, with paths relative to the project.

## Success Criteria *(mandatory)*

- **SC-001**: From one logo to icons for iOS, Android and web plus a light and dark splash, written and checked, in
  under five minutes without an image editor or a website.
- **SC-002**: Every generated file has the size its platform requires, verified automatically for all targets.
- **SC-003**: What the preview shows matches the installed app's icon and launch screen (checked on one iPhone).
- **SC-004**: Changing a control updates the preview in under half a second on a typical laptop.
- **SC-005**: Regenerating from the saved settings gives byte-identical files.

## Assumptions

- This replaces 023's assumption that Android is out of scope. xcross still builds iOS only; Android, web and macOS
  files are written for `flutter build` on those platforms, and are checked by size and structure, not by building.
- An iOS launch screen shows one centred image and one colour, so padding, margin and branding are baked into that
  image. iPhones of different heights place a branding image slightly differently; it stays above the home indicator
  on the supported sizes.
- Clipart is a curated, searchable set of common symbols rather than the whole Material catalogue.
- Text uses the fonts on the user's machine or a picked font file; the source PNG, not the font, is what the assets
  file records, so regeneration does not depend on the machine.
- Sharing is through the committed `xcross_assets.json`, not a web link.
- The sites' AI generation and share links are out of scope.
