# Feature Specification: Quick wins — fail fast, correct versions, PATH guard, loud warnings

**Feature Branch**: `002-quick-wins`

**Created**: 2026-11-01

**Status**: Draft

**Input**: User description: "002-quick-wins: Quick wins for milestone M1 (upstream issues #145 warning part, #147
fail-fast, #148). (1) Check the target device's iOS version and the host device service BEFORE the long build in
`xcross flutter run`, so an unsupported device fails in under 5 seconds with a stable error code and fix hint.
(2) Resolve CFBundleShortVersionString/CFBundleVersion in the order --build-name/--build-number > pubspec.yaml version >
ios/Flutter xcconfig > project.pbxproj, so the IPA version matches pubspec instead of a stale Generated.xcconfig.
(3) PATH guard: when XCROSS_CONFIG environment.PATH points at a Swift toolchain whose bundled LLD cannot link iOS,
warn (doctor + before build) and still link with the system clang/lld instead of failing native-asset linking.
(4) Loud warnings with stable codes and fix hints, instead of silent skips, for CocoaPods-only plugins, skipped
.xcassets asset catalogs and uncompiled storyboards. Windows and Linux equal hosts; changes at small documented
upstream seams; generally useful fixes are upstreamable."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Find out in seconds that my iPhone can't be used (Priority: P1)

A developer runs `xcross flutter run` with an iPhone that the tool cannot deploy to (for example an iPhone X on
iOS 16), with no device attached, or with the host's device service stopped. Today they wait through a full build
(often several minutes) and only then learn the device is unusable. They want the answer before any build work starts,
with a clear reason and what to do about it.

