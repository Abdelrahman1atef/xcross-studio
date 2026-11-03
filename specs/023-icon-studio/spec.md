# Feature Specification: Icon studio

**Feature Branch**: `023-icon-studio` (work lands on `008-json-events-gui`) | **Created**: 2026-11-03 |
**Status**: Draft

**Input**: user request (2026-11-03): "add icon app studio to make all related to app from icons like app icon and
notification … to make sure the app icon is placed perfectly". The 018 release check found a real problem in app A
(the 1024 px App Store icon has an alpha channel, which App Store Connect rejects with ITMS-90717); today nothing
shows how an icon will look once iOS masks it, whether every size is there, or whether the logo sits well inside the
rounded corners. On iOS the notification icon is the app icon at 20 pt, so the same set covers notifications.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Know the icon is right before a build (Priority: P1)

A Flutter developer opens the App icon page (or runs `xcross icons check`) and sees every size iOS uses, with its
place on the device (notification, Settings, Spotlight, home screen, iPad, App Store), whether it is there at the
right pixel size, and what would be rejected or look wrong.

**Independent Test**: run `xcross icons check` in a project whose 1024 px icon has an alpha channel and is missing
one size; both are reported, the command exits 1.

**Acceptance Scenarios**:

1. **AC-023-1**: `xcross icons check [--json] [--project <dir>]` finds the app icon set
   (`ios/Runner/Assets.xcassets/AppIcon.appiconset`, else the first `.appiconset`) and lists every slot of the
   Flutter template set (iPhone 20/29/40/60 pt, iPad 20/29/40/76/83.5 pt, App Store 1024 px) with its role, point
   size, scale, expected pixels, file and status: `ok`, `missing`, `wrong_size` (with the actual size) or
   `unreadable`. A single-size set (one universal 1024 px image, Xcode 14+) is reported as such: every size is made
   from that image.
2. **AC-023-2**: errors (exit 1): no icon set or unreadable `Contents.json` (`icons.no_set`,
   `icons.contents_invalid`); a missing home screen or App Store slot (`icons.missing`); a file of the wrong size
   (`icons.wrong_size`); a file that is not a readable PNG (`icons.unreadable`); an App Store icon with an alpha
   channel (`icons.alpha`). Warnings: other missing sizes (iOS scales another one) and transparency in other
   sizes (transparent pixels show black).
3. **AC-023-3**: placement, measured on the 1024 px icon: when its border is one colour, the logo's box, its offset
   from the centre and the share of the logo outside the iOS corner mask are reported; warnings for a logo the
   rounded corners cut (`icons.clipped`), a logo off centre by more than 3% (`icons.off_center`, with the pixel
   offset and direction), a logo filling less than 45% of the width and height (`icons.logo_small`), and an icon
   exported with its own rounded or transparent corners (`icons.prerounded`). Full-bleed artwork (no one-colour
   border) is reported as such and not measured.
4. **AC-023-4**: JSON: one `{"v":1,"type":"icons_check",…}` object with `set`, `path`, `style`, `slots`,
   `placement`, `issues`, `errors`, `warnings` (contract in `contracts/cli.md`).

### User Story 2 - Make a perfect icon set from one image (Priority: P1)

The developer picks one square image (their logo or the designer's 1024 px icon), chooses the background colour and
the margin around the logo, previews it as iOS will show it, and writes the whole set.

**Independent Test**: `xcross icons generate logo.png --padding 12 --background "#0A84FF"` in a project; the set has
every slot at the right size, no PNG has an alpha channel, the old set is backed up, and `icons check` passes.

**Acceptance Scenarios**:

1. **AC-023-5**: `xcross icons generate <image.png> [--background auto|#RRGGBB] [--padding <0–30>]
   [--output <dir>] [--json] [--project <dir>]` composes a 1024 px master: the image fitted (aspect kept) and
   centred inside the margin, over the background (`auto`: the image's own border colour when it is one opaque
   colour, else white); transparency is flattened onto the background, so no file has an alpha channel. It writes
   every slot of the Flutter template set (`Icon-App-<size>@<scale>x.png`) and its `Contents.json`.
2. **AC-023-6**: writing into the project first copies the current set to
   `.xcross/icon-backups/<yyyyMMdd-HHmmss>/<set>.appiconset` and prints the path; `--output <dir>` writes the set
   there instead and touches nothing in the project (the desktop app uses it for previews). A non-PNG or unreadable
   source stops with `icons.source_unreadable`; a source smaller than 1024 px is used with an `icons.upscaled`
   warning; a non-square source is centred on the background.
3. **AC-023-7**: after writing, the result of `icons check` on the new set is printed (JSON: `icons_generate` with
   `written`, `backup`, `background`, `padding` and the `check` object).

### User Story 3 - See it as iOS shows it (Priority: P1)

1. **AC-023-8**: an **App icon** destination in XCross Studio shows the set's icon masked as iOS masks it, on the
   home screen (light and dark wallpaper, with the app name), in a notification banner, in Settings, in Spotlight
   and on the App Store; a "Safe area" switch draws the corner mask outline, the centre guides and the measured logo
   box over a large preview.
2. **AC-023-9**: the page lists every slot (image, role, size, status) and the check's issues with their hints,
   errors first; "Check again" runs `xcross icons check --json`.
3. **AC-023-10**: "Make icon set…" opens a panel: pick a PNG, background (Auto, a colour field, swatches), margin
   slider (0–30%), live preview in the same mask; "Write icon set" runs `xcross icons generate … --json`, shows its
   job, then refreshes the page and names the backup.
4. **AC-023-11** (device, `device-check.md`): on app A, generate a set from its own 1024 px icon, build, install;
   the home-screen icon, the Settings row and a notification banner show it; `release check` reports no
   `release.marketing_icon` error.

### Edge Cases

- No project open: the page says "Open a Flutter project".
- An icon set with dark or tinted variants (iOS 18): reported as info; `generate` writes the default appearance only
  and says the variants were left in the backup.
- An older CLI without `icons`: the job's error is shown as is.

## Requirements *(mandatory)*

- **FR-001**: The checks read only the project's files; `generate` writes only the icon set (after the backup) or the
  `--output` folder.
- **FR-002**: The desktop app starts only `xcross` commands and reads the icon files only to display them
  (Constitution IV).
- **FR-003**: Generated PNGs are 8-bit RGB without an alpha channel, at the exact pixel size of their slot.

## Success Criteria *(mandatory)*

- **SC-001**: A developer can go from one logo image to a complete icon set that passes `icons check` and `release
  check`'s icon rule in under two minutes, without an image editor.
- **SC-002**: Every icon problem App Store Connect rejects (alpha channel, wrong or missing App Store icon) is shown
  before the build.

## Assumptions

- The iOS icon mask is approximated by a superellipse (exponent 5), which matches the rounded-corner shape to within
  a pixel at 1024 px; it is used to measure placement, not to cut the files (iOS masks them itself).
- Android launcher and notification icons are out of scope: xcross builds iOS apps (on iOS the notification shows
  the app icon).
- Sources are PNG; JPEG and SVG are not decoded (the existing asset code reads JPEG dimensions only).
