## Unreleased (XCross Studio)

- **The Accounts card shows who holds each account** (feature 031): Account Holder, Company and Team ID on every row, not only the Key ID. `xcross auth account --key-id <id> --private-key <file> [--issuer-id <id>] [--json]` asks Apple with that key for the Account Holder and the team ID, without saving anything or changing the saved sign-in; Studio asks once per account. Apple only answers the holder for a team key with the Admin role (the row says so otherwise), and no API gives the company name, so Company is typed once in the new Edit dialog. What you type is never replaced by what Apple says. Not yet seen with real keys.
- **Switch between App Store Connect accounts** (feature 030): the Signing page has an Accounts card with every API key Apple accepted, the one in use marked, and Use, Rename and Remove. Use runs `xcross auth` with that key, so the CLI still checks it with Apple and keeps the saved key when Apple refuses. Only the name, Key ID, Issuer ID and the `.p8` path are remembered (`signing-accounts.json` in the Studio config folder), never the key or a password; Apple ID accounts are not listed because they need the password again. The first run also reads the profiles of the `xcross-key` script.
- **App Store Connect showed Apple's grey placeholder grid, not the app icon, for an xcross build** (feature 004). `Assets.car` lacked what actool writes for an `AppIcon`: the `SISM` icon-set record of each idiom (iPhone, iPad, marketing), and the per-size Icon Index (20 pt is 1, 60 pt is 6, 1024 pt is 11, as in Xcode 26.2 catalogs). Every size shared index 1, so only 6 of 19 icons reached the catalog, and Apple could not render the icon set. The catalog now has one icon per size, the icon-set records (the marketing one is byte for byte Apple's) and BITMAPKEYS masks computed from the icons present. A Flutter app build now gets the real rendered icon from `/v1/builds/{id}/icons`, as an Xcode build does. Not yet seen on the App Store Connect website itself.
- **The iOS splash logo looked very stretched on an iPhone X (TestFlight).** A square logo under `UILaunchScreen` was
  scaled to fill the whole screen. The build now draws the launch image on a canvas the shape of the screen (375 × 812 pt
  for iPhones, 768 × 1024 pt for iPads, at each scale), with the logo in the middle over its background colour. It looks
  right whether iOS centres the picture or fills the screen with it. The files in your project do not change. The catalog
  grows by about 30 MB on disk (the IPA far less, the canvas is one colour). Not yet seen on a device: restart the phone,
  install a release build, and open the app twice (the stretch showed on later launches).
- **Permissions and capabilities like Xcode** (feature 027): `xcross permissions list|set|remove` and
  `xcross capabilities list|add|remove` (`--json`) read and edit the purpose strings of `ios/Runner/Info.plist` and the
  entitlements file as text, so comments, key order and line endings stay, with a backup in `.xcross/permission-backups/`.
  The Studio's **Project** page (it replaces Plugins) has Permissions, Capabilities and Plugins tabs.
- **The camera (and every other) permission answered "denied" without asking** in iOS apps that use `permission_handler`
  and are built by xcross. The plugin compiles a permission out unless its `PERMISSION_X` switch is set, CocoaPods sets it
  from the Podfile, and xcross never did. xcross now reads the Info.plist purpose strings and the Podfile's
  `PERMISSION_X=1|0` lines and gives the plugin the switches (part of the plugin build's cache key; the build says which it
  switched on). Drafts of older plugin versions (9.4.x, from a podspec) get the same switches written into
  `Package.swift`, and `plugin status` reports a draft that lacks one (`permission_macros_missing`) with a Regenerate
  button. doctory's draft lacked all of them: run Regenerate once.
- **Plugin actions you cannot miss** (feature 028): `xcross plugin status --json` finds an override for another version of
  the plugin (a build skips it), a draft that lacks the privacy manifest the plugin ships, and a draft nobody reviewed;
  `plugin ack` marks it reviewed. `plugin shim --force` copies the old files to `.xcross/plugin-backups/` first and refuses a
  `Package.swift` you wrote unless `--replace-hand-written`. The Studio shows the count on the sidebar and the top bar, lists
  the items on Overview, Build & Run, Project and Release step 6, and fixes one with a click.

