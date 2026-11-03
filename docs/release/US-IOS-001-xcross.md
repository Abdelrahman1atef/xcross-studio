<!-- US-IOS-001 rewritten for XCross Studio on Windows and Linux (no Mac, no Xcode). The original Mac/Xcode story
     is docs/release/US-IOS-001-original.md. Client app names and bundle IDs are placeholders. Each feature
     (specs/016…022) updates the "Status in xcross" lines and the QA table. -->

# US-IOS-001 (XCross edition): build, archive, sign, validate, upload and distribute a Flutter iOS app from Windows or Linux

**Story type:** technical / release engineering · **Priority:** high · **Platform:** iOS / iPadOS
**Technology:** Flutter, Dart, XCross Studio (`xcross` CLI + desktop app), Apple Developer Program, App Store Connect
API, TestFlight
**Primary owner:** iOS / Flutter developer · **Supporting roles:** QA engineer, release manager, Apple Developer
account holder
**Scope:** first-time publication and later production builds · **Requirements verified:** 2026-11-03

**Status legend** used on every acceptance criterion:

- ✅ **supported**: works in xcross today (feature number in brackets);
- 🛠 **added by feature 0xx**: planned or in progress in `specs/0xx-*`;
- 🍎 **Apple-side only**: done in App Store Connect or by Apple; xcross links to the page and checks what it can.

---

## 1. User story

**As** an iOS/Flutter developer **without a Mac**,

**I want** to configure, compile, archive, code-sign, validate and upload my Flutter app's production iOS build
from Windows or Linux with XCross Studio and the App Store Connect API,

**so that** I can distribute it through TestFlight to internal and external testers, collect feedback, and submit the
validated build for App Store review.

### Business value

Everything in the original story, plus:

- No Mac hardware or macOS CI minutes: the whole release runs on Windows, Linux or `ubuntu-latest`.
- One tool from the first build on a device to App Store submission, with machine-readable output (`--json`,
  `XCROSS_EVENTS=ndjson`) for CI and for the desktop app.
- Release checks run before the upload, so Apple's slow server-side rejections (ITMS errors) are caught locally.

### Expected outcome

The developer produces a signed App Store IPA and an `.xcarchive` with xcross, passes `xcross release check`,
uploads with `xcross publish`, sees Apple's processing result, and makes the build available to the right TestFlight
group. Once metadata and compliance are complete, the build can be attached to an App Store version and submitted.

---

# 2. Preconditions and dependencies

## 2.1 Host and toolchain

**Given** the developer is preparing an iOS production release, **when** the environment is reviewed, **then**:

- A Windows 10/11 or Linux (x64) computer is available. macOS is not needed. WSL is not a supported host for device
  work.
- `xcross setup` has installed the Swift toolchain and LLVM (clang, `ld64.lld`), or the doctor shows how to.
- Apple's iOS SDK comes from the developer's **own** `Xcode_<version>.xip` (downloaded from developer.apple.com with
  their Apple ID): `xcross sdk install <Xcode.xip>`. XCross Studio never downloads or redistributes Apple
  material.
- As of November 2026 App Store Connect requires **Xcode 26 / iOS SDK 26 or later**: use an Xcode 26+ `.xip`.
  The doctor fails when the installed iOS SDK is below 26 (✅ 018).
- The app's deployment target is at least iOS 13 (higher when plugins require it).
- The Flutter SDK has a published iOS AOT compiler for this host. When it does not, `xcross flutter sdk auto`
  installs a matching Flutter just for iOS builds (✅ 014).
- There are **no CocoaPods**. Plugins build as one Swift package; podspec-only plugins get a Swift package through
  `xcross plugin shim` overrides (✅ 006).
- Disk space for the SDK (~3 GB unpacked), the SwiftPM cache, archives, symbols and IPAs; internet for Apple
  authentication, package resolution, validation and upload.
- A physical iPhone or iPad for release testing (iOS 15+; iOS 15/16 run release and profile builds, iOS 17+ also
  debug), or an approved device-testing plan.

**Validation commands:**

