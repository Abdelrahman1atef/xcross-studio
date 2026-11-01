# Feature Specification: iOS 16 install and launch, and `xcross install` for any app

**Feature Branch**: `005-ios16-install-launch`

**Created**: 2026-11-01

**Status**: Draft

**Input**: ROADMAP 005: "Install/launch/run on iOS < 17 via installation_proxy + user's DDI + dvt launch;
`xcross install <any.ipa>` for any device (Sideloadly replacement, part 2)". Upstream #147.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run my app on an iOS 16 iPhone (Priority: P1)

A developer with an iPhone X (iOS 16) runs `xcross flutter run --release`. Today xcross refuses: it requires iOS 17. They
want the app signed, installed and opened, or at least installed with clear guidance.

**Independent Test**: run `xcross flutter run --release` against an iOS 16 device. The app is installed; it is
launched when a developer disk image is available, otherwise the tool says "tap the icon".

**Acceptance Scenarios**:

1. **AC-005-1** — **Given** an iOS 15/16 device, **When** I run `xcross flutter run --release` or `--profile`,
   **Then** the precheck accepts the device, the app is built, signed and installed over USB, with no tunnel and no
   elevation.
2. **AC-005-2** — **Given** an iOS 16 device and a developer disk image for that iOS version (`--ddi <dir>`, or
   `XCROSS_DDI_DIR`, or `~/.xcross/DeviceSupport/<major.minor>/` containing `DeveloperDiskImage.dmg` +
   `.signature`), **When** the app is installed, **Then** xcross mounts the image (never downloading one) and launches
   the app.
3. **AC-005-3** — **Given** no image is available, **When** the app is installed, **Then** xcross prints that the app
   is installed, asks to tap its icon, and shows `xcross logs --app <id>` to watch it; the command succeeds.
4. **AC-005-4** — **Given** an iOS 16 device and a debug (JIT) build, **When** I run `xcross flutter run`, **Then** it
   stops before building with `device.legacy_debug_unsupported` and suggests `--release` or `--profile`.

### User Story 2 - Install any app like Sideloadly (Priority: P1)

A developer has an `.ipa` (built by xcross or anyone) and wants it on their iPhone, signed with their own Apple ID.

**Independent Test**: `xcross install app.ipa` signs and installs it; the app appears on the phone.

**Acceptance Scenarios**:

1. **AC-005-5** — **Given** an `.ipa` or `.app`, **When** I run `xcross install <path>`, **Then** the bundle is
   extracted (`.ipa`), re-signed with the saved Apple ID or App Store Connect key, installed over USB on iOS 15+, and
   launched as in US1.
2. **AC-005-6** — **Given** an input that is not an `.ipa`/`.app` or has no app inside, **When** I run
   `xcross install`, **Then** it stops with a stable code (`install.unsupported_input`, `install.no_app`) before
   contacting the device.

### Edge Cases

- A developer image is already mounted → treat as success.
- Mounting fails (wrong image for the iOS version) → install still succeeds; warn with the mount error and fall back
  to "tap the icon".
- iOS 17+ → unchanged behaviour (CoreDevice launch, hot reload).
- iOS < 15 → `device.ios_unsupported` with the new minimum.

## Requirements *(mandatory)*

- **FR-001**: The device precheck MUST accept iOS 15 and 16 ("legacy") as well as 17+.
- **FR-002**: Legacy devices MUST install over plain usbmux (installation_proxy).
- **FR-003**: Legacy launch MUST use only a user-supplied developer disk image, found in this order: `--ddi`,
  `XCROSS_DDI_DIR`, `~/.xcross/DeviceSupport/<major.minor>` then `<major>`. It MUST NOT download images.
- **FR-004**: Without an image, the command MUST still succeed after install, with tap-to-open guidance.
- **FR-005**: Debug (JIT) runs on legacy devices MUST fail before the build with `device.legacy_debug_unsupported`.
- **FR-006**: `xcross install <ipa|app>` MUST sign and install any app bundle through the existing signing pipeline,
  and accept `--udid`, `--ddi` and `--no-launch`.

## Success Criteria *(mandatory)*

- **SC-001**: On an iPhone X (iOS 16.7), `xcross flutter run --release` ends with the app installed and either
  launched or "tap the icon", with no admin rights.
- **SC-002**: `xcross install <ipa>` installs a third-party IPA signed with the user's Apple ID.

## Assumptions

- Signing uses the existing Apple ID / App Store Connect flow (`xcross auth`); free accounts get the existing
  team-qualified bundle id.
- Hot reload on iOS 16 (debugger attach) is out of scope; feature 009 may revisit it.
- Newer Xcode versions may not contain iOS 16 disk images; users with an older Xcode can copy `DeviceSupport/16.x`.