- App Store Connect refused an IPA with **90426 Invalid Swift Support**: apps that load Swift libraries (Facebook's
  frameworks, Flutter's plugin library) need `SwiftSupport/iphoneos/` in the IPA. The App Store build now adds it, and
  the archive too. **Run `xcross sdk install <Xcode.xip>` again once:** the SDK now keeps Xcode's iPhoneOS Swift runtime
  libraries (about 60 MB), which the build copies from; without them an App Store build stops before signing and says so.
- Apple then answered **90429** twice. The first fix (the Swift libraries also in the app's `Frameworks` folder, signed
  with the app; `release.swift_support_not_embedded`) was not the cause. Apple's engineers say 90429 names the Swift
  files when a **standalone `.dylib` sits in `Frameworks`**, and the plugin build leaves one
  (`libFlutterPluginsGenerated.dylib`). The App Store build now wraps it in `FlutterPluginsGenerated.framework` and
  repoints everything that loads it. Build again; no new SDK install is needed beyond the one above.
- `xcross release check` now also tests how the IPA is put together, without needing Apple's code for it:
  `release.loose_dylib`, `release.static_library_in_bundle`, `release.nested_not_signed`, `release.nested_team_mismatch`,
  `release.unsupported_architecture`, `release.dependency_missing`, `release.swift_support_incomplete`, and a warning for
  frameworks without version keys. It reports the loose library of the IPA Apple rejected.
- `xcross publish` explains a rejection: the fix for the codes it knows (90426, 90429, 90683) and, for any other, that the
  check has no rule for it yet.
- Settings has a **Darwin SDK** card (pick the Xcode.xip, Install SDK, link to Apple's download page) and an **Install
  missing tools** card; the doctor now warns when the SDK has no Swift runtime libraries instead of saying "Installed".
- `xcross release check` reads the code for what App Store Connect reads: `release.swift_support_missing` (an error, the
  90426 case) and `release.permission_missing_for_call` (a warning: `requestAlwaysAuthorization` needs
  `NSLocationAlwaysAndWhenInUseUsageDescription`, 90683). It passed both before.
- `xcross release check --online` also asks App Store Connect with the saved key, read-only: the app exists, this build
  number and version are accepted, the App ID has the capabilities the entitlements need. The Studio's Release step 6
  does this by default and shows whether App Store Connect was asked.

- iOS plugins that ship only a podspec lost their privacy manifest when xcross drafted their `Package.swift`, because the
  file sat outside the source folder: for example `fluttertoast` 8.2.14, `flutter_secure_storage` 9.2.4 and
  `permission_handler_apple` 9.4.7. New drafts copy the manifest in and ship it. **Existing drafts are not changed:** run
  `xcross plugin shim <plugin> --force`, which replaces the draft, then build again. For a plugin with an override,
  `release.privacy_manifest_missing` now says this, where it used to tell you to update the plugin.

- Splash: padding and margin did nothing you could see, and Android 12+ ignored them and any size above about 135 dp.
  `--padding` now makes the logo smaller, where it used to add space around a centred image. **A saved design with padding
  gets a smaller logo.** Margin moves the logo by half the difference between opposite sides, also on Android 12+; equal
  margins cancel out, so the app shows each side and the CLI warns with `splash.margin_no_effect`.
  `--android12-icon-width` is used as it is, through Android's 192 dp circle, or 160 dp with an icon background, as
  Android documents, and what falls outside shows as cut in the app and is reported by `splash.android12_clipped`.

- App icon page and Icon and splash studio: the app icon and splash now show together, on every iPhone and iPad screen and
  common Android phones, tablets and foldables, each frame to scale in that device's own size. Filter by family, portrait
  or landscape, light or dark, splash or home icon, with safe area guides, and add any size by hand. Android frames show
  what Android draws, where the preview used to reuse the iOS image. The studio's new `All screens` tab writes or exports
  the icon and splash with one action, and a new splash starts from the icon's image.

- Splash options: a separate logo size for iPad, Android and Android 12+, an Android 12+ icon background, and branding
  size and position (`--ipad-logo-width`, `--android-logo-width`, `--android12-icon-width`,
  `--android12-icon-background`, `--dark-android12-icon-background`, `--branding-width`, `--branding-bottom`). The app
  also offers what only the CLI had: a splash zip, every icon target at once, your own badge image, and half-percent
  padding. `splash check` warns with `splash.branding_clipped` when branding would be cut off on small iPhones.

- Signing: `xcross auth status [--json]` shows how you signed in, offline and without any password, token or key. The
  Signing page's Status section shows the same, with what device builds and App Store builds each use, and the sign-in form
  starts from it.

- iOS splash: a transparent logo showed as a big black square on a real iPhone. The launch image is now drawn over its
  background colour when the app is built, so it has no transparent pixels; the files in the project stay as they are.
  Confirmed on an iPhone X, light and dark: the logo on its colour, no square. To see a new splash, restart the
  iPhone and install again: iOS keeps the one it saved, and deleting the app is not enough.

- Asset catalogs: iOS could not find any named colour xcross compiled, so `UIColor(named:)` failed and the splash background
  fell back to the system's, black in dark mode. Colours are now written as Apple's `actool` writes them, checked byte for
  byte against real catalogs.

- iOS splash and asset catalogs: an image set with the same name as a colour set hid the colour from iOS, as the
  `LaunchBackground.imageset` flutter_native_splash leaves behind did. The colour now wins and the build warns with
  `build.asset_invalid`. `splash check` reports it (`splash.name_clash`), and `splash generate` backs it up and removes it.

- Flutter assets: an asset with a space or special character in its name could not load on iOS, such as a Lottie file named
  `Map Loading.json`, because the file was written with a plain name while Flutter asks for `Map%20Loading.json`.
  Assets declared by packages were left out of the app too, and are now copied, with a warning if one is missing.

- Plugin builds: switching between debug and release threw away every compiled plugin and compiled them all again, because
  the build's cache key included the Flutter engine's binary, which differs per mode. The key now holds what plugins compile
  against (the engine's headers and modules, and its revision), and each build still embeds the engine of its own mode. The
  App Store compiler flags are in the key too, so a change in them no longer reuses what the old flags compiled. The key
  changed, so the next build in each project compiles its plugins once.

- App Store uploads: App Store Connect rejected builds with "91111 Missing app icon", because `Assets.car` left out the
  1024 px App Store icon to save about 4 MB. It is now in the catalog, from the set's App Store icon or from a single-size
  set's only image. An icon of the wrong size is left out with `build.asset_invalid`.

- The release quality gate only fails on what stops a release: analyzer errors and failing tests. Warnings and infos are
  listed and do not fail it, unless you pass `--fatal-warnings` or `--fatal-infos`. A project without tests passes, where
  `flutter test` failed with "Test directory "test" not found". An issue an analyzer plugin reports twice is listed once.

- XCross Studio: page text can be selected and copied with the mouse and Ctrl+C. Quality gate results, the release check
  and the app icon checks have a copy button, and a long list of gate results scrolls in its own box.

- Firebase Cloud Messaging on the device: apps had no FCM token, while Firebase features that only need the network
  worked. `firebase_messaging` connects to push when launch finishes, and xcross registered plugins later, on the
  engine of the window it makes in code. Plugins now register during launch, on an engine the window then uses.
  `build.runner_legacy_registration` is gone with the behaviour it warned about.
  ([specs/025-plugin-drafts-check](specs/025-plugin-drafts-check/spec.md), AC-025-7)

- App Store builds: `--export-method app-store` builds plugins without `DEBUG`. It was always defined, so
  `firebase_messaging` marked the APNs token as sandbox, which cannot be delivered to an App Store install. These builds
  use a workspace of their own, so everyday builds are kept.
  `XCROSS_PLUGIN_BUILD=distribution` does the same for an app signed for distribution outside xcross. (AC-025-6)

- Podspec-only plugins build without a manual step: a build drafts
  `xcross_overrides/<plugin>/<version>/Package.swift`, the files `xcross plugin shim` writes, and says so with
  `[build.plugin_drafted]`. A pod with no known Swift package is named by `[build.plugin_unknown_pods]`, before anything
  compiles. `xcross plugin check` says what a build will do with each plugin without compiling. (AC-025-1 to AC-025-4)

- A new workspace no longer fails with "no versions of" a package when SwiftPM's shared download cache holds an unusable
  copy of it. xcross removes what git cannot read and resolves again. (AC-025-9)

- A build no longer stays stuck after a compile error. On Windows, `swift build` that printed an error and then nothing
  for 5 minutes is ended with its compilers, and the build fails showing the errors. (AC-025-5)

- Apps using FlutterFire plugins whose `Package.swift` reads the plugin's own `pubspec.yaml` (firebase_core 3.x,
  firebase_analytics 11.x, firebase_messaging 15.x, firebase_crashlytics 4.x, firebase_remote_config 5.x) build on
  Windows again. Their manifest found its folder with `URL(string: #file)`, which reads `C:` as a URL scheme, and
  crashed with "Failed to load configuration … pubspec.yaml". xcross now gives that expression the manifest's real
  folder and stages the plugin's `pubspec.yaml` with it.

- XCross Studio on Windows: commands the app started (the device watch, log streams, builds) no longer keep running
  after it closes, crashes or is ended in Task Manager. They locked the app's CLI files. The app runs in a Windows
  job that ends its processes with it; folders and links open outside that job, so the window or browser stays open.
  Every command also gets the environment saved in Windows (PATH, `SDKROOT`) when it starts, not the one the app
  started with, and the bundled CLI is found next to the app on each run instead of from a saved path.

- Change the version quickly: `xcross project version [<x.y.z>[+<n>]] [--build <n>] [--bump
  major|minor|patch|build]` edits the `version:` line of `pubspec.yaml` (quotes, comments and other lines kept; a new
  version also raises the build number). Step 2 of the Release page has Version and Build fields with Save and
  one-click bumps showing the result ("Patch → 1.0.8 (8)").
  ([specs/022-studio-release-flow](specs/022-studio-release-flow/spec.md), AC-022-9)

- **Icon and splash studio** on the App icon page and in the CLI. One source makes every app icon and the native
  splash. The source is an image, text (font, bold, italic) or a searchable symbol (filled, outline, round), with a
  foreground colour, an effect (drop shadow, cast shadow, score), padding for all sides or each side, trim, a colour,
  gradient, mesh or image background, 11 textures, a badge, and Android's file name, shape and themed icon. Targets:
  iOS, Android (densities, adaptive, monochrome, Play Store), notification icons, web (favicon, manifest, maskable),
  macOS, watchOS, tvOS, Android TV and the Play Store banner, each with its own live preview. `xcross splash
  generate|check` makes the native splash: logo with its own padding and margin, background, dark variant and
  branding image, written for iOS (`LaunchImage`, `LaunchBackground`, the storyboard xcross reads into
  `UILaunchScreen`) and Android (`launch_background`, `values-v31` with the Android 12 safe circle), previewed on
  phones. Writing into a project backs up what it replaces; `--output` and `--zip` touch nothing. The settings stay
  in `xcross_assets.json` for `--config` to regenerate, and what they name is kept in `.xcross/assets/`.
  ([specs/024-icon-splash-studio](specs/024-icon-splash-studio/spec.md))

- **App icon** in XCross Studio and `xcross icons`: `icons check [--json]` lists every icon size iOS uses
  (notification, Settings, Spotlight, home screen, iPad, App Store) with its file and status, reports what App Store
  Connect rejects (an App Store icon with an alpha channel, missing or wrong-size files) and how the logo sits
  against iOS's rounded corners (cut by the corners, off centre, too small, exported pre-rounded). `icons generate
  <image.png> [--background auto|#RRGGBB] [--padding <0-30>]` writes the whole set from one image, centred on a
  solid background without an alpha channel, after backing up the old set to `.xcross/icon-backups/`. The App icon
  page shows the icon as iOS masks it on the home screen, in a notification, in Settings, Spotlight and the App
  Store, with a safe-area overlay, and makes the set from a picked image with a live preview.
  ([specs/023-icon-studio](specs/023-icon-studio/spec.md))

- Builds no longer stop with "Bundle contains an unresolved link" when a plugin's package keeps a resource as a
  symbolic link (SDWebImage's privacy manifest): SwiftPM resource bundles are embedded with the files the links
  point at, found in the package checkout when the link does not resolve (`build.resource_link_unresolved` when it
  is found nowhere). Reading the Darwin SDK's version no longer prints a parser stack trace.

- XCross Studio has a **Release** destination that walks US-IOS-001 in order (readiness, version and build with the
  next App Store Connect build number, signing, quality gate, App Store archive and IPA, release check, upload and
  processing, TestFlight groups and notes, App Store submission with a dry run and a confirmation, the release record
  and a CI workflow), and an **Archives** destination listing the `.xcarchive`s xcross built. New CLI commands for
  it: `xcross release gate` (`flutter analyze` and `flutter test` as the release gate) and `xcross release ci`
  (writes a GitHub Actions workflow that builds, signs and uploads from `ubuntu-latest`, also in
  `docs/ci/github-testflight.yml`). ([specs/022-studio-release-flow](specs/022-studio-release-flow/spec.md))

- App Store submission from the command line with the App Store Connect API (`xcross appstore …`):
  - `app [--json]` finds the project's app record, or explains that Apple's API cannot create apps and prints the
    New App page with the bundle ID, name and SKU to enter (exit 1).
  - `version [<x.y.z>] [--create]` shows or creates the editable iOS version.
  - `metadata pull|push` syncs a fastlane-style `appstore/metadata` folder (names, subtitles, privacy URL,
    description, keywords, promotional text, release notes, support and marketing URLs, copyright, categories, age
    rating), creating missing localizations and sending only changed fields.
  - `screenshots push [--replace]` checks every PNG's size against Apple's sizes for its display type before
    anything is sent, then reserves, uploads to Apple's upload operations (without the API token) and commits each
    image with its MD5.
  - `attach --build <n>`, `submit [--dry-run]` (blockers it can see: no build, missing texts or screenshots) and
    `status [--json]`. App Privacy, pricing and agreements are not in the API; the commands point to those pages.

  ([specs/021-app-store-submission](specs/021-app-store-submission/spec.md))

- `xcross testflight` takes an uploaded build through TestFlight from Windows or Linux with an App Store Connect team
  key (Admin or App Manager): `status [--json]` (processing state, internal/external beta states, export compliance,
  groups), `groups`, `group create [--external] [--public-link]`, `add --group`, `what-to-test`, `testers add|list`,
  `compliance --no-encryption|--uses-encryption`, and for external testing `app-info`, `review-info` (the demo
  password is never printed), `submit` and `public-link`. The app is `--app-id` or the App Store Connect record of
  the project's bundle ID; the build is `--build <number>` or the newest upload. Apple's refusals name the role
  needed. ([specs/020-testflight](specs/020-testflight/spec.md))

- `xcross publish [<ipa>] [--wait]` uploads an App Store IPA to App Store Connect without a Mac or Transporter,
  through the Build Upload API: the upload is created, the file reserved, every part sent to Apple's presigned URLs
  (three tries each, resumed by running the command again after an interruption) and committed with its MD5. A
  build number App Store Connect already has stops it first (`publish.duplicate_build`). `--wait` follows the upload
  and the build's processing to `VALID` (Apple's ITMS codes printed; exit 2 on `--timeout`); `--json` streams
  progress and states. Each publish fills `build/xcross-ios/release.json` (app, team, version, build, SDK, git commit,
  IPA SHA-256, upload and processing results). `--transporter` and `--validate` use Apple's Transporter when you
  installed it. `xcross flutter build --build-number auto` picks one past App Store Connect's newest build
  (`APP_STORE_APP_ID` or the bundle ID). ([specs/019-upload-processing](specs/019-upload-processing/spec.md))

- App Store builds without a Mac:
  - `xcross flutter build --release --ipa --export-method app-store` signs the app and its extensions for App Store
    distribution with an App Store Connect team key (Admin or App Manager): an Apple Distribution certificate reused
    across runs (`XCROSS_CERTIFICATE_PRIVATE_KEY` in CI, never revoked), a fresh `IOS_APP_STORE` profile per bundle
    (only xcross's own are replaced), production entitlements. It writes `build/xcross-ios/ipa/<name>.ipa` and
    `build/xcross-ios/archive/Runner.xcarchive` with dSYMs (`release.dsym_unavailable` without `dsymutil`).
    Without a saved team key (or with an individual key) it stops before compiling, and `xcross flutter doctor`
    shows this as "App Store signing", which the Release page's Signing step follows.
  - `xcross release check [<ipa|app>] [--json]` reports the app's configuration and what App Store Connect would
    reject, with `release.*` codes: signing and profile type, SDK below 26, DT keys, version format, bundle ID,
    usage descriptions per plugin, ATS, privacy manifests and required-reason APIs, export compliance, secrets in the
    bundle, the 1024 px icon (alpha channel), launch screen and iPad multitasking.
  - Every build writes Apple's toolchain keys (`DTXcode`, `DTXcodeBuild`, `DTSDKBuild`, `DTPlatformBuild`,
    `DTCompiler`) from the installed SDK; `xcross sdk install` now records the Xcode version the SDK came from.
    `uses_non_exempt_encryption: true|false` under `xcross:` writes `ITSAppUsesNonExemptEncryption`. The doctor
    fails an iOS SDK older than 26.
  - Fixed: SwiftPM resource bundles (`<Package>_<Target>.bundle`) were never copied into the app, so plugins' and
    Firebase's privacy manifests and Google Maps' resources were missing. They are now embedded at the app root,
    where `Bundle.module` and App Store Connect look.

  ([specs/018-app-store-build](specs/018-app-store-build/spec.md))

- `xcross devices --watch [--json]` keeps running and reports the connected iPhones again whenever one is plugged in
  or out (a `devices` snapshot per change), through a pure-Dart usbmuxd `Listen` client (no pymobiledevice3 process
  per event). A stopped device service is reported once and retried every 2 s. XCross Studio runs it in the
  background: the top-bar badge, Devices and Build & Run follow the cable within about two seconds, and say when
  the device service is not reachable. ([specs/017-device-watcher](specs/017-device-watcher/spec.md))

- Push, Firebase and Google Maps work in xcross-built apps (found on an iPhone X with a Firebase/FCM/Maps app):
  - Apps are signed under their **real App ID** by default. The prefixed `XCR-<identity>.<id>` form is now used
    only on request or when another team owns the ID (with a warning that push, Firebase and Sign in with Apple
    will not work). The first-build question defaults to the real ID, builds from the desktop app use it too, and
    `xcross install <ipa>` run inside the project now honours the project's saved choice.
    `xcross project bundle-id [original|prefixed] [--json]` shows or saves it; XCross Studio has an App ID card
    with a switch on the Signing page.
  - `aps-environment` is added when the app uses `firebase_messaging` or the `remote-notification` background mode
    and declares no entitlements (`build.push_entitlement_inferred`).
  - Capabilities are reported truthfully: "Enabled …" only when the App ID's list or the issued profile shows it;
    refusals are `sign.capability_not_enabled` with Apple's reason, and the build goes on. With an Apple ID
    sign-in, push, associated domains, Game Center, Siri and App Groups are now really switched on (through
    Xcode's `updateAppId.action`). Before, Apple's 409 was swallowed and reported as "Enabled", so profiles never
    granted push.
  - `XCROSS_RUNNER=auto` is the new default: the app's own `AppDelegate` is compiled when it has code beyond
    Flutter's template, with the module maps of SwiftPM C-family targets (FirebaseCore, …) and every resolved
    xcframework (GoogleMaps) visible to it; `shim` and `project` still force one runner. The generic runner also
    passes the Google Maps key the AppDelegate gives `GMSServices.provideAPIKey` (literal, or an Info.plist value
    with `$(VAR)` from xcconfig; `build.maps_key_unresolved` otherwise).
  - `xcross flutter doctor` has a "Push notifications" section (entitlement, App ID, Firebase config bundle ID),
    shown as a readiness card in XCross Studio.

  ([specs/016-push-firebase-maps](specs/016-push-firebase-maps/spec.md))

- App Store Connect **individual** API keys: `xcross auth --key-id <id> --private-key <p8>` without `--issuer-id`
  saves an individual key (signed as `sub: user`, no `iss`). A key passed with an Issuer ID that Apple only accepts
  as individual is detected and saved that way. Apple does not let individual keys manage devices, certificates,
  bundle IDs or profiles, so `xcross auth` and `xcross flutter doctor` say that signing needs a Team key or an
  Apple ID. XCross Studio's Signing page has a Team key / Individual key choice (no Issuer ID field for individual
  keys) and a card that explains the limit with "Create a Team key" and "Use Apple ID instead".
  ([specs/015-individual-api-key](specs/015-individual-api-key/spec.md))

- iPhone release builds no longer stop at an unexplained "No prebuilt iOS AOT compiler (gen_snapshot)" error when
  your Flutter is newer than the compilers published for Windows/Linux. The error is now
  `[build.gen_snapshot_unavailable]`, names the Flutter version to use, and points at the new
  `xcross flutter sdk auto`. That command installs that version once (into `<config>/xcross/flutter-sdks/`) and uses
  it for iOS builds only; your own Flutter is not changed.
  - `xcross flutter sdk list|install|use|reset` manage it.
  - `xcross flutter doctor` reports the missing release compiler as ✗ with the fix.
  - XCross Studio explains it in plain words with a one-click "Set up Flutter X for iPhone builds" and "Build
    again" (Build & Run, Overview, setup wizard), and Settings shows which Flutter iPhone builds use.

  ([specs/014-flutter-sdk-compat](specs/014-flutter-sdk-compat/spec.md))

- The desktop app follows the XCross Studio design system ([docs/XCross_Studio_Design_System.md](docs/XCross_Studio_Design_System.md)): dark theme from the doc's tokens (Inter and JetBrains Mono bundled under the SIL OFL), a shell with top bar (project, iPhone), seven destinations (Overview, Build & Run, Devices, Signing, Logs & Debug, Plugins, Settings), a resizable console dock and a status bar (Toolchain / Signing / Device readiness from real doctor checks, running tasks, xcross version); a five-step first-run wizard (environment, Darwin SDK, sign-in, device, first build); command previews, reported build steps, diagnostic cards with the CLI's codes and hints; Apple ID risk and anisette notes; Ctrl+K quick commands, Ctrl+, Ctrl+L Ctrl+J shortcuts; light theme option. ([specs/013-gui-design-system](specs/013-gui-design-system/spec.md))

- `xcross plugin list` shows each iOS plugin as Swift package, podspec only or overridden; `xcross plugin shim <plugin>` drafts `xcross_overrides/<plugin>/<version>/Package.swift` from the podspec (known pods such as Google Maps, Firebase and Pusher mapped to their Swift packages, mixed Swift/Objective-C split into two targets, review notes printed). ([specs/006-plugin-overrides](specs/006-plugin-overrides/spec.md))

- Release packages for the desktop app: Windows per-user installer (Inno Setup) and portable zip; Linux `.deb` (depends on usbmuxd), AppImage and tar.gz. Each bundles the `xcross` CLI next to the app, `LICENSE` and a not-affiliated-with-Apple `NOTICE.txt`. Built and checked by the *Studio GUI* CI workflow on every push. ([specs/009-hardening-1.0](specs/009-hardening-1.0/spec.md))

- Add `xcross sign <ipa|app> [-o <out.ipa>] [--udid <id>]... [--bundle-id <id>]`: re-signs any app with your Apple ID or App Store Connect key (the `xcross install` pipeline, nothing installed) and writes an installable IPA: sorted entries, Unix modes, checked with the `xcross inspect` reader before success. `--udid` registers testers' devices; the development profile also covers every device already on the team (`sign.no_device` when there is none). `xcross install --no-resign` installs such an IPA as it is. Binary Info.plists in third-party IPAs are converted to XML before signing. GUI: "Sign only (.ipa)" on the Device page. ([specs/011-sign-ipa](specs/011-sign-ipa/spec.md), upstream #146)

- Opt-in: `XCROSS_RUNNER=project` compiles the app's own Runner sources (`AppDelegate.swift`, other Swift/Objective-C files of the app target, taken from `project.pbxproj`) into the `Runner` executable instead of xcross's generic runner, so method channels, push setup or `GMSServices.provideAPIKey` in AppDelegate run. xcross supplies `GeneratedPluginRegistrant` (forwarding to the plugins library) and a scene delegate that creates the Flutter window. A compile failure never fails the build: it falls back to the generic runner with `build.runner_project_failed` and the compiler's first errors. ([specs/007-native-runner-code](specs/007-native-runner-code/spec.md), upstream #149)

- `XCROSS_EVENTS=ndjson` makes `xcross flutter build`, `flutter run`, `install` and `flutter doctor` print NDJSON events (`step`, `progress`, `log`, `warning`/`error` with code and hint, `artifact`, `device` without UDID, `check`, `done`); default output is unchanged. The desktop app uses them for a step list, download progress, an issue list, the doctor checklist and an Install button for the exact IPA built. Setup's doctor now runs `flutter doctor` (there is no top-level `xcross doctor`). ([specs/012-build-events](specs/012-build-events/spec.md))

- Plugin overrides: put your own `Package.swift` in `xcross_overrides/<plugin>/[<version>/]` (or `~/.xcross/overrides/`) and xcross builds a podspec-only plugin, or replaces a broken manifest, from a staged copy of the plugin's `ios/` folder, without touching the pub cache. `override.yaml` can limit an override to plugin versions (`versions: ">=1.2.0 <2.0.0"`); the override's iOS floor counts for the deployment target. New codes `build.plugin_override_applied` and `build.plugin_override_invalid`. ([specs/006-plugin-overrides](specs/006-plugin-overrides/spec.md), upstream #145)

- Add the XCross Studio desktop app (`apps/studio`, Flutter, Windows and Linux): Setup (notice, xcross location, doctor, Apple ID / API-key sign-in with 2FA input), Project & Build, Device & Install, Device logs (live table, presets, filters, pause, save, app info ✔/✖, push checklist, crash reports) and Console. It drives the CLI as a subprocess. New `xcross devices [--json]` and `xcross app list [--json]` for its pickers, and `XCROSS_OUTPUT_ENCODING=utf-8` makes xcross write UTF-8 to pipes on Windows. ([specs/008-json-events-gui](specs/008-json-events-gui/spec.md))

- Flutter builds compile the app's asset catalogs into `Assets.car` (a pure-Dart port of xtool-org/AssetKit, MIT): image sets (PNG, JPEG, dark, display-P3), colour sets and the app icon, with the loose icon PNGs and `CFBundleIcons`/`CFBundleIconName` that SpringBoard needs, so the app has its icon without a Mac (Xcode 14 single-size icons are scaled to every slot). The launch storyboard, which cannot be compiled without Xcode, becomes a `UILaunchScreen` with its background colour and centred image from the catalog. Unsupported or broken assets give `build.asset_unsupported` / `build.asset_invalid`, storyboard elements that cannot be shown give `build.launch_screen_approximated`, and the build never fails because of assets. ([specs/004-icon-launch-screen](specs/004-icon-launch-screen/spec.md), upstream #149)

- Flutter builds pass the app's `Runner.entitlements` (the app target's `CODE_SIGN_ENTITLEMENTS`, else `ios/Runner/Runner.entitlements`) to the signer, the same way Compose builds do: push (`aps-environment`), associated domains, App Groups and the rest are enabled on the App ID and embedded when the app is signed by `flutter run` or `xcross install` of an xcross-built IPA. An unreadable file gives `build.entitlements_unreadable` instead of a silent skip. ([specs/003-entitlements-signed-ipa](specs/003-entitlements-signed-ipa/spec.md), upstream #149)

- iOS 15/16 devices are supported: `flutter run --release|--profile` and `compose run` sign and install over USB (installation_proxy), then open the app through a developer disk image from the user's own Xcode (`XCROSS_DDI_DIR` / `~/.xcross/DeviceSupport/<version>/` / `--ddi`; never downloaded) or explain how to open it from its icon. Debug builds on iOS 15/16 stop before building with `device.legacy_debug_unsupported`. New `xcross install <ipa|app>` signs any app with your Apple ID and installs it (Sideloadly replacement). ([specs/005-ios16-install-launch](specs/005-ios16-install-launch/spec.md), upstream #147)

- Add iPhone device logs over plain USB (iOS 16 and 17+, Windows and Linux; no tunnel, no DeveloperDiskImage, no admin rights): `xcross logs` (live syslog with `--app`, `--process`, `--grep`, `--level`, presets `push`/`crash`/`flutter`, `--save`, NDJSON `--json`, UDIDs/tokens/emails masked by default), `xcross app info <bundle-id>` (signer type, team and entitlements as installed, ✔/✖ for push and associated domains) and `xcross crashes list|pull`. The push preset prints a diagnosis (missing entitlement, permission denied, not registered, registered but nothing delivered, delivered). ([specs/010-device-logs](specs/010-device-logs/spec.md))

- `xcross flutter run` and `xcross compose run` check the host device service (Apple Mobile Device Service / usbmuxd), find the device and check its iOS version **before** building, so an unusable device fails in seconds with a stable code (`device.ios_unsupported`, `device.not_found`, `device.host_service_unavailable`, `device.query_timeout`) and a fix hint, and the chosen device is reused after the build. ([specs/002-quick-wins](specs/002-quick-wins/spec.md), upstream #147)
- Bundle versions follow `--build-name`/`--build-number`, then `pubspec.yaml` `version`, then the xcconfig, then `project.pbxproj`, then 1.0.0 (1); a stale `Generated.xcconfig` no longer wins over pubspec, and the build log names the source of each value.
- xcrun lookups skip `clang`/`ld` from directories whose `ld64.lld` cannot link iOS (for example a Swift toolchain added to `environment.PATH`), and doctor plus the build warn with `toolchain.path_linker_unusable`. (upstream #148)
- Podspec-only plugins, skipped asset catalogs, uncompiled storyboards and missing project resources produce one coded warning each (`build.*`) with a hint, plus an end-of-build summary, instead of being skipped silently. (upstream #145, warning part)

- Add `xcross inspect <ipa|app> [--json] [--normalize]`, a read-only report of what is inside an iOS app: Info.plist, entitlements per Mach-O, provisioning profile summary (no device UDIDs), icons, `Assets.car`, launch screen, frameworks and app extensions, as a ✔/✖ summary or deterministic JSON (schema v1). Lives in the new `studio_ext` package. ([specs/001-inspect](specs/001-inspect/spec.md))

## 2.0.9

- Strip native asset frameworks with `llvm-strip` in release and profile builds. Flutter's `install_code_assets` runs the `strip` found on PATH, which on Linux is GNU strip and fails on Mach-O (`file format not recognized`) for code assets such as `super_native_extensions`. ([#141](https://github.com/arxdeus/xcross/issues/141), [#142](https://github.com/arxdeus/xcross/pull/142))
- `xcross setup` on Linux no longer accepts a PATH `ld64.lld` that cannot link for iOS (such as the Swift toolchain's) as the fixed linker, so it installs lld 19+ instead of falling back to an older lld that miswires Objective-C selector stubs. ([#142](https://github.com/arxdeus/xcross/pull/142))

## 2.0.8

- Match a development certificate's serial against the team's certificate list locally. Apple's Developer Services returns an empty page for `filter[serialNumber]`, so after issuing a certificate xcross failed with "Development certificate serial … is not on the team after issuance" and a later run could revoke the team's certificates. ([#140](https://github.com/arxdeus/xcross/pull/140))

## 2.0.7

- Default Apple ID login to Omnisette Mac anisette (`https://mac-ani.jkcoxson.com`, overridable with `--anisette-url` / `XCROSS_ANISETTE_URL`) because Apple’s GSA now rejects Android-identifying clients (`-80046`). `--adi-library-dir` remains a legacy opt-in to local Android ADI.
- Add `xcross compose build --framework` to build only the Kotlin/Native framework of a Compose Multiplatform project, whatever entry point its sources declare. A host app that xcross does not assemble, such as a SwiftPM package built with xtool, links the framework itself; before, a project with a Kotlin `ComposeUIViewController` entry always compiled an Objective-C runner against it, which fails when that entry is not a top-level `MainViewController()` function.
- Pin the Kotlin/Native 2.4.20 archive digests, so `xcross compose setup` installs the compiler for projects on Kotlin 2.4.20 instead of refusing with "No pinned SHA-256 digest".

## 2.0.6

- Reuse an existing pymobiledevice3 pairing for wireless runs. xcross now looks for `remote_<UDID>.plist` in `~/.pymobiledevice3` (and `$XDG_DATA_HOME/pymobiledevice3` on Linux) instead of `$HOME`, so wireless runs on iOS 27+ no longer re-advertise for device-initiated pairing after `lockdown remotepairing --pair` over USB, and saved-pairing reconnects in `xcross tunnel --wifi` work again. ([#132](https://github.com/arxdeus/xcross/pull/132))

## 2.0.5

- Sign in to Apple again after GrandSlam began refusing (-80045) sign-ins whose client info platform does not match the anisette: xcross now presents Android client info matching its Android-derived local anisette. Apple Root CA - G3 is trusted for `gsd.apple.com` on Linux and Windows, and the HTTP 403 Apple now returns for SMS two-factor under Android anisette is explained with a fix (add a trusted Apple device). ([#127](https://github.com/arxdeus/xcross/pull/127))

## 2.0.4

- Find the python that a pipx (or other virtualenv) install of `pymobiledevice3` runs on when starting the RSD tunnel daemon. xcross no longer warns "no python >= 3.13 with pymobiledevice3 found" when the CLI's own interpreter is 3.13 or newer, and candidate interpreters are probed concurrently. ([#121](https://github.com/arxdeus/xcross/issues/121))

## 2.0.3

- Build and run Flutter iOS apps in `--profile` and `--release` mode from Linux, Windows and macOS, x64 and arm64, like `flutter build ios`/`flutter run`: whole-program AOT kernels with flutter_tools' arguments and Dart plugin registrant, `App.framework` from the iOS `gen_snapshot` (on Linux and Windows the compiler [arxdeus/xcross_gen_snapshot](https://github.com/arxdeus/xcross_gen_snapshot) builds for that Flutter version and proves byte-identical to Flutter's), dSYMs next to the `.app`, `--split-debug-info` and `--obfuscate`. Profile runs serve the VM Service for DevTools.
- Revalidate a cached iOS `gen_snapshot` against its release once a day, so a compiler republished for the same Flutter version replaces the cached one; offline builds keep using the verified cache. A manifest schema newer than this xcross asks for `xcross update`.
- Add `xcross flutter precache` to fetch iOS engine artifacts and AOT compilers ahead of the first build, and report in `xcross flutter doctor` whether a release and profile compiler is shipped, cached, pinned, published, or missing.
- Add `xcross cache prune` to remove cached Flutter engine artifacts and AOT compilers for engines no discoverable Flutter SDK uses (`--dry-run`, `--older-than <days>`).

## 2.0.2

- Sign apps that embed resource-only `.bundle` directories, such as `GoogleCastCoreResources.bundle` inside `GoogleCast.framework` or SwiftPM `<Package>_<Target>.bundle` resource bundles. Device runs no longer fail at "Signing app" with "unsupported nested code bundle". These bundles hold no code, so they are sealed as resources of the enclosing bundle like `codesign` does. A `.bundle` that declares an executable or contains Mach-O code is still rejected. ([#118](https://github.com/arxdeus/xcross/issues/118))
- Exit as soon as a command finishes. A leftover stdin subscription, socket, HTTP client, timer or child process (for example after `q` in a run session or an auth failure) no longer keeps the CLI hanging. ([#112](https://github.com/arxdeus/xcross/pull/112))
- Stop Windows plugin builds failing with "could not build Objective-C module 'UIKit'" or "module 'UIKit' is defined in both". The SDK Clang modules the plugins import are now built once before the parallel build, and a build that still loses a module cache race is retried. ([#117](https://github.com/arxdeus/xcross/pull/117))
- Retry a Windows `swift package resolve` that crashes with an access violation (`0xC0000005`) on large plugin graphs. ([#114](https://github.com/arxdeus/xcross/pull/114))

## 2.0.1

- Resolve `packages/<package>/...` shader and font paths in a package's `pubspec.yaml` inside that package's `lib/` directory, like `flutter build`. Apps depending on `material_ui` (for example through `cached_network_image`) no longer fail with "shader not found: packages/material_ui/packages/material_ui/shaders/ink_sparkle.frag". ([#110](https://github.com/arxdeus/xcross/issues/110))

## 2.0.0

- **Breaking:** split `xcross clean` into per-area commands. `xcross flutter clean` clears the project's native asset and SwiftPM build caches (what `xcross clean` used to do, now for both device and simulator targets). `xcross compose clean` clears the Compose project's xcross build output and Kotlin/Native caches. `xcross sdk clean` removes the installed Darwin Swift SDK along with leftover backup and staging copies. The top-level `xcross clean` is gone.
- **Breaking:** rename `xcross auth clear` to `xcross auth clean`. The old spelling now fails with a pointer to the new one.
- **Breaking:** replace `xcross doctor` with `xcross flutter doctor` and `xcross compose doctor`, each checking only the dependencies its own framework needs.
- **Breaking:** require Swift 6.4 or newer on Linux and Windows. `setup`, `sdk install` and `doctor` reject older swift.org toolchains. macOS stays on the Xcode-paired Swift.
- **Breaking:** resolve SwiftPM dependencies natively. xcross no longer clones URL dependencies or rewrites them to path dependencies. SwiftPM resolves the whole plugin graph itself and an xcross manifest compiler applies host fixes to every manifest it evaluates, without touching `Package.swift`.
- Run on a device without a network after the first online run. When Apple's Developer Services cannot be reached, or the saved Apple ID session has expired, xcross signs with the cached certificate and provisioning profile for that app instead of failing, and says what to do when the cache cannot cover the run (no profile yet, device not in it, expired). `XCROSS_OFFLINE=1` skips Apple entirely. A 20-second cap on the Apple ID access check keeps a dead network from stalling the run.
- Ask on an app's first device build whether to register the original bundle id or an `XCR-` prefixed one, and save the answer as `bundle_id` under `xcross:` in `pubspec.yaml` (or in `xcross_project.yaml` for Compose). CI and IDE debug sessions use the saved value, falling back to the prefixed id only when nothing is saved. `XCROSS_BUNDLE_ID=original|prefixed` overrides it for a run.
- Stop reusing Flutter SDK engine artifacts left over from an older engine. After a Flutter upgrade on Linux or Windows, `flutter precache --ios` artifacts are never refreshed, so xcross shipped a stale `Flutter.framework` that rejected the app kernel with "Invalid SDK hash" and showed a black screen. xcross now reuses SDK iOS artifacts on Linux and Windows only when the framework's `FlutterEngine` revision matches the SDK engine (Flutter rewrites `ios-sdk.stamp` there without refreshing the files, so the stamp is only trusted on macOS). Host snapshots and the patched SDK are checked against `flutter_sdk.stamp`. Mismatched artifacts are fetched into the xcross cache with a one-time warning naming the refresh command, and a Dart SDK from another engine is flagged too. ([#93](https://github.com/arxdeus/xcross/issues/93))
- Group doctor output into project, toolchain, and deployment sections with a status header, aligned rows, dimmed locations, and a spinner while each section runs.
- List every Compose requirement individually in `xcross compose doctor`, and report a missing Kotlin/Native download as a warning since the first build fetches it.
- Build, sign, self-update and install natively on Windows ARM64, including Apple ID login through ADI. `install.ps1` picks the ARM64 asset even from an emulated x64 PowerShell, and releases ship `xcross-windows-arm64.zip`.
- Compile Flutter shaders with the host `impellerc` like `flutter build`, so ink sparkle, stretch and app or package `shaders:` entries load at runtime. Tree shake icon fonts in profile and release builds behind `--[no-]tree-shake-icons`.
- Expand SwiftUI, `#Preview` (including UIKit and widget previews) and FoundationModels macros through the Open Apple Macros server. Release bundles ship it prebuilt from the pinned [arxdeus/OpenAppleMacros](https://github.com/arxdeus/OpenAppleMacros) fork, so the first build no longer compiles swift-syntax. Source and `pub` installs build the pinned revision once and cache it. `tools.OpenAppleMacrosServer` points xcross at another server.
- Split Windows setup into winget, Scoop, Chocolatey and direct scripts, confirm setup scripts before running them, and install the pinned LLVM into `XCROSS_LLVM_DIR` when another LLVM is on `PATH`.
- Preserve Flutter package licenses across iOS builds, for apps with and without native hooks, keeping compiler definitions and flavors. ([#94](https://github.com/arxdeus/xcross/pull/94))
- Keep the banner link visible on dark Linux terminal themes. ([#80](https://github.com/arxdeus/xcross/issues/80))

## 1.5.1

- Resolve the Dart launcher per host platform in `xcross update`, and harden launcher resolution and batch launches.
- Run integration and Compose workflows on every push and fork PR without cancelling running jobs.

## 1.5.0

- Build and run real Compose Multiplatform apps on a device from Linux and Windows: stage Compose resources, honour static frameworks, keep sibling project klibs in the link, expand `$(VAR)` build settings in Info.plist, and find nested `iosApp` layouts.
- Speed up Compose debug links with per-library Kotlin/Native compiler caches, reuse the Gradle daemon, and compile plus dump dependencies in one Gradle invocation.
- Link Compose apps on Windows with the official LLVM installer: fall back to `llvm-ar` when `llvm-libtool-darwin` is missing, and drop Kotlin/Native platform klibs Gradle resolves from a second distribution.
- Link the iOS compiler runtime into the Compose runner, fixing `___isPlatformVersionAtLeast` on Linux.
- Sign an App ID the team already owns under its real bundle id instead of an `XCR-` qualified one, so Sign in with Apple, passkeys, push and associated domains keep working.
- Enable the App ID capabilities a Compose app's entitlements declare, for the app and its extensions, and sign with the app's declared entitlements where the profile grants a wildcard.
- Only delete provisioning profiles xcross created, or a lone development profile occupying the App ID's only slot. Release profiles are never deleted.
- Repair Windows Flutter iOS builds and debug sessions, recover missing SwiftUI `State` macros in staged sources, and reject native asset framework symlinks that escape the framework.
- Make `examples/flutter_example` build on Linux: answer `xcrun --version`, shim `ar`, and prefer a clang new enough for the SDK's libc++.
- Rewrite `arm64e.x1` stub targets so Xcode 27 SDKs link with released `ld64.lld`.
- Render dim and TUI text readably on dark terminal themes.
- Add a Compose integration workflow that builds `examples/compose_app` on Linux and Windows.

## 1.4.5

- Stop cold Flutter iOS builds deadlocking on `git cat-file --batch`: read the process output while the requests are still being written, so a symlink-heavy SwiftPM checkout no longer fills the pipe buffer and hangs the build indefinitely.
- Cache SwiftPM plugin builds on `main` under one stable key per toolchain, so a push refreshes a single cache entry instead of accumulating one per run.

## 1.4.4

- Report the reason behind an app's `SIGABRT` on device: stream the device log over plain usbmux, always retain a bounded history, and print the abort reason (or the last device lines) with the crash.
- Bump `archive` from 4.2.0 to 4.3.0.
- Document the configuration section and warn against using a primary Apple ID for xcross auth.

## 1.4.3

- Speed up incremental Flutter iOS builds substantially: only prebuild the Swift interop targets the aggregate can actually reach, skip the interop re-plan when the build manifest already carries the search paths, and derive generated-file timestamps from their content so staged sources and vendored manifests stop invalidating SwiftPM on every run.
- Reuse one Flutter tool workspace across builds instead of a per-build temporary directory, and stop clearing the native-assets output, so `flutter assemble` no longer re-runs every build hook each time.
- Stop bounding SwiftPM resolve and `swift build` by wall clock, and drop the integration job timeout: a cold dependency graph is slow rather than stuck, and the cap turned that into a failure.
- Surface Apple rate limits, unify the `akd` client identity, and disable GrandSlam connection reuse to avoid proof-stage HTTP 429.

## 1.4.2

- Point GrandSlam anisette `X-MMe-Client-Info` at `akd/1.0` instead of an Xcode identity.
- Prebuild planned Swift interop targets and re-plan the Swift build with those search paths, so `cloud_firestore` finds `FirebaseFirestore` on a cold Windows build.
- Bound SwiftPM resolve, git clones, and binary-artifact downloads, fail instead of hanging on invisible git credential prompts, and surface SwiftPM's stdout diagnostic when resolve fails.

## 1.4.1

- Vendor transitive SwiftPM dependencies faithfully: keep `.package(path:)` unnamed for manifests older than swift-tools-version 5.2, and initialize git submodules in vendored checkouts (fixes `flutter_image_compress`).
- Preserve chained-fixup metadata when repairing Objective-C selrefs, fixing a launch crash in `dyld4::PrebuiltObjC` on apps linked with lld 19 or newer.
- Install lld from apt.llvm.org (`llvm.sh`) in the apt setup script instead of the distro `lld` package, register an unversioned `ld.lld` through update-alternatives, and verify the linker in the dnf and pacman ones.
- Report the resolved linker version in `xcross doctor`.

## 1.4.0

- Add `xcross config` with an interactive terminal config editor and a dynamic, script-driven setup flow.
- Support local installer builds and avoid running setup during installation.
- Prefer build tool shims in `xcrun` resolution and use native executable compiler aliases for Windows native assets.
- Repair Objective-C fast stubs sharing a selref when one stub can relocate, fixing incremental SwiftPM relinks on Linux.
- Vendor URL dependencies declared by vendored SwiftPM packages using cached git checkouts, including transitive package manifests.
- Improve cross-platform SwiftPM dependency resolution, binary artifact recovery, symlink materialization, and long-path staging.
- Reuse content-validated SwiftPM plugin builds and stabilize interop flags across build retries.

## 1.3.6

- Repair Kotlin native-asset builds on Linux, including Objective-C small-stub arguments and Mach-O fast-stub rewriting.
- Strengthen release update verification, rollback, and recovery of missing native libraries.

## 1.3.5

- Normalize native asset framework install names and Mach-O dylib references for correct runtime loading.
- Cache SwiftPM build identities and artifact-junction capabilities to reduce repeated build work.
- Strengthen toolchain and SDK cache invalidation using filesystem change metadata.
- Update the examples repository reference.

## 1.3.4



- Add `xcross clean` to clear project-local native asset and SwiftPM build caches while preserving shared caches and unrelated build output.
- Expand `xcross doctor` with Windows iOS tool checks and remediation guidance.
- Prevent source-update cleanup from deleting active temporary directories owned by concurrent xcross operations.
- Update the examples repository reference.

## 1.3.3

- Add `xcross doctor` with cross-platform checks and remediation guidance for required and optional tooling.

## 1.3.2

- Stabilize Flutter iOS builds on Windows with native-asset tool shims, `xcrun` compatibility, shorter SwiftPM workspaces, reusable staged builds, and resilient transitive binary-artifact recovery.
- Simplify SwiftPM artifact handling and improve release installation, tool-output parsing, linker argument forwarding, and cross-platform integration coverage.
- Move examples to the dedicated examples repository and update package dependencies.

## 1.3.1

- Fix Flutter iOS native-asset builds on Windows by using the resolved LLVM Clang as the `cc` host compiler and falling back from unavailable `llvm-otool` to `llvm-objdump` with compatible Mach-O inspection arguments.

## 1.3.0

- Expand Flutter iOS compatibility with SwiftPM Firebase support, packaged native assets, dependency fonts, resilient Swift interop targets, correct UIScene window attachment, and support for read-only Flutter SDKs.
- Improve Flutter launch and hot-reload reliability with transport-specific VM Service binding, immediate session controls while hot reload prepares, clearer diagnostics, and safer device log streaming.
- Make wireless device sessions more reliable by bounding Developer Disk Image mounts, shortening timeout recovery, and restarting stale Wi-Fi tunnel daemons.
- Improve update cleanup so stale source-build clones are always removed.

## 1.2.2

- Phase release and update identity work so source-ref installs report injected normalized refs, tagged release archives report the release tag, and unreleased builds stay clearly marked until the next official update.
- Build Linux and Windows release artifacts through the shared compile-time identity wrapper, remove the hardcoded dev version fallback from stamped release automation, and keep unreleased installs returning to the latest official release.

## 1.2.1

- Replace the old tag-only update selector with `--ref`, so release tags still install verified release assets while branch and commit refs build from source before the same atomic install step.

## 1.2.0

- Add first-class wireless device support with `xcross tunnel --wifi` and
  `xcross flutter run --wifi`. xcross can bootstrap RemotePairing over a trusted
  USB connection, reconnect saved wireless pairings, or advertise the host for
  cable-free pairing on iOS 27+, then start a TCP RSD tunnel and mount the
  Developer Disk Image automatically. (#29)
- Discover wireless devices through `pymobiledevice3 tunneld`, route installs,
  app lookup, DDI mounting, and launches through the correct RSD transport, and
  surface actionable pairing, mDNS, Python, privilege, and tunnel diagnostics.
  (#29)
- Launch the exact account-qualified bundle id produced during signing and
  installation instead of guessing from installed apps. This avoids attaching
  to stale xcross builds or production/TestFlight builds with the same base
  bundle id, which could cause kernel-version errors or denied debugging. (#28)
- Complete App Groups support for share and action extensions. Xcode 16 synced
  folders and localized resources are handled correctly, Swift module names
  match extension principal classes, host and extensions use the same group and
  callback URL scheme, and Apple ID signing creates and attaches groups
  automatically. (#27)
- Treat the issued provisioning profile as the source of truth for App Group
  entitlements. App Store Connect API keys can use a group attached manually by
  passing `XCROSS_APP_GROUP`, while unsupported group creation no longer blocks
  an otherwise valid install. (#27)
- Retry Linux package installation after refreshing a stale APT index. (#29)

## 1.1.2

- Build, embed, sign and install iOS **app extensions** (share and action
  extensions). Extension targets are read from the Xcode project, compiled
  against the Darwin SDK, embedded at `<App>.app/PlugIns/<Name>.appex`, and
  each is given its own App ID and provisioning profile. This is what lets
  plugins such as `receive_sharing_intent` appear in the iOS share sheet.
  See `docs/app-extensions.md`. (#23)
- Resolve the bundle id from the **application** target rather than the first
  `PRODUCT_BUNDLE_IDENTIFIER` in `project.pbxproj`. A project with a share
  extension usually lists the extension's first, so xcross signed, installed
  and launched the extension instead of the app, showing a blank screen. (#23)
- Expand `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)` from the
  application target's build settings. The default `ios/Runner/Info.plist`
  references both, so apps were shipping a literal `$(MARKETING_VERSION)` as
  their version string. Embedded extensions inherit the app's versions, which
  iOS requires them to match.
- Register App Groups declared by an app or its extensions, qualified per
  account (`group.XCR-<TEAM>.…`) because App Group ids are globally unique.
  Enabling the capability on the App IDs is still a manual step on
  developer.apple.com; xcross reuses an existing group, so the next run picks
  it up.

## 1.1.1

- Detect a Swift toolchain that no longer matches the installed Darwin SDK.
  `xcross sdk install` patches the SDK with the selected toolchain's clang
  headers, so switching Swift afterwards made every plugin build fail with
  "this SDK is not supported by the compiler" and no mention of the SDK.
  The toolchain is now recorded at install time and checked before building,
  with a message naming the cause and the command that fixes it.
- Require Swift on `PATH` before `xcross setup` and `xcross sdk install`,
  which previously failed only after a sudo prompt and a full package
  transaction, or after extracting tens of gigabytes.
- Verify the Xcode archive before `xcross sdk install` removes the previous
  SDK, so a wrong path or a partial download no longer leaves the host with
  no SDK at all.
- Fail the Windows release job on failing tests, and fix the 7 Windows-only
  test bugs that gap had been hiding.

## 1.1.0

- Add Compose Multiplatform support: `xcross compose setup`, `xcross compose
  build`, and `xcross compose run` build, sign, install, and launch Kotlin
  Multiplatform iOS frameworks and `.app` bundles from Linux and Windows,
  with a `--watch` rebuild loop and fingerprinted builds that skip `konanc`
  when nothing changed.
- Provision and patch the Kotlin/Native toolchain for cross-host iOS builds:
  spoof Apple host checks, stage an Apple toolchain and the real compiler-rt
  archives, keep dependency resolution off the network, and disable
  Apple-only debug transparent stepping.
- Pass explicit `-arch` and `-platform_version` through the Swift runner
  link, and degrade a missing Windows `dsymutil` to a no-op.
- Build `sharedDarwinSource` Flutter plugins from their `darwin/` directory,
  and warn instead of silently dropping a plugin whose iOS manifest is
  missing.
- Generate and run the Dart plugin registrant, so federated plugins that
  register through `dartPluginClass` no longer fail at first use.

## 1.0.5

- Enhance Windows SwiftPM support and normalize staged plugin manifests.
- Synthesize fallback Clang/Swift modules for SwiftPM checkouts, including
  nested modules, module shims, and Swift interop headers for Objective-C
  and Swift consumers.
- Infer fallback module topology and linkage from sources, and preserve
  source fallback module names across rebuilds.
- Implement `#Preview` through a compiler plugin instead of patching plugin
  sources.
- Make Flutter plugin staging incremental, staging only iOS-reachable
  package entries, pruning entries the filter no longer stages, and skipping
  development-only trees and `pigeons/`.
- Keep binary files out of the sync transform, and preserve checkout symlink
  identity and materialized checkout placeholders.
- Forward symlinked headers and avoid a Clang module lock deadlock on
  Windows.
- Skip cross-host Swift interface verification.

## 1.0.4

- Resolve Flutter package configs from workspace roots.
- Pin the iOS SDK and sysroot for Flutter plugin linking, and expose Flutter
  headers to Objective-C plugins.
- Propagate the project's iOS deployment target through SwiftPM builds and
  generated app metadata.
- Normalize SwiftPM linker flags and stage normalized manifests for plugin
  builds.
- Skip generated imports for FFI-only Flutter plugins.

## 1.0.3

- Teach `xcross setup` to install host requirements on macOS via Homebrew
  and to verify the Windows toolchain more clearly.
- Find Homebrew LLVM/`lld` installs on Apple Silicon and Intel Macs when
  resolving Darwin SDK link tools.
- Recommend using a separate Apple account for auth in the README.

## 1.0.2

- Recover automatically when `tunneld` refuses to create an RSD tunnel:
  `xcross flutter run` now mounts the Developer Disk Image and starts a
  lockdown tunnel itself instead of stalling 60s and silently degrading to
  the userspace transport.
- Say why hot reload is unavailable, and answer `r`/`R` with that reason
  instead of ignoring the keypress.

## 1.0.1

- Add `xcross auth clear` to sign out: deletes the saved App Store Connect
  key, the Apple ID session and its machine attestation state, and every
  certificate, private key, and provisioning profile xcross minted.
- Reject unexpected positional arguments to `xcross auth` instead of silently
  starting an Apple ID login.
- Accept certificates and profiles Apple minted up to an hour ahead of a
  lagging host clock, and name both clocks in the error when it is worse.

## 1.0.0

- Build, sign, install, launch, and hot-reload Flutter iOS apps natively on
  Linux and Windows.
- Support Swift Package Manager Flutter plugins on both hosts.
- Apple ID/password login on Linux and Windows via Android ADI / Anisette, or
  App Store Connect API keys on either host.
- Remove the xtool runtime completely; xcross now owns Darwin SDK setup and
  uses the native device pipeline.
- Add `xcross --version`, stamped from the git tag at release build time.
- Add `xcross update` to self-update an installed xcross from the latest
  GitHub release, verified against the release's `SHA256SUMS.txt`.
- Print a cached, once-a-day "update available" hint on other commands;
  disable it with `XCROSS_NO_UPDATE_CHECK`.
