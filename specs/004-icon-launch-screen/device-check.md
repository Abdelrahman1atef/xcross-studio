# Device check: 004 (to run on the iPhone X, iOS 16.7.16)

Prerequisites: `xcross auth` done; a Flutter project with the template `Assets.xcassets` (or your own icon) and
`LaunchScreen.storyboard`. For a visible splash, put a non-transparent `LaunchImage` in `LaunchImage.imageset` (the
template image is a 1×1 transparent PNG) and/or change the storyboard background colour.

| # | AC | Command | Expected | Result |
|---|---|---|---|---|
| 1 | SC-002 | `xcross flutter build ipa`, then `xcross inspect build/xcross-ios/<name>.ipa` | `Assets.car` present, icons ✔ resolved, launch screen `UILaunchScreen` with image from the asset catalog | ✅ Windows host 2026-11-01, Flutter template app, debug build (release blocked: no Windows gen_snapshot for Flutter 3.47.8): `Assets.car` 344 KB, AppIcon20/29/40… resolved, `UILaunchScreen` image `LaunchImage` from the asset catalog |
| 2 | AC-004-1 | `xcross flutter run --release` | the home screen shows the app icon (not the blank grid) | ⏳ |
| 3 | AC-004-2 | delete the app, reboot the phone, install again, open it | the launch screen shows the background colour and the launch image | ⏳ |
| 4 | AC-004-2 | open a screen that uses `Image.asset` / a plugin reading a catalog image (if any) | unchanged (Flutter assets are not catalog images) | ⏳ |
| 5 | AC-004-3 | add an SVG image set, build | `warning: [build.asset_unsupported] …`; build continues | ⏳ |
| 6 | AC-004-5 | replace the app icon with a single 1024 universal icon (Xcode 14 style), build and install | icon shows | ⏳ |
| 7 | AC-004-1 | upload an App Store build, then read `GET /v1/builds/{id}/icons` and fetch the image of each record | record #0 (`Placeholder.mill` template) is the app's rendered icon, not Apple's grey grid | ✅ App Store Connect API 2026-11-08, a Flutter app, Windows host: 1.10.0 (32) built before the fix returned the grey grid (106,565 bytes); Xcode 1.10.1 (1) returned the logo (333,397 bytes); 1.10.2 (1) built after the fix returned the logo (333,397 bytes, same picture). The App Store Connect website itself was not looked at yet |

If row 2 fails but `xcross inspect` is green, check the loose `AppIcon60x60@2x.png` inside the `.app` (SpringBoard's
fallback). If row 3 fails, run `xcross logs --process SpringBoard --grep -i launch` while opening the app and attach it.
