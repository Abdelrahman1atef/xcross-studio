# Feature Specification: All-screens preview, full splash control, signing status

**Feature Branch**: `026-all-screens-preview` (work lands on `008-json-events-gui`) | **Created**: 2026-11-04 |
**Status**: Draft

**Input**: user request (2026-11-04), after testing on an iPhone: "I want the preview to include the app icon and
splash, in preview and in create, and make sure to show all possible sizes of screens, to control everything";
"in signing show the way and the data I used before in the status section". Asked how far control should go, the user
chose to include a full-screen iOS splash, as research first.

"Preview" is the App icon page, which shows what the project holds. "Create" is the Icon and splash studio, which
designs and writes it.

Fixed separately, outside this feature (each with its own tests and commit): asset names with a space or special
character, assets declared by packages, the transparent launch image shown as a black square, and an image set hiding
a colour set of the same name.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See how I signed in (Priority: P1)

A developer opens the Signing page and sees which method and which details are saved, without remembering them or
reading config files, and which of them each kind of build will use. Signing in again starts from those details.

**Independent Test**: with an Apple ID session and a team key saved, `xcross auth status --json` lists both with no
network, and the Signing page shows the same.

**Acceptance Scenarios**:

1. **AC-026-1**: `xcross auth status` prints a report, and with `--json` one object
   `{"v":1,"type":"auth_status","deviceBuilds":…,"appStoreBuilds":…,"appleId":…,"apiKey":…}`. It only reads saved
   files: it works offline and asks Apple nothing. It takes no other option.
2. **AC-026-2**: `appleId` holds `email`, `teamId`, `anisetteUrl`, `expires`, `expired`. `apiKey` holds `keyType`,
   `issuerId`, `keyId`, `privateKeyPath`, `privateKeyFound`. Either is `null` when nothing is saved, or `{"problem":…}`
   when what is saved cannot be read.
3. **AC-026-3**: The output never holds a password, session token or key contents.
4. **AC-026-4**: `deviceBuilds` is what a device build would use: a saved Apple ID session first, even an expired one;
   the key when there is no session or the session cannot be decrypted here; nothing when the session is otherwise
   broken, as signing then stops instead of using a key that may belong to another team. `appStoreBuilds` is the key
   only when it is a team key.
5. **AC-026-5**: The Signing page's Status section shows all of AC-026-2, and which credential device builds and App
   Store builds use. It warns when the session has expired, the `.p8` file is gone, a part cannot be read, or App Store
   builds have no team key.
6. **AC-026-6**: The sign-in form starts on the method device builds use, with the saved details filled in. It never
   overwrites what the user has typed or chosen, and the password is always empty.
7. **AC-026-7**: After sign-out the page shows nothing saved and the form keeps no details.

---

### User Story 2 - See the icon and splash on every screen (Priority: P1)

A developer sees the app icon and splash together, on every screen size the app can run on, both while designing and
for what the project holds, and notices a problem on a small phone or an iPad before installing anything.

**Independent Test**: open the studio's `All screens` tab with a logo: frames for every iPhone, iPad and Android group
appear, each with the splash and icon; switching filters changes them at once.

**Acceptance Scenarios**:

1. **AC-026-8**: The gallery lists every distinct iPhone and iPad screen, by size in points and scale, with the models
   that use it, its safe areas and its cutout. It also lists common Android phones, tablets and foldables by size in dp.
2. **AC-026-9**: Each frame has the device's true proportions, and the logo is at its true size relative to the screen:
   a logo too wide for a small phone looks too wide there.
3. **AC-026-10**: Filters choose the family (iPhone, iPad, Android phone, Android tablet), portrait or landscape, light
   or dark, and splash, home icon or both. Safe area guides can be shown on any frame.
4. **AC-026-11**: A custom width and height adds a frame. A size outside 100–5000 says so and adds nothing.
5. **AC-026-12**: Android frames show what Android draws. Android 11 and older: the logo centred without branding, and
   branding near the bottom as its own image. Android 12 and newer: the icon in its circle, with the branding image if
   there is one. The preview is not the iOS image reused.
6. **AC-026-13**: An "every icon size" section shows each iOS slot and each Android density and launcher shape.
7. **AC-026-14**: In Create, the App icon tab also shows the splash and the Splash tab also shows the icon. An
   `All screens` tab holds the gallery. A new splash starts from the icon's source image until another logo is chosen.
8. **AC-026-15**: `All screens` has one action that writes the icon and splash to the project, and one that exports
   both. Each still reports its own result and backup.
9. **AC-026-16**: In Preview, the App icon page shows the same gallery from the project's files. A project with no
   splash or no icon yet says which is missing and how to make it.
10. **AC-026-17**: A preview request can name the images it needs, and a change still shows within the 0.5 s of 024's
    SC-004, with the gallery open.

---

### User Story 3 - Control everything that can work (Priority: P2)

A developer can set every option from the app, and can size the logo for each kind of device instead of accepting one
size for all.

**Independent Test**: set a different logo size for iPhone, iPad and Android in the studio: each frame family changes,
and the written files match.

**Acceptance Scenarios**:

1. **AC-026-18**: The app offers what only the CLI had: splash `--zip`, all icon targets at once, the user's own badge
   image file, decimal padding, and the full range of each value.
2. **AC-026-19**: `--ipad-logo-width`, `--android-logo-width` and `--android12-icon-width` size the logo for each,
   defaulting to `--logo-width`. An iPad width writes `ipad` images into the image set, so iPhones are unchanged.
