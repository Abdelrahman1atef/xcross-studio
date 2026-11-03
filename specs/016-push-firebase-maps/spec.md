# Feature Specification: Firebase, push and Maps work on the device

**Feature Branch**: `016-push-firebase-maps` (work lands on `008-json-events-gui`) | **Created**: 2026-11-03 |
**Status**: Draft

**Input**: handoff plan `specs/HANDOFF-2026-11-03.md`, feature 016. On an iPhone X (iOS 16.7.16) app A (Firebase,
FCM, Google Maps, Pusher) crashes on the map screen, gets no push and no FCM token, and Firebase reports bundle
errors. The causes found in the built app: the generic runner never runs `AppDelegate.swift`, so
`GMSServices.provideAPIKey` is never called; the profile has no `aps-environment` (no entitlements file, nothing
inferred); the app is signed as `XCR-<identity>.<id>` while APNs and Firebase are bound to the real ID; builds from
the desktop app never get the first-build App ID question; capability errors either stop the build (403/404) or are
reported as "Enabled" (409). The user decided (2026-11-03): use the real App ID; Firebase already has an APNs key.
This feature covers US-IOS-001 AC-01 (identifier and capabilities) and the push/Firebase/Maps part of AC-08.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The app is signed under its real App ID (Priority: P1)

A developer builds an app that uses push, Firebase or Sign in with Apple. xcross signs it under the bundle ID in the
project, the one Firebase, APNs and the App Store record use, unless the developer asks for the prefixed form or
another team owns the ID. The developer can see and change the choice from the CLI and from XCross Studio.

**Why this priority**: every bundle-bound Apple and Firebase service fails under the prefixed ID; nothing else in
this feature can be verified without it.

**Independent Test**: on a fresh project (no saved choice, neither App ID registered) a non-interactive build
registers and signs the real ID; `xcross project bundle-id prefixed` then `original` switch the saved choice.

**Acceptance Scenarios**:

1. **AC-016-1**: The App ID is decided in this order: `XCROSS_BUNDLE_ID` (`original`|`prefixed`); `bundle_id` saved
   in the project (`xcross:` in `pubspec.yaml` or `xcross_project.yaml`); the real ID when the team already has it;
   the prefixed ID when the team has only that one (an earlier build's choice, kept, with a note naming
   `xcross project bundle-id original`); otherwise this is the first build and the real ID is registered. When
   another team owns the real ID, the prefixed ID is used with a warning that push, Firebase, Sign in with Apple and
   associated domains will not work under it. On a terminal the first-build question is still asked, with the real
   ID as the default answer `[1]`, and the answer is saved; without a terminal nothing is asked and nothing is saved
   (the registered real ID keeps later builds on it).
2. **AC-016-2**: `xcross project bundle-id` prints the project's bundle ID, the saved choice (or "not saved"), the
   override from `XCROSS_BUNDLE_ID` if set, and what the next build will use. `xcross project bundle-id
   original|prefixed` saves the choice, keeping the rest of the file. `--json` prints one object
   (`bundleId`, `saved`, `override`, `settingsPath`). A value other than the two is refused with a usage error.
3. **AC-016-3**: XCross Studio's Signing page shows the App ID mode of the open project with a switch
   ("Real App ID" / "Prefixed App ID") that runs the command above and explains that switching makes iOS treat the
   app as a different app (separate data, reinstall).

---

### User Story 2 - Push notifications reach the app (Priority: P1)

A developer whose Flutter app uses `firebase_messaging` builds and runs it. The profile grants push, the app gets an
APNs token and an FCM token, and a notification sent from the backend arrives. When something blocks push, the
doctor and the desktop app say what and how to fix it.

**Why this priority**: push is a release-blocking device test of US-IOS-001 (AC-08) and currently fails silently.

**Independent Test**: build a project with `firebase_messaging` and no entitlements file; `xcross inspect` on the IPA
shows `aps-environment` in the signed entitlements and `xcross app info` on the device shows `push: development`.