**Why this priority**: This wasted the most time while shipping a real client app from Windows (upstream #147). Every
run against an unusable device costs a full build.

**Independent Test**: Connect an iOS 16 device (or none, or stop the device service) and run `xcross flutter run`.
The command stops before any build step with a stable error code and a fix hint.

**Acceptance Scenarios**:

1. **AC-002-1** — **Given** a USB-attached device running an iOS version below the supported minimum, **When** I run
   `xcross flutter run` (or `xcross compose run`), **Then** the command stops before any build step starts, within
   5 seconds of starting, with error code `device.ios_unsupported`, the device name and its iOS version, and a fix hint.
2. **AC-002-2** — **Given** no device is attached (and `--wifi` is not requested), **When** I run `xcross flutter run`,
   **Then** it stops before building with `device.not_found` and a hint to connect and trust the device.
3. **AC-002-3** — **Given** the host device service is not available (Windows: Apple Mobile Device Service not running;
   Linux: usbmuxd not reachable), **When** I run `xcross flutter run` or `xcross flutter doctor`, **Then** run stops
   before building with `device.host_service_unavailable` and an OS-specific fix hint, and doctor reports the same
   problem as a failed check.
4. **AC-002-4** — **Given** a supported device is attached, **When** I run `xcross flutter run`, **Then** the device is
   chosen once before the build (including the existing multi-device picker), and the same device is used for
   install and launch after the build, with no second prompt.

---

### User Story 2 - The installed app shows the version from pubspec.yaml (Priority: P2)

A developer bumps `version: 1.0.7+7` in `pubspec.yaml` and builds. Today the app keeps the version from a stale
`ios/Flutter/Generated.xcconfig` (written by an earlier `flutter` run) or falls back to 1.0.0, so the version shown on
the phone and in TestFlight-style tooling is wrong.

**Why this priority**: Wrong versions break update checks and support conversations; it is a silent correctness
bug seen in the real client app. It is independent of devices, so it can ship on its own.

**Independent Test**: Build a project whose `pubspec.yaml` says `1.0.7+7` while `Generated.xcconfig` says `1.0.6`/`6`;
the built app (checked with `xcross inspect`) reports 1.0.7 (7).

**Acceptance Scenarios**:

1. **AC-002-5** — **Given** `pubspec.yaml` `version: 1.0.7+7`, a stale `Generated.xcconfig` with `1.0.6`/`6`, and the
   standard Info.plist template, **When** I run `xcross flutter build` without version flags, **Then** the bundle has
   `CFBundleShortVersionString = 1.0.7` and `CFBundleVersion = 7`.
2. **AC-002-6** — **Given** the same project, **When** I pass `--build-name 2.0.0 --build-number 42`, **Then** the
   bundle has 2.0.0 (42).
3. **AC-002-7** — **Given** a project whose `pubspec.yaml` has no `version`, **When** I build, **Then** the versions
   come from the xcconfig values, else from the Xcode project file, else default to 1.0.0 (1) — in that order, for the
   version name and the build number independently.
4. **AC-002-8** — **Given** any build, **When** it writes the bundle versions, **Then** the build output names the
   source of each value (flag, pubspec, xcconfig, project file or default).

---

### User Story 3 - A polluted PATH no longer breaks linking (Priority: P3)

A developer once pointed `environment.PATH` in their xcross configuration at a Swift toolchain directory. That
toolchain's bundled linker cannot link iOS binaries, and native-asset linking failed with an obscure error until the
entry was removed by hand (upstream #148, later traced to this configuration).

**Why this priority**: Rare but very costly to diagnose; the fix is small and generally useful upstream.

**Independent Test**: Add a PATH entry whose linker cannot link iOS to the configuration, run doctor and a build:
doctor warns with a fix hint, and the build links with an iOS-capable linker.

**Acceptance Scenarios**:

1. **AC-002-9** — **Given** a configured PATH entry that provides a linker which cannot link iOS (such as a Swift
   toolchain's bundled linker), **When** I run `xcross flutter doctor`, **Then** it reports warning
   `toolchain.path_linker_unusable` naming the entry and a fix hint.
2. **AC-002-10** — **Given** the same configuration, **When** I build, **Then** the same warning is shown once before
   the build, and every link step uses an iOS-capable linker, so the build succeeds where a usable linker exists.
3. **AC-002-11** — **Given** no iOS-capable linker exists at all, **When** I build, **Then** it fails before compiling
   with a clear error and the existing setup hint (unchanged behaviour, now reached earlier).

---

### User Story 4 - Nothing is skipped silently (Priority: P4)

A developer's app builds and installs, but a CocoaPods-only plugin, the asset catalog (icon, splash images) or a
storyboard was left out without a clear message. They only notice on the phone.

**Why this priority**: Required by constitution Principle III (fail fast, never skip silently); smaller user impact
than the stories above because some warnings already exist.

**Independent Test**: Build a project with a CocoaPods-only plugin, an `Assets.xcassets` folder and a
`LaunchScreen.storyboard`; the build prints one coded warning with a hint for each, plus a summary.

**Acceptance Scenarios**:

1. **AC-002-12** — **Given** a plugin that ships only a CocoaPods podspec, **When** I build, **Then** the build prints
   warning `build.podspec_only_plugin` naming the plugin and a fix hint.
2. **AC-002-13** — **Given** an `.xcassets` asset catalog in the iOS project, **When** I build, **Then** the build
   prints warning `build.asset_catalog_skipped` naming the catalog and a fix hint.
3. **AC-002-14** — **Given** a storyboard that cannot be used because it is not compiled (including the launch and
   main storyboards removed from Info.plist), **When** I build, **Then** the build prints warning
   `build.storyboard_skipped` naming the storyboard and a fix hint.
4. **AC-002-15** — **Given** a build with warnings, **When** it finishes, **Then** each distinct warning appears once,
   a one-line summary lists the warning codes and counts, and the build's exit code is unchanged.

### Edge Cases

- **Wireless only**: with `--wifi`, discovery may legitimately wait up to the existing wireless timeout. The 5-second
  target applies to attached devices; the check still happens before the build.
- **Device version unreadable**: today this only warns and continues; it still warns and continues, but before the
  build.
- **Multiple devices without a terminal**: the existing "pass --udid" error now appears before the build.
- **Device unplugged during the build**: install fails after the build as it does today, with the existing error.
- **Framework-only Compose builds**: the existing "cannot be run on a device" error stays and needs no device query.
- **Device query hangs** (no response from the device tools): the pre-build check gives up after a bounded time
  with `device.query_timeout` instead of hanging.
- **pubspec version without a build number** (`1.2.3`): the build number comes from the next source in the order.
- **Invalid pubspec version**: the existing invalid-version hint is shown and the next source is used.
- **Info.plist with literal version values** (not `$(...)` variables): literals are kept unless a version flag is
  given, as today.
- **Compose projects** (no `pubspec.yaml`): version resolution is unchanged.
- **PATH entry that does not exist or has no linker**: ignored, no warning.
- **The same skipped resource reached by several build steps**: reported once.

## Requirements *(mandatory)*

### Functional Requirements

**Fail fast (US1)**

- **FR-001**: `xcross flutter run` and `xcross compose run` MUST check the host device service, resolve the target
  device and read its OS version before starting any build step.
- **FR-002**: When the device's OS version is below the supported minimum, the command MUST stop before building
  with code `device.ios_unsupported`, the device name, the OS version, the required minimum and a fix hint.
- **FR-003**: When no device is found (and wireless discovery was not requested), the command MUST stop before
  building with code `device.not_found` and a fix hint.
- **FR-004**: The host device service check MUST run on Windows (Apple Mobile Device Service) and Linux (usbmuxd),
  stop `run` with code `device.host_service_unavailable` and an OS-specific hint, and appear as a doctor check.
- **FR-005**: Every device query made before the build MUST be bounded in time; on expiry the command stops with code
  `device.query_timeout` and a hint.
- **FR-006**: The device chosen before the build MUST be the device used for install and launch after it; the user is
  never asked twice.

**Versions (US2)**

- **FR-007**: For Flutter builds, the bundle version name and build number MUST each be resolved in this order:
  command-line flag, `pubspec.yaml` `version`, iOS xcconfig values, Xcode project file values, default (1.0.0 / 1).
- **FR-008**: The order MUST apply to both `xcross flutter build` and `xcross flutter run`, and to Info.plist values
  written as `$(FLUTTER_BUILD_NAME)`, `$(FLUTTER_BUILD_NUMBER)`, `$(MARKETING_VERSION)`, `$(CURRENT_PROJECT_VERSION)`
  or missing.
- **FR-009**: The build output MUST state the chosen version name and build number and the source of each.

**PATH guard (US3)**

- **FR-010**: Doctor MUST warn with code `toolchain.path_linker_unusable` when a configured PATH entry provides a
  linker that cannot link iOS, naming the entry and giving a fix hint.
- **FR-011**: Before a build, the same condition MUST produce the same warning once.
- **FR-012**: Every link step MUST use a linker verified to link iOS, regardless of the order of PATH entries; a
  configured PATH entry MUST NOT make an unverified linker win.

**Loud warnings (US4)**

- **FR-013**: A plugin that ships only a CocoaPods podspec MUST produce warning `build.podspec_only_plugin` with the
  plugin name and a fix hint.
- **FR-014**: A skipped `.xcassets` asset catalog MUST produce warning `build.asset_catalog_skipped` with the catalog
  path and a fix hint.
- **FR-015**: A skipped uncompiled storyboard, and each storyboard reference removed from Info.plist for that reason,
  MUST produce warning `build.storyboard_skipped` with the storyboard name and a fix hint.
- **FR-016**: Each distinct warning MUST be printed once per build, a summary of warning codes and counts MUST be
  printed at the end, and warnings MUST NOT change the exit code.

**Cross-cutting**

- **FR-017**: All new error and warning codes and their hints MUST be listed in the feature's contract and MUST NOT be
  renamed later.
- **FR-018**: Behaviour MUST be the same on Windows and Linux, except for the OS-specific device service check and
  hint texts.

### Key Entities

- **Diagnostic**: a coded message shown to the user — code (stable, e.g. `device.ios_unsupported`), severity
  (warning or error), subject (device, plugin, file or PATH entry), message and fix hint.
- **Version decision**: the chosen version name and build number, each with its source (flag, pubspec, xcconfig,
  project file, default).
- **Device precheck result**: the selected device, its OS version, and the outcome of the host service check, carried
  from before the build to install and launch.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With an unsupported, missing or unreachable attached device, `xcross flutter run` stops in under
  5 seconds and before any build work, on both Windows and Linux (previously after a full build of minutes).
- **SC-002**: In all tested project layouts (template variables, missing keys, stale xcconfig, no pubspec version),
  the built app's version matches the documented order in 100% of cases.
- **SC-003**: With the problematic PATH configuration from the real project, doctor warns and the build links
  successfully.
- **SC-004**: Zero silent skips: every skipped plugin, asset catalog and storyboard in the test fixtures produces
  exactly one coded warning with a hint.
- **SC-005**: Existing builds that had no such problems produce identical artifacts and exit codes (no regressions in
  the existing test suites on both OSes).

## Assumptions

- The supported minimum stays iOS 17 until feature 005 adds iOS 16 install/launch; the hint for
  `device.ios_unsupported` says so, and feature 005 will relax the check.
- Codes use dotted namespaces (`device.*`, `build.*`, `toolchain.*`) like the `inspect.*` codes from feature 001.
- Warnings are printed to the error stream like today's warnings; a machine-readable event stream is feature 008.
- The xcconfig source keeps today's behaviour (Debug.xcconfig with its includes, else Generated.xcconfig); reading
  Release.xcconfig for release builds is out of scope.
- The exact failure in #148 is reproduced in tests with a configured PATH entry whose linker fails the existing iOS
  link probe; a real Swift toolchain is not needed in CI.
- `xcross flutter doctor` gains the device service and PATH checks; listing podspec-only plugins and skipped resources
  in doctor is out of scope (they are reported during the build).
- Changes to upstream files stay small and are marked; the version-order, fail-fast and silent-skip fixes are
  candidates for upstream pull requests.