3. **AC-026-20**: `--android12-icon-background` and `--dark-android12-icon-background` set Android 12's icon background.
4. **AC-026-21**: `--branding-width` and `--branding-bottom` size and place the branding on Android 11 and older, and
   `--branding-width` sizes it on iOS. A control says when a platform cannot honour it.
5. **AC-026-22**: `splash check` warns with `splash.branding_clipped` when branding would be cut off on a supported
   screen, naming the screen height.
6. **AC-026-23**: All new options are saved to and read from `xcross_assets.json`, and the studio restores them.
7. **AC-026-28**: Padding makes the logo smaller inside its width, keeping its shape, and uneven padding also moves it,
   on iOS and every Android. (Added 2026-11-04, after the user found padding did nothing: it used to add space around a
   centred image, which no screen can show. This replaces the padding part of AC-024-7.)
8. **AC-026-29**: Margin moves the logo by half the difference between opposite sides, on iOS and every Android. Equal
   margins cancel out, so the app shows each side and never one value, and the CLI warns with `splash.margin_no_effect`.
9. **AC-026-30**: `--android12-icon-width` is used as it is, on a canvas of 288 dp through a 192 dp circle, or 240 dp
   through a 160 dp circle with an icon background, as Android documents. What falls outside the circle is masked: the
   frame shows that, and `splash.android12_clipped` reports it, counting only pixels that show. Without that option, the
   general logo width is still kept inside the circle. The app's slider stops at the canvas.
10. **AC-026-31**: The Splash tab shows an iPad as soon as it has its own size, so that control has a visible effect.

---

### User Story 4 - A full-screen iOS splash (Priority: P3)

A developer wants a picture or gradient across the whole iOS launch screen. Today's launch screen is one colour and one
centred image, so this is researched before anything is promised.

**Independent Test**: a test project with the prebuilt launch screen, installed on an iPhone, shows a full-screen
picture with a transparent logo over it, and the same on repeated cold starts.

**Acceptance Scenarios**:

1. **AC-026-24**: `research.md` records whether a launch screen compiled once from one template can serve every app
   without a Mac, including what Constitution II allows, with the device result. No push or CI run happens without the
   user's agreement.
2. **AC-026-25**: Only if AC-026-24 works on a device: `--background-type color|gradient|image` applies to the iOS
   launch screen, and full-screen images larger than about 5 megapixels are refused with a code and a hint.
3. **AC-026-26**: If AC-026-24 does not work, no full-screen option appears for iOS, and the studio says why.
4. **AC-026-27**: Android 12 and newer allow only a colour and an icon, so a full-screen background shows on Android
   11 and older only, and the control says so.

---

### Edge Cases

- `auth status` with no saved sign-in reports both as `null`, exits 0, and the page says "Not signed in".
- A session saved on another computer: reported as a problem; the key, if any, still counts for device builds.
- An older CLI without `auth status`: the Status section shows what it shows today, with no error.
- The two sign-in methods can both be saved: both are shown, each with what it is used for.
- The gallery with no logo yet shows empty frames with the chosen colours, and says to pick a logo.
- A landscape frame on a phone: the launch image stays centred; nothing is rotated in the file.
- Custom size: portrait and landscape come from the numbers given, and the orientation filter does not swap them.
- Android has no complete device list; the custom size covers what the list leaves out.
- A device released after this list is written: a custom size shows it until the list is updated.
- An option a platform cannot honour is disabled there with the reason, not silently ignored (Constitution III).
- Writing both from `All screens` when one fails: the other's result still shows, and nothing is reported as done that
  was not.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The CLI owns reading credentials, composing images and writing files. The GUI runs the CLI and draws
  frames; it imports no `@internal` code (Constitution IV). The device list is display data and lives in the GUI.
- **FR-002**: Credentials are never written to the output, logs or screen beyond the identifiers in AC-026-2
  (Constitution VIII).
- **FR-003**: Everything unsupported on a platform warns or is disabled with a reason and, in the CLI, a stable code
  (Constitution III).
- **FR-004**: New CLI behaviour lives in `packages/studio_ext`; upstream files change only at `// studio: 026` seams
  (Constitution I).
- **FR-005**: Existing commands, options and files keep working, and old `xcross_assets.json` files still load.
- **FR-006**: The gallery follows the design system (`docs/XCross_Studio_Design_System.md`).

### Key Entities

- **Saved sign-in**: the identifiers of the saved Apple ID session and API key, and what each kind of build uses.
- **Device screen**: name, family, size, scale, safe areas, corner radius, cutout, models.
- **Gallery content**: the images and colours of the icon and splash, from a live design or the project's files.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer can tell how they signed in, and what each kind of build uses, in under 5 seconds on the
  Signing page, with no network.
- **SC-002**: A problem specific to a small phone or an iPad is visible in the gallery without installing the app.
- **SC-003**: With the gallery open, a design change shows in under 0.5 s.
- **SC-004**: Every splash and icon option the CLI has can be set from the app.
- **SC-005**: What the frames show matches the installed app on the devices in `device-check.md`.

## Assumptions

- The gallery covers iPhones and iPads that run a supported iOS, checked against Apple's published tables when written.
- Frames are mockups: cutout shapes are close, not exact, and are labelled by size and models.
- Only what is saved now is shown. Sign-out deletes it, so nothing is remembered after that (AC-026-7).
- Colour and centred-image launch screens keep working as they do. US4 only adds to them, if it works at all.
- The transparent launch image fix is at build time, so the project's files stay transparent for previews and Android.