```bash
xcross --version
xcross flutter doctor            # toolchain, Darwin SDK version, Flutter, AOT compiler, device service, sign-in
xcross flutter sdk list          # the Flutter used for iOS builds and its iOS compiler
xcross sdk list                  # installed Darwin SDKs
flutter --version
```

In XCross Studio: **Overview → Readiness** (Flutter, Swift, LLVM, Darwin SDK, iOS release compiler, Authentication,
Device, Push notifications).

**Expected result:** every readiness area is ✓; nothing blocks a production build.

**Status in xcross:** ✅ setup, SDK install and doctor (001–014); ✅ SDK ≥ 26 check (018).

## 2.2 Apple Developer Program and App Store Connect access

**Given** the app is distributed through App Store Connect, **when** the developer authenticates, **then**:

- An active Apple Developer Program membership exists, and its agreements are accepted (🍎).
- The developer signs in with `xcross auth` (or **Signing** in XCross Studio) with one of:

  | Sign-in | Can do | Cannot do |
  |---|---|---|
  | Apple ID (`xcross auth --apple-id`) | development signing, App IDs, capabilities, App Groups, device registration | App Store Connect API calls (upload, TestFlight, metadata) |
  | Team API key, Admin or App Manager role (`xcross auth --issuer-id … --key-id … --key-path …`) | everything below: App IDs, capabilities, certificates, profiles, upload, TestFlight, metadata, submission | App Groups attachment (Apple's API has none) |
  | Team API key, Developer role | upload builds, read processing | provisioning, TestFlight external review, metadata |
  | Individual API key (`--individual`) | read App Store Connect; upload as permitted by the user's role (🛠 verified in 019) | provisioning (✅ 015 explains it) |

- Two-factor authentication is completed for an Apple ID sign-in.
- The **App Store Connect app record** exists before the first upload (see AC-01).
- Certificates and provisioning profiles can be created by the chosen sign-in, or already exist.

**Individual account note:** a personal membership can distribute through TestFlight and the App Store; an
organization is not required.

**Status in xcross:** ✅ Apple ID, team key and individual key sign-in (008, 015); 🛠 distribution certificates and
App Store profiles (018); 🛠 App Store Connect upload and TestFlight (019–020).

## 2.3 Source code readiness

Unchanged from the original story: release commit identified, features merged, no release blockers, `flutter
analyze` and the required tests pass, production endpoints configured, no secrets committed, plugin versions
reviewed, generated configuration (for example `lib/firebase_options.dart`) available, reproducible from the
recorded revision.

XCross Studio runs `flutter analyze` and `flutter test` as the release gate on the **Release** page, through
`xcross release gate` (✅ 022).
`xcross release check` scans the built IPA for private keys and API secrets (✅ 018).

---

# 3. Acceptance criteria

## AC-01 — App ID, capabilities and the App Store Connect record

**Given** the developer can sign in, **when** a new iOS app is registered, **then**:

1. A unique explicit App ID (reverse-domain bundle ID, for example `com.company.product`) is registered on the right
   team. xcross registers the **project's real bundle ID** on the first build (the prefixed `XCR-<identity>.<id>`
   form is only used on request, or when another team owns the ID, with a warning).
   - `xcross project bundle-id` shows the ID and the saved choice; `xcross project bundle-id original|prefixed`
     changes it.
   - In XCross Studio: **Signing → App ID**.
2. The capabilities the app's entitlements declare are switched on for the App ID before the profile is issued
   (push, associated domains, Sign in with Apple, App Groups, …). `aps-environment` is added when the app uses
   `firebase_messaging` or the `remote-notification` background mode. Every capability Apple refuses is reported
   with `[sign.capability_not_enabled]`; nothing is reported as enabled unless it is on.
