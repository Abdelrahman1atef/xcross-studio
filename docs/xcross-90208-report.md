# xcross release check gap: App Store Connect 90208 for native-asset frameworks

## Observed failure

`xcross release check` passed, but `xcross publish --wait --json` failed during upload of WasherClean 1.10.0 (32), bundle ID `Haggag.WasherClean`, with this exact output:

```text
[publish.upload_failed] App Store Connect rejected the upload: 90208 Invalid Bundle. The bundle washerclean.app/Frameworks/cupertino_http.framework does not support the minimum OS Version specified in the Info.plist.; 90208 Invalid Bundle. The bundle washerclean.app/Frameworks/objective_c.framework does not support the minimum OS Version specified in the Info.plist..
hint: `xcross release check` has no rule for 90208 yet; the check passing does not mean this is fixed. Keep the exact message, it is what a new rule is written from.
```

The failed upload was recorded in `build/xcross-ios/release.json` with state `FAILED` at `2026-11-06T18:49:05.637172Z`. The rejected IPA was subsequently replaced by a new local build, so the values below are from inspection of the original archive before rebuilding. The installed xcross CLI now reports `2.0.9`; the version that ran the original `publish` command was not captured.

## Metadata inspected in the rejected archive

| Bundle | `Info.plist` `MinimumOSVersion` | Mach-O `LC_BUILD_VERSION` platform | Mach-O minimum |
| --- | --- | --- | --- |
| `washerclean.app` | `15.0` | — | — |
| `cupertino_http.framework` | `13.0` | `ios` (device) | `15.0` |
| `objective_c.framework` | `13.0` | `ios` (device) | `15.0` |

The two framework plists claimed iOS 13.0 support, while their binaries required iOS 15.0. The binaries were for iOS devices, so the simulator-platform failure mode was **not** observed in this upload. The app's Runner configurations all specified iOS 15.0. `ios/Podfile` specified iOS 16; changing deployment targets was not needed for the verified local fix.

## Reproduction and local fix

The app declared `cupertino_http: ^3.1.0` and `dio_compatibility_layer: ^0.1.1`. Its only use of `CupertinoClient` was behind `kDebugMode && Platform.isIOS`, as a simulator networking workaround. Despite that runtime guard, the release IPA embedded `cupertino_http.framework` and its transitive `objective_c.framework`.

Removing the debug-only adapter and both dependencies, then running `flutter pub get` and `xcross flutter build --release --no-pub`, produced a local release app without either framework. `flutter analyze` and the focused Dio tests passed. App Store Connect acceptance of the new build has **not** yet been verified.

## Suggested `xcross release check` rule

Before upload, inspect the **final signed IPA**, not just dependency metadata:

1. Read `Payload/*.app/Info.plist` and every embedded `Frameworks/*.framework/Info.plist`.
2. For each framework executable and architecture slice, read `LC_BUILD_VERSION` (or legacy `LC_VERSION_MIN_IPHONEOS`).
3. Report an error if a device IPA embeds a simulator or other non-iOS-device slice; if the framework plist claims an OS version below the binary's minimum; or if the binary minimum exceeds the app's declared minimum.
4. Include the framework path and all three values (app minimum, framework plist minimum, binary platform/minimum) in the diagnostic. Recommend updating/removing the responsible dependency or fixing framework packaging. Avoid suggesting a deployment-target increase when the observed defect is a plist/binary mismatch.

Suggested rule ID: `release.framework_ios_compatibility`. Map the diagnostic to App Store Connect error `90208`, retaining Apple's exact message when available.

Related references: [Apple's `MinimumOSVersion` documentation](https://developer.apple.com/documentation/BundleResources/Information-Property-List/MinimumOSVersion) and [dart-lang/native issue #2989](https://github.com/dart-lang/native/issues/2989).
