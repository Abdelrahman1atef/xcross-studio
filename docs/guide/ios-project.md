# Your iOS project

[← xcross README](../../README.md) · [All guides](README.md)

## Your own AppDelegate code

When `ios/Runner/AppDelegate.swift` (or `.m`) has code beyond Flutter's template, such as `GMSServices.provideAPIKey`
or Firebase setup, xcross compiles the app target's own Swift/Objective-C sources into the `Runner` executable
(`XCROSS_RUNNER=auto`, the default; Swift toolchain required). A template AppDelegate keeps xcross's faster generic
runner. `XCROSS_RUNNER=project` or `shim` forces one or the other:

```sh
XCROSS_RUNNER=shim xcross flutter run --release      # PowerShell: $env:XCROSS_RUNNER = 'shim'
```

The app's code sees every plugin module, including SwiftPM C-family targets (`import FirebaseCore`) and binary
frameworks (`import GoogleMaps`). Even with the generic runner, the Google Maps key the AppDelegate passes to
`GMSServices.provideAPIKey` (a literal, or an Info.plist value such as `$(MAPS_API_KEY)` from xcconfig) is applied at
launch; `build.maps_key_unresolved` names a form xcross cannot read.

xcross supplies `GeneratedPluginRegistrant` (plugins are one Swift package) and a scene delegate that creates the
Flutter window (`Main.storyboard` cannot be compiled), so put custom code in `AppDelegate`, not `SceneDelegate`. If the
sources do not compile, the build continues with the generic runner and prints `build.runner_project_failed` with the
compiler errors. See [specs/007-native-runner-code](../../specs/007-native-runner-code/spec.md).

## App extensions

Share and action extensions are built, embedded under `PlugIns/`, signed with their own provisioning profiles and installed alongside the app, so plugins like [receive_sharing_intent](https://github.com/KasemJaffer/receive_sharing_intent) put your app in the iOS share sheet. No configuration needed.

Sharing data back to the app needs an App Group. Signed in with an Apple ID, xcross registers and attaches it for you. With an App Store Connect API key, Apple's public API cannot manage App Groups at all, so attach one yourself and pass `XCROSS_APP_GROUP`. See **[docs/app-extensions.md](../app-extensions.md)**.

## Bundle identity

The bundle id is read from the Flutter iOS project, using the same sources as Flutter's own tooling on non-macOS hosts:

1. A literal `CFBundleIdentifier` in `ios/Runner/Info.plist` (no `$(…)` variables), otherwise
2. the `PRODUCT_BUNDLE_IDENTIFIER` of the **application** target in `ios/Runner.xcodeproj/project.pbxproj`.

Step 2 reads the application target specifically: a project with app extensions declares several `PRODUCT_BUNDLE_IDENTIFIER`s, and the extension's often comes first in the file.

The packed `.app`'s `Info.plist` is always derived from `ios/Runner/Info.plist` when present. `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)` are expanded from the application target's build settings, and embedded extensions inherit those versions, as iOS requires.

### App ID on device

xcross signs the app under its **real App ID** (the project's bundle id) unless told otherwise:

- **Original** (`com.example.app`, the default) is what push, Firebase, Sign in with Apple, passkeys, associated domains and the App Store record are bound to. If another team already owns it, xcross falls back to the prefixed id and warns that those services will not work.
- **Prefixed** (`XCR-<TEAM>.com.example.app`) never collides with another team that owns the same bundle id.

On an app's first device build for your team, `xcross flutter run` and `xcross compose run` on a terminal ask, with the real id as the default answer. `xcross project bundle-id` shows the choice and `xcross project bundle-id original|prefixed` changes it (XCross Studio: Signing → App ID).

The answer is saved to the project so it can be committed: under `xcross:` in `pubspec.yaml` for Flutter, or in `xcross_project.yaml` for projects without a pubspec (Compose). If `xcross_project.yaml` exists, it is used even in a Flutter project.

```yaml
# pubspec.yaml
xcross:
  bundle_id: original # or prefixed
```

The order of precedence is: `XCROSS_BUNDLE_ID=original|prefixed` for a single run, then the saved `bundle_id`, then whichever App ID already exists on the team, and only then the question.

CI, IDE debug sessions and XCross Studio cannot be asked, so they use the saved `bundle_id` from `xcross_project.yaml` or `pubspec.yaml`. When nothing is saved and the team has no App ID yet, they register the real id and save nothing. `xcross install <ipa>` run in the project folder uses the project's saved choice for that project's IPA.

Push needs `aps-environment`: when the app uses `firebase_messaging` or the `remote-notification` background mode and declares no entitlements, xcross adds it (`build.push_entitlement_inferred`). `xcross flutter doctor` shows a "Push notifications" section (entitlement, App ID, and the bundle id in `GoogleService-Info.plist` / `firebase_options.dart`).

<!-- studio: 018 -->