3. The App Store Connect **app record** (name, platform, primary language, bundle ID, SKU) exists:
   `xcross appstore app` checks it and, if it is missing, opens App Store Connect's **New App** page with the
   bundle ID, name and SKU to enter (Apple's public API cannot create apps) (✅ 021).
4. The record's bundle ID equals the bundle ID in the signed app: `xcross release check` compares the signed ID with
   the project's (✅ 018) and `xcross appstore app` shows the record's (✅ 021).
5. Extensions (notification service, widgets, share) get their own App IDs under the app's ID (✅ 003, 007).

**Failure conditions:** ID owned by another team (prefixed fallback, warning); project ID differs from the record
(`release check` error); no record (`xcross appstore app`); capability refused (`sign.capability_not_enabled`);
no access to the app (401/403 from App Store Connect, shown with the role needed).

**Status in xcross:** ✅ real App ID by default, `project bundle-id`, truthful capabilities (016); ✅ extensions
(003, 007); ✅ app record check (021); 🍎 creating the app record.

## AC-02 — Version and build number

`pubspec.yaml` `version: 1.0.0+1` maps to `CFBundleShortVersionString` / `CFBundleVersion`. xcross applies the
version from `--build-name`/`--build-number`, then `pubspec.yaml`, then the xcconfig files, then the project file,
and writes the result into every bundle (app and extensions) (✅ 002).

- `xcross flutter build --release --ipa --build-number auto` uses `max(pubspec build, latest App Store Connect
  build + 1)` for the app (✅ 019).
- `xcross publish` refuses a build number App Store Connect already has for that version, before uploading
  (TC-29, ✅ 019).
- `build/xcross-ios/release.json` records version, build number and the git commit (✅ 019).

**Status in xcross:** ✅ version mapping (002); ✅ `--build-number auto`, duplicate check, release record (019).

## AC-03 — Project and target configuration (replaces "open Runner.xcworkspace")

There is no Xcode to open. xcross reads `ios/Runner.xcodeproj/project.pbxproj`, the xcconfig files and
`ios/Runner/Info.plist` directly:

1. Display name, bundle ID, deployment target, device family and orientations are shown by `xcross release check`
   (✅ 018) and on the **Release** page (✅ 022).
2. The Release configuration is used for `--release` builds.
3. Swift and Objective-C code in the app target (AppDelegate) is compiled when it has code beyond Flutter's
   template (`XCROSS_RUNNER=auto`, ✅ 016); plugins and frameworks link through SwiftPM (✅ 006).
4. App icons and the launch screen come from the asset catalog and `LaunchScreen.storyboard` approximation
   (✅ 004).

**Status in xcross:** ✅ project reading, native code, plugins, icons (002–016); ✅ configuration report (018).

## AC-04 — Distribution signing and provisioning

- `xcross flutter build --release --ipa --export-method app-store` signs for App Store distribution: an
  **Apple Distribution** certificate (reused across runs; in CI from `XCROSS_CERTIFICATE_PRIVATE_KEY`), an
  **App Store** profile for the app and each extension, production entitlements (`aps-environment: production`,
  no `get-task-allow`) (✅ 018).
- Signing requires a team API key with Admin/App Manager role, or an Apple ID for development signing only.
- The profile's App ID, team and entitlements are checked against the app; expired or revoked certificates and
  profiles are reported by `release check` (✅ 018).
- Development profiles are never used for an `app-store` export.

**Status in xcross:** ✅ development signing and entitlements (003, 011); ✅ distribution signing (018, team key;
store evidence pending).

## AC-05 — Permissions and Info.plist

`xcross release check` runs a permission audit (✅ 018):

1. Each plugin that needs a protected resource (camera, photos, location, microphone, contacts, Bluetooth, …)
   requires its `NS…UsageDescription`; a missing one is an error (an App Review and runtime crash).
2. Empty or placeholder descriptions ("TODO", the key name, short texts) are warnings.
3. `InfoPlist.strings` localizations are copied into the bundle and checked for the same keys.
4. `UIBackgroundModes` entries are listed with the plugin that justifies them.
5. Broad App Transport Security exceptions (`NSAllowsArbitraryLoads`) are warnings.

Runtime behaviour (granted, denied, restricted) stays a QA test on the device (TC-10).

**Status in xcross:** ✅ permission audit (018).

## AC-06 — Privacy manifests, SDKs and compliance

`xcross release check` (✅ 018):

1. Embeds plugin and SDK resource bundles (and their privacy manifests) in the app, and copies `ios/Runner/PrivacyInfo.xcprivacy` into the app and checks each plugin's and SDK's privacy manifest is
   present for the SDKs on Apple's list.
2. Scans the binaries for required-reason API symbols (file timestamp, system boot time, disk space, active
   keyboards, user defaults) and compares them with the declared reasons.
3. Checks the code signatures of the SDKs Apple lists as requiring them.
4. Asks for (or reads) the export compliance answer and writes `ITSAppUsesNonExemptEncryption`.
5. Scans the IPA for private keys and API secrets.

Data collection review, the privacy policy URL, App Privacy answers and ATT are 🍎 App Store Connect pages; xcross
links to them.

**Status in xcross:** ✅ manifests, required-reason scan, export compliance key, secret scan (018); 🍎 App Privacy.

## AC-07 — Icons, launch screen and devices

- The asset catalog is compiled (`Assets.car`, icons, alternate icons) and the launch screen approximated (✅ 004).
- `xcross release check` requires the 1024 px marketing icon without alpha, a launch screen, and for iPad support the
  multitasking rules (all four orientations or `UIRequiresFullScreen`) (✅ 018).

**Status in xcross:** ✅ icons and launch screen (004); ✅ store checks (018).

## AC-08 — Quality gate and device tests

- **Static and automated tests:** `flutter pub get`, `flutter analyze`, `flutter test`; XCross Studio's **Release**
  page runs them as the gate with `xcross release gate` (✅ 022).
- **Environment:** `xcross flutter doctor`.
- **Device tests** on a real iPhone with xcross: `xcross flutter run --release`, `xcross logs`, `xcross crashes`,
  `xcross app info` (✅ 005, 010). Push notifications, Firebase and Google Maps work in xcross-built apps (✅ 016):
  the real App ID, `aps-environment`, the Maps key from AppDelegate. A plugged/unplugged device updates the desktop
  app live (✅ 017: `xcross devices --watch`).
- The rest of the original list (login, deep links, offline, accessibility, …) is unchanged and app-specific.

**Status in xcross:** ✅ device run, logs, crashes (005, 010); ✅ push/Firebase/Maps (016, device check pending);
✅ live device watcher (017); ✅ gate in the desktop app (022).

## AC-09 — Release build

```bash
xcross flutter build --release --ipa --export-method app-store \
  [--build-name 1.0.0] [--build-number 1|auto] [--obfuscate --split-debug-info=build/symbols/ios]
```

1–6. Dart AOT for arm64, native code and plugins compiled and linked, signed for distribution (✅ 018).
7. `build/xcross-ios/archive/Runner.xcarchive` with `Products/Applications/Runner.app`, `dSYMs/` and the archive
   `Info.plist` (✅ 018).
8. `build/xcross-ios/ipa/<name>.ipa` (✅ 002, App Store export ✅ 018).
9–11. Version, production configuration and release mode are checked by `release check`.

dSYMs are made with `dsymutil` from PATH (the Swift toolchain ships one; a non-assert build from the full LLVM
release is preferred), else `release.dsym_unavailable` (✅ 018). Dart symbols from `--split-debug-info` stay where
Flutter writes them.

**Status in xcross:** ✅ release IPA (002–014); ✅ App Store export, `.xcarchive`, dSYMs (018, store evidence
pending a team key).

## AC-10 — Archive through a GUI (replaces Xcode Organizer archives)

XCross Studio → **Archives** lists every `.xcarchive` under the project with version, build, date, bundle ID,
signing (team, certificate) and the IPA next to it, and opens the folder (✅ 022).

**Status in xcross:** ✅ Archives page (022).

## AC-11 — Validation before distribution (replaces Organizer "Validate App")

- `xcross release check [--json] [<ipa>]` runs every local check from AC-01…AC-09 and returns coded issues
  (`release.*`), errors before warnings (✅ 018).
- When Apple's Transporter is installed by the user, `xcross release check --apple` also runs its `-m verify`
  (✅ 019, `xcross publish --validate`).

**Failure examples:** invalid or development profile, expired certificate, SDK below 26, deployment target too low,
missing privacy manifest data, wrong bundle ID, entitlement mismatch, missing icons, invalid embedded frameworks,
duplicate build number, missing usage descriptions.

**Status in xcross:** ✅ release check (018); ✅ Transporter verify (019).

## AC-12 — Upload (replaces Organizer "Distribute App")

```bash
xcross publish build/xcross-ios/ipa/<name>.ipa [--app-id <Apple ID>] [--wait]
```

- Uploads through the App Store Connect **Build Upload API** (`buildUploads`, `buildUploadFiles`, the reserved
  upload operations, then commit), with retry of failed parts and resume of an interrupted upload (TC-30)
  (✅ 019).
- Falls back to the user's installed Transporter (`--transporter`) when the API is unavailable to the sign-in.
- Records the upload ID, version and build number in `build/xcross-ios/release.json`.
- XCross Studio → **Release → Upload** shows progress.

**Status in xcross:** ✅ publish (019; store evidence pending a team key).

## AC-13 — Processing

`xcross publish --wait` and `xcross testflight status [--build <n>]` follow the upload state and the build's
`processingState` (`PROCESSING`, `VALID`, `FAILED`, `INVALID`) and its beta states (`MISSING_EXPORT_COMPLIANCE`,
`READY_FOR_BETA_TESTING`, `IN_BETA_TESTING`, `WAITING_FOR_BETA_REVIEW`, `IN_BETA_REVIEW`, `BETA_REJECTED`,
`EXPIRED`), with Apple's messages (✅ 019 `publish --wait`; ✅ 020 `testflight status`). The original states table maps one-to-one.

**Status in xcross:** ✅ processing status (019, 020).

## AC-14 — Internal TestFlight

`xcross testflight groups`, `xcross testflight group create <name> --internal`, `xcross testflight add --group
<name> [--build <n>]`, `xcross testflight what-to-test "<text>"`, `xcross testflight testers add <email> --group
<name>`, and the export compliance answer (`xcross testflight compliance --no-encryption`) (✅ 020). The 100-tester and
90-day limits
and "internal only" builds are Apple's (🍎).

**Status in xcross:** ✅ internal TestFlight (020; writes pending a team key, reads checked).

## AC-15 — External TestFlight

Beta app information (description, feedback email), beta review contact and demo account, `xcross testflight
submit` for beta review, external groups, testers by email and `xcross testflight public-link` (✅ 020). Beta
review itself is Apple's (🍎).

**Status in xcross:** ✅ external TestFlight (020); 🍎 beta review.

## AC-16 — App Store submission

- `xcross appstore metadata pull|push` syncs a `fastlane`-style folder (`appstore/metadata/<locale>/name.txt`,
  `subtitle.txt`, `description.txt`, `keywords.txt`, `support_url.txt`, `privacy_url.txt`, `release_notes.txt`,
  categories, age rating) with the App Store version (✅ 021).
- `xcross appstore screenshots push` uploads `appstore/screenshots/<locale>/<display>/*.png` after checking the sizes
  Apple accepts (✅ 021).
- `xcross appstore attach --build <n>` attaches the processed build; `xcross appstore submit` creates and submits the
  review submission (`--dry-run` lists blockers); `xcross appstore status` shows its state (✅ 021).
- App Privacy answers, pricing, agreements, tax and banking are not in the public API: xcross opens the page (🍎).

**Status in xcross:** ✅ metadata, screenshots, attach, submit, status (021; writes pending a team key, status
checked); 🍎 privacy labels, pricing, agreements, approval.

---

# 4. End-to-end developer guide (Windows or Linux)

1. **Toolchain:** `xcross setup`, `xcross sdk install ~/Downloads/Xcode_26.x.xip`, `xcross flutter doctor`.
2. **Dependencies and gate:** `flutter pub get`, `flutter analyze`, `flutter test` (or **Release → Quality gate**).
   No `pod install`: plugins build through SwiftPM.
3. **Version:** `pubspec.yaml` `version: 1.0.0+1`; record the commit.
4. **Project review (instead of Xcode):** `xcross release check` shows display name, bundle ID, deployment target,
   devices, orientations, entitlements, permissions and icons.
5. **Sign-in:** `xcross auth --issuer-id … --key-id … --key-path AuthKey_XXXX.p8` (team key, Admin/App Manager).
6. **App ID and capabilities:** `xcross project bundle-id` (real ID); capabilities follow the entitlements.
7. **Permissions:** fix every `release.permission_*` issue; test the dialogs on the device.
8. **Production configuration:** unchanged from the original guide (endpoints, Firebase, deep links, flags).
9. **Archive and IPA:** `xcross flutter build --release --ipa --export-method app-store --build-number auto`.
10. **Validate and upload:** `xcross release check`, then `xcross publish build/xcross-ios/ipa/*.ipa --wait`.
11. **App Store Connect:** `xcross testflight status`; the build must reach `VALID` and a testable beta state.
12. **QA:** `xcross testflight add --group QA`, `xcross testflight what-to-test "…"`; testers install from
    TestFlight.

The same steps run unattended in CI with `docs/ci/github-testflight.yml` on `ubuntu-latest` (`xcross release ci`
writes it into the project, ✅ 022).

---

# 5. QA test cases

| ID | Scenario | xcross / XCross Studio | Expected | Status |
|---|---|---|---|---|
| TC-01 | Host, toolchain, SDK ≥ 26, Flutter | `xcross flutter doctor`; Overview | all ✓ | ✅ |
| TC-02 | Account and team | `xcross auth`; Signing | right team, role shown | ✅ |
| TC-03 | App Store Connect record | `xcross appstore app` | record exists | ✅ 021 |
| TC-04 | Registered App ID equals project | `xcross project bundle-id`; `release check` | exact match | ✅ 016, 018 |
| TC-05 | Version in pubspec and app | `xcross inspect <ipa>` | right marketing version | ✅ |
| TC-06 | Build number | `inspect`; `--build-number auto` | unique build | ✅ 002, 019 |
| TC-07 | Distribution signing | `release check` | App Store profile, distribution cert | ✅ 018 (store ⏳) |
| TC-08 | Capabilities and entitlements | `inspect`; build log | entitlements match profile; refused ones named | ✅ 016 |
| TC-09 | Usage descriptions | `release check` | all present | ✅ 018 |
| TC-10 | Denied permissions | device test | app stable | manual |
| TC-11 | Privacy manifests and SDKs | `release check` | requirements met | ✅ 018 |
| TC-12 | Icon and launch screen | `release check`; device | production branding | ✅ 004, 018 |
| TC-13 | Static analysis | Release → Quality gate (`release gate`) | passes | ✅ 022 |
| TC-14 | Automated tests | Release → Quality gate (`release gate`) | pass | ✅ 022 |
| TC-15 | Release archive | `flutter build … --export-method app-store` | `.xcarchive` created | ✅ 018 (store ⏳) |
| TC-16 | App Store IPA | same | App Store IPA | ✅ 018 (store ⏳) |
| TC-17 | Archive through the GUI | Release step 5, Archives page | archive listed | ✅ 022 |
| TC-18 | Validation | `release check` | no errors | ✅ 018 |
| TC-19 | Upload | `xcross publish` | accepted | ✅ 019 (store ⏳) |
| TC-20 | Uploaded build identity | `testflight status` | version, build, app match | ✅ 019, 020 (store ⏳) |
| TC-21 | Processing | `publish --wait` | `VALID` | ✅ 019 (store ⏳) |
| TC-22 | Export compliance | `testflight status`; build key | declared | ✅ 018, 020 |
| TC-23 | Internal group | `testflight add --group` | group has build | ✅ 020 (store ⏳) |
| TC-24 | Install from TestFlight | device | installs, launches | manual |
| TC-25 | Production backend | device | production | manual |
| TC-26 | Critical journeys | device | no blockers | manual |
| TC-27 | External beta review | `testflight submit` | review handled | ✅ 020 (store ⏳) |
| TC-28 | Submission metadata | `appstore metadata push`; `appstore status` | complete | ✅ 021 (store ⏳) |
| TC-29 | Duplicate build number | `publish` | refused before upload | ✅ 019 |
| TC-30 | Interrupted upload | kill `publish`, run again | resumes or restarts safely | ✅ 019 |
| TC-31 | Release evidence | `release.json`; Release → record card | recorded | ✅ 019, 022 |
| TC-32 | Symbols | archive `dSYMs/`, `build/symbols/ios` | retained | ✅ 018 |
| TC-33 | Push, Firebase, Maps on device (xcross addition) | `app info`, `logs --preset push`; map screen | token, notification, map | ✅ 016 (device ⏳) |
| TC-34 | Plug/unplug (xcross addition) | `xcross devices --watch`; top-bar badge | updates within ~2 s | ✅ 017 (device ⏳) |

### Example detailed case: TC-20, uploaded build identity

**Preconditions:** an upload was accepted; the record exists; the tester can read the app.

**Steps:** `xcross testflight status --build <n> --json` (or Release → Processing); compare `version`,
`buildNumber` and `bundleId` with `build/xcross-ios/release.json`; check `processingState`.

**Pass:** same identity and `VALID`. **Fail:** wrong app, version mismatch, missing build, `FAILED`/`INVALID`.

---

# 6. Failure handling and recovery

| Failure | Probable cause | Response with xcross |
|---|---|---|
| Doctor reports a problem | missing tool, SDK or sign-in | follow the doctor's fix line (`xcross setup`, `xcross sdk install`, `xcross auth`) |
| SDK below 26 | old `.xip` | install an Xcode 26+ `.xip` |
| No iOS compiler for this Flutter | Flutter newer than published compilers | `xcross flutter sdk auto` |
| Plugin has only a podspec | no Swift package | `xcross plugin shim <plugin>` |
| No distribution certificate | team key lacks the role, or none exists | Admin/App Manager key, or `XCROSS_CERTIFICATE_PRIVATE_KEY` |
| Profile mismatch | wrong App ID, team or entitlements | `release check` names the key; fix entitlements |
| Capability refused | sign-in may not change capabilities | `[sign.capability_not_enabled]` hint |
| Push/FCM token missing | prefixed App ID or no `aps-environment` | doctor "Push notifications"; `xcross project bundle-id original` |
| Map screen crashes | Maps key not set | AppDelegate's key is passed (016); `[build.maps_key_unresolved]` names a form xcross cannot read |
| Duplicate build number | number already uploaded | `--build-number auto`, rebuild |
| Missing usage description | Info.plist incomplete | add the key, rebuild |
| Privacy manifest | missing or incomplete | add `PrivacyInfo.xcprivacy` reasons |
| Upload authentication fails | key, role or expired session | `xcross auth`; check the key's role |
| Upload interrupted | network | run `xcross publish` again: it resumes |
| Build stays processing | Apple | `xcross testflight status`; escalate after 24 h |
| Missing compliance | export compliance not answered | `xcross testflight compliance --no-encryption` or the plist key |
| ITMS-xxxxx from Apple | server-side validation | record the code here and in the feature's `device-check.md`; fix and rebuild |

Recovery principles 1–8 of the original story apply unchanged.

---

# 7. Non-functional requirements

As in the original, plus:

- **Security:** API keys and the Apple ID session live only in xcross's owner-only config files or the OS credential
  store; never in logs, events or bug reports; no telemetry.
- **Portability:** every command works on Windows and Linux hosts with the same output.
- **Observability:** `--json` and `XCROSS_EVENTS=ndjson` on every release command; `release.json` per build.
- **Legal:** the Apple SDK comes from the developer's own `.xip`; Apple's license terms on SDK use apply and are
  shown on first run.

---

# 8. Sub-tasks

| Task | Owner | Deliverable (xcross) |
|---|---|---|
| IOS-01 Host toolchain | developer | `xcross setup`, `xcross sdk install`, doctor ✓ |
| IOS-02 Program access | account holder | team key (Admin/App Manager) or Apple ID |
| IOS-03 App ID | developer | `xcross project bundle-id` (real ID) |
| IOS-04 App record | release manager | App Store Connect New App (🍎), `xcross appstore app` |
| IOS-05 Project review | developer | `xcross release check` report |
| IOS-06 Signing and capabilities | developer | `--export-method app-store` |
| IOS-07 Version and build | developer | pubspec, `--build-number auto` |
| IOS-08 Permissions | developer | `release check` clean |
| IOS-09 Privacy and SDKs | developer | `release check` clean |
| IOS-10 Icons and launch | developer/designer | asset catalog |
| IOS-11 Release configuration | developer | production endpoints |
| IOS-12 Automated validation | developer/QA | Release → Quality gate |
| IOS-13 Archive | developer | `.xcarchive` |
| IOS-14 IPA | developer | App Store IPA |
| IOS-15 Validate | developer | `release check` (+ Transporter verify) |
| IOS-16 Upload | developer | `xcross publish` |
| IOS-17 Processing | developer | `publish --wait` |
| IOS-18 Internal TestFlight | release manager | `xcross testflight add` |
| IOS-19 TestFlight smoke tests | QA | report |
| IOS-20 External testing | release manager | `xcross testflight submit` |
| IOS-21 Metadata | release manager | `xcross appstore metadata push` |
| IOS-22 Submit | release manager | `xcross appstore submit` |
| IOS-23 Evidence | release manager | `release.json`, Release → Export |
| IOS-24 CI (linked story) | developer | `docs/ci/github-testflight.yml` on `ubuntu-latest` |

---

# 9. Definition of ready

As in the original, with "Required Mac and Xcode environment" replaced by "Windows or Linux host with `xcross
flutter doctor` ✓ and an Xcode 26+ `.xip` installed".

# 10. Definition of done

As in the original, with these xcross specifics:

- [ ] `xcross flutter doctor` ✓, Darwin SDK ≥ 26.
- [ ] App record exists (`xcross appstore app`).
- [ ] The app is signed under its real App ID with an App Store profile.
- [ ] `xcross release check` has no errors; warnings reviewed.
- [ ] `.xcarchive`, IPA, dSYMs and Dart symbols retained.
- [ ] `xcross publish --wait` reached `VALID`; build visible in `xcross testflight status`.
- [ ] Internal group installs the build; smoke tests pass.
- [ ] `build/xcross-ios/release.json` archived with the release.

External TestFlight and App Store submission additions are unchanged. Apple approval and public release remain
external milestones.

# 11. Release evidence

`build/xcross-ios/release.json` (✅ 019; shown and copied from the Release page, ✅ 022):

| Field | Source |
|---|---|
| Application, bundle ID, team | signed app and profile |
| Marketing version, build number | `Info.plist` |
| Flutter version, xcross version | toolchain |
| Darwin SDK and the Xcode version it came from | installed SDK (`DTXcode`, `DTSDKBuild`) |
| Deployment target | `Info.plist` |
| Source revision | `git rev-parse HEAD` (dirty flag) |
| Archive, IPA (SHA-256) | build output |
| Signing | certificate serial, profile name and type |
| Upload result, upload ID | `xcross publish` |
| Processing result, TestFlight state | App Store Connect |
| QA result, owner, date, known issues | filled in by the release manager |

# 12. Out of scope unless separately requested

As in the original, except: **a CI/CD pipeline is now a linked story (IOS-24)** with a ready template,
`docs/ci/github-testflight.yml`, that runs the whole flow on `ubuntu-latest` with the same secrets as the reference
Mac workflow (`docs/release/reference-macos-workflow.yml`).

# 13. References

Apple and Flutter references 1–15 of the original story, plus:

- [App Store Connect API: Build uploads](https://developer.apple.com/documentation/appstoreconnectapi/build-uploads)
- [WWDC25 324: Automate your development process with the App Store Connect API](https://developer.apple.com/videos/play/wwdc2025/324/)
- XCross Studio specs `specs/016-push-firebase-maps` … `specs/022-*`.

**Final acceptance statement:** unchanged. The release succeeds when a correctly configured, signed, validated build
built with xcross is accepted and processed by App Store Connect, reaches the intended TestFlight audience and passes
the release checks; App Store approval and publication are tracked separately.
