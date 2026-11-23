# App Store, icons and splash screens

[← xcross README](../../README.md) · [All guides](README.md)

With an App Store Connect **team** key (Admin or App Manager role):

```sh
xcross release preflight        # problems the project already shows, in seconds (also run by the build below)
xcross flutter build --release --ipa --export-method app-store
xcross release check            # what App Store Connect would reject, before you upload
xcross publish --wait           # upload (Build Upload API) and wait for Apple's processing
xcross testflight status        # processing and beta states; group create/add, testers, what-to-test, submit
xcross appstore metadata push   # App Store page texts; screenshots push, attach, submit --dry-run, status
xcross project version --bump patch   # or: xcross project version 1.2.0 --build 14
xcross release gate             # flutter analyze + flutter test (warnings and infos only fail with --fatal-warnings/--fatal-infos)
```

`xcross flutter build --export-method app-store` runs the preflight first: errors stop it before anything compiles,
warnings are shown (`--no-preflight` skips it). Issues xcross can fix carry the command in `release check --json`
(`fix`), such as `xcross privacy init` for a missing privacy manifest.

XCross Studio's **Release** page runs these steps in order, and **Archives** lists the archives.

<!-- studio: 023 -->
**App icon.** `xcross icons check` lists every icon size (notification, Settings, Spotlight, home screen, iPad, App
Store) and reports an App Store icon with an alpha channel, missing or wrong-size files, and a logo the rounded
corners cut, off centre or too small. `xcross icons generate logo.png --padding 12 --background "#0A84FF"` writes
the whole set from one image without an alpha channel (the old set goes to `.xcross/icon-backups/`). The desktop
app's **App icon** page previews the icon as iOS masks it. See [specs/023-icon-studio](../../specs/023-icon-studio/spec.md).

**Icon and splash studio.** The same page opens a studio with a live preview per target: image, text or symbol as the
source; foreground, effect, padding per side and trim; colour, gradient, mesh or image background with a texture; a
badge; and Android's file name, shape and themed icon. The CLI does the drawing:

```bash
xcross icons generate logo.png --padding 10,14,18,14 --background-type gradient --background "#0A84FF" \
  --background2 "#5E5CE6" --targets ios,android,web,macos --save-config
xcross icons generate logo.png --targets all --zip app-icons.zip   # nothing in the project changes
xcross splash generate logo.png --background "#FFFFFF" --dark-background "#000000" --logo-width 120 \
  --margin 0,0,40,0 --save-config
xcross splash generate logo.png --logo-width 200 --ipad-logo-width 300 --android12-icon-width 120 \
  --android12-icon-background "#FFFFFF"                            # a size for each kind of device
xcross splash check
xcross icons generate --config && xcross splash generate --config  # from the committed xcross_assets.json
```

Commit `xcross_assets.json` and `.xcross/assets/` so a team regenerates the same files. Replaced files go to
`.xcross/icon-backups/`. See [specs/024-icon-splash-studio](../../specs/024-icon-splash-studio/spec.md). In XCross Studio, the
App icon page and the studio's `All screens` tab show both on every screen size
([specs/026-all-screens-preview](../../specs/026-all-screens-preview/spec.md)). iOS keeps showing the splash it saved: to see a
new one, restart the iPhone and install again. Deleting the app is not enough.

The build signs the app and its extensions with an Apple Distribution certificate and App Store profiles, and writes
`build/xcross-ios/ipa/<name>.ipa` and `build/xcross-ios/archive/Runner.xcarchive` (with dSYMs when `dsymutil` is on
PATH). The certificate is reused across runs; in CI pass its private key (PEM) in `XCROSS_CERTIFICATE_PRIVATE_KEY`.
Answer the export compliance question once with `uses_non_exempt_encryption: false` (or `true`) under `xcross:` in
`pubspec.yaml`. `xcross release check [--online] [--json]` lists signing, SDK, SwiftSupport, Info.plist, permission,
privacy-manifest, icon and iPad issues with `release.*` codes; `--online` also asks App Store Connect (read-only) whether
the app, build number, version and App ID capabilities are accepted. `xcross publish` resumes an interrupted upload, refuses a build number App Store
Connect already has, and writes `build/xcross-ios/release.json`; `--build-number auto` on the build picks the next
number. See [specs/018-app-store-build](../../specs/018-app-store-build/spec.md) and
[specs/019-upload-processing](../../specs/019-upload-processing/spec.md).
