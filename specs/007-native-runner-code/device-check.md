# Device check: 007 project Runner (iPhone X, iOS 16.7.16, Windows host)

Prerequisites:
- the Darwin SDK and Swift toolchain are installed (`xcross setup`; `xcross doctor` shows both ✔);
- `xcross auth` has been run;
- you have a Flutter test project.

Add a method channel to its `ios/Runner/AppDelegate.swift`:

```swift
func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
  GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "XcrossCheck")!
  let channel = FlutterMethodChannel(
    name: "xcross/check", binaryMessenger: registrar.messenger())
  channel.setMethodCallHandler { _, result in result("native ok") }
}
```

Then call `const MethodChannel('xcross/check').invokeMethod('ping')` from Dart and show the result on screen.

PowerShell: `$env:XCROSS_RUNNER = 'project'` (unset with `Remove-Item Env:XCROSS_RUNNER`).

| # | AC | Command | Expected | Result |
|---|---|---|---|---|
| 1 | AC-007-1 | without `XCROSS_RUNNER`: `xcross flutter run --release` | same as before (generic runner); the channel call fails with `MissingPluginException` | ⏳ |
| 2 | AC-007-2, 3 | with `XCROSS_RUNNER=project`: `xcross flutter run --release` | build log shows `Runner: compiling the project sources (2 Swift, 0 Objective-C)`; no `build.runner_project_failed` | ⏳ |
| 3 | AC-007-7 | open the app from its icon | Flutter UI appears (window from `XcrossSceneDelegate`); the channel shows "native ok" | ⏳ |
| 4 | AC-007-4 | `xcross app info <bundle-id>` and `xcross logs --app Runner --duration 10` while opening | plugins work (e.g. shared_preferences); no crash on launch | ⏳ |
| 5 | AC-007-5 | add a syntax error to AppDelegate.swift and build again | `warning: [build.runner_project_failed] …` with the swiftc error line; the build succeeds with the generic runner | ⏳ |
| 6 | AC-007-6 | an app with the old `GeneratedPluginRegistrant.register(with: self)` AppDelegate | `[build.runner_legacy_registration]`; plugins still work | ⏳ |
| — | Linux | same rows on Ubuntu 24.04 | | ⏳ deferred |

Build-level evidence (Windows host, 2026-11-01, Swift 6.4.2, LLVM 23.1.4, Darwin SDK from Xcode 27.1, Flutter template app, `XCROSS_RUNNER=project xcross flutter build --debug --ipa`): `Runner: compiling the project sources (2 Swift, 0 Objective-C)`, no `build.runner_project_failed`, IPA written, so swiftc and the link accept the flags against the real SDK. Device rows remain open.