**Acceptance Scenarios**:

1. **AC-016-4**: When the app's entitlements do not declare `aps-environment` and the app depends on
   `firebase_messaging` or its `Info.plist` lists `remote-notification` in `UIBackgroundModes`, the build declares
   `aps-environment` itself (value `development`; the signer keeps the value the profile grants, so an App Store
   profile yields `production`) and warns once with code `build.push_entitlement_inferred`, naming the reason and the
   fix (add `aps-environment` to `ios/Runner/Runner.entitlements`). A declared value is never changed. Apps with
   neither signal get nothing.
2. **AC-016-5**: Capabilities are reported truthfully. After switching capabilities on, xcross checks the App ID's
   capability list and then the issued profile's entitlements: "Enabled the PUSH_NOTIFICATIONS capability" is
   printed only for a capability one of them shows. With an Apple ID sign-in, push, associated domains, Game Center,
   Siri and App Groups are switched on through Xcode's `updateAppId.action` (developerservices2's JSON route refuses
   that session with a 409, which used to be swallowed and logged as "Enabled").
   A capability Apple refused (403/404/409 or any other non-authentication error) or that is still off produces the
   coded warning `sign.capability_not_enabled` with the capability, the App ID, Apple's reason and the fix, and
   the build continues (the app installs without that capability). Authentication failures (401) still stop the
   build.
3. **AC-016-6**: `xcross flutter doctor` in a project that uses push has a "Push notifications" section:
   entitlement (declared ✓ / inferred ⚠ with the fix), App ID (real ✓ / prefixed ✗ "push and Firebase are bound to
   <bundle id>; run `xcross project bundle-id original`"), and Firebase config (`GoogleService-Info.plist`
   `BUNDLE_ID` equals the project's bundle ID ✓, differs ✗, missing ⚠). The section is absent for apps without push.
4. **AC-016-7**: XCross Studio's Overview shows a "Push notifications" readiness card from those checks (hidden when
   the doctor reports none), with the failing check's message.

---

### User Story 3 - Code in AppDelegate (Google Maps) runs (Priority: P1)

A developer's `AppDelegate` calls `GMSServices.provideAPIKey(...)` before Flutter starts. The built app opens the
map screen instead of crashing, whether xcross used the project's own Runner sources or its generic runner.

**Why this priority**: the map crash takes the app down on a core screen.

**Independent Test**: build a project whose AppDelegate calls `GMSServices.provideAPIKey("…")`; the generated
generic runner source calls `provideAPIKey:` with that key; on the device the map renders.

**Acceptance Scenarios**:

1. **AC-016-8**: The build finds the Google Maps key the AppDelegate passes to `GMSServices.provideAPIKey`
   (Swift or Objective-C): a string literal, or an `Info.plist` value read with
   `Bundle.main.object(forInfoDictionaryKey:)` / `objectForInfoDictionaryKey:` (resolved from the built
   `Info.plist`, so `$(VAR)` from the xcconfig files works). The generic runner calls `provideAPIKey:` with it at
   launch, before the Flutter engine starts, and only if the GoogleMaps class exists at run time. The key is never
   printed: the log says where it was found. A call whose key cannot be resolved gives the warning
   `build.maps_key_unresolved`.
2. **AC-016-9**: `XCROSS_RUNNER` accepts `auto` (the default), `shim` and `project`. `auto` builds the project's
   own Runner sources when the AppDelegate has code beyond Flutter's template (plugin registration and the
   `super` call) and the generic runner otherwise. Any failure of the project runner still falls back to the
   generic runner with `build.runner_project_failed`, and the generic runner still applies AC-016-8.
3. **AC-016-10**: The project runner's Swift and Objective-C compiles see every module the plugin build produced:
   Swift modules, the module maps of C-family source targets (for example `FirebaseCore`), and the headers and
   frameworks of every resolved xcframework (for example `GoogleMaps`), so `import GoogleMaps` and
   `import FirebaseCore` in `AppDelegate.swift` compile.

---

### User Story 4 - Device evidence (Priority: P2)

**Acceptance Scenarios**:

1. **AC-016-11** (device, `device-check.md`): app A on the iPhone X: the map screen opens; `xcross app info` shows
   `push: development`; the FCM token is non-null; the backend's "order paid" notification arrives; a log capture
   shows no Firebase bundle-ID errors. App B: the release build completes (GoogleMaps link) and the map opens.

### Edge Cases

- The real ID is registered by another team: prefixed with the warning (AC-016-1); the doctor then shows the App ID
  check as ✗.
- The project saves `bundle_id: prefixed` (app A today): the saved choice wins; the doctor flags it for a push app.
- An entitlements file exists but lacks `aps-environment` while the app uses `firebase_messaging`: the key is
  added to the declared set (AC-016-4); other keys are kept.
- The AppDelegate is Objective-C, or calls `provideAPIKey` with a variable that is not an Info.plist lookup: the
  literal or plist forms are handled; anything else warns `build.maps_key_unresolved`.
- `XCROSS_RUNNER=auto` on a template AppDelegate: the generic runner, no extra compile time.
- The Apple ID backend (developerservices2) refuses capability calls: the same warning as AC-016-5.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: App ID selection follows AC-016-1 in the CLI and in desktop-app builds alike.
- **FR-002**: `xcross project bundle-id` reads and writes the saved choice (AC-016-2); the desktop app uses only this
  command (Constitution IV).
- **FR-003**: Push entitlement inference (AC-016-4) runs in the bundle assembler, before signing, and never changes
  a declared value.
- **FR-004**: Capability provisioning never reports a capability as enabled unless Apple's list shows it on, and
  never stops a build for a refused capability (AC-016-5).
- **FR-005**: The doctor's push section and the desktop app's card use the same checks (AC-016-6, AC-016-7).
- **FR-006**: The generic runner applies a Maps key found at build time (AC-016-8) without importing GoogleMaps
  headers, so apps without GoogleMaps are unaffected.
- **FR-007**: `XCROSS_RUNNER=auto` is the default; the project runner never fails a build (AC-016-9, AC-016-10).
- **FR-008**: No key, token or device identifier appears in logs, events or committed files.

### Key Entities

- **App ID mode**: `original` (the project's bundle ID) or `prefixed` (`XCR-<identity>.<bundle ID>`); saved per
  project as `bundle_id`.
- **Push signal**: `firebase_messaging` dependency or `remote-notification` background mode.
- **Maps key source**: AppDelegate literal or Info.plist key named in the AppDelegate.

## Success Criteria *(mandatory)*

- **SC-001**: On the iPhone X, app A opens its map screen, receives an FCM token and shows a backend notification
  (AC-016-11).
- **SC-002**: A first build from the desktop app (no terminal) of an app with push signs under the real ID with no
  question asked.
- **SC-003**: No build stops because a capability could not be switched on; every refused capability is named in
  one warning.
- **SC-004**: A developer can tell from `xcross flutter doctor` alone why push would not work, for each of the three
  causes in AC-016-6.

## Assumptions

- The team's Apple ID session (or an Admin team key) can register the real App ID and switch on Push Notifications;
  the individual API key cannot provision (feature 015), so device tests use the Apple ID session.
- Firebase already has the team's APNs key (user, 2026-11-03), so nothing APNs-side is automated here.
- `firebase_messaging` is detected from the project's resolved plugin list (`.flutter-plugins-dependencies`) or
  `pubspec.yaml`.
- The uncommitted edits to `project_runner.dart` and its test (xcframework search paths for the Runner) come from
  outside this session and are kept as the base of AC-016-10.
- Out of scope: APNs key upload to Firebase, Firebase project configuration, notification service extensions
  (already supported by the extension builder), and the release (distribution) profile, which is feature 018.
