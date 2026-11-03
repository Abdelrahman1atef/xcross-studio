# Research: 016 Firebase, push and Maps

## R1 Why push and Firebase failed on app A
- **Decision:** sign under the real App ID by default and infer `aps-environment`.
- **Rationale:** the built app's profile had no `aps-environment` (no entitlements file) and the App ID was
  `XCR-<identity>.<id>`; APNs tokens and Firebase Installations/FCM are bound to the real bundle ID, and the
  Firebase iOS API key is restricted to it. The user confirmed (2026-11-03) that the real ID must be used.
- **Alternatives:** keep prefixed and tell the user to switch by hand (the desktop app never showed the question, so
  users could not); register a second Firebase app for the prefixed ID (pushes the problem onto every project).

## R2 How the generic runner can call Google Maps without its headers
- **Decision:** `NSClassFromString(@"GMSServices")` and `objc_msgSend` with the `provideAPIKey:` selector, key
  baked into the generated `Runner.m`.
- **Rationale:** `_OBJC_CLASS_$_GMSServices` is exported from the plugins dylib (seen in app A's build), so the class
  resolves at run time; no import path or link flag is needed, and apps without GoogleMaps skip the call.
- **Alternatives:** always use the project runner (fails whenever an AppDelegate import cannot be resolved);
  write the key into Info.plist and read it at run time (the SDK still needs the call).

## R3 What "custom code" in AppDelegate means for `XCROSS_RUNNER=auto`
- **Decision:** compare the AppDelegate source, with comments and whitespace removed, against the statements of
  Flutter's Swift and Objective-C templates (old and UIScene). Anything left over is custom code. Other source
  files in the target (besides `main`, an empty `SceneDelegate` and `GeneratedPluginRegistrant`) also count.
- **Rationale:** robust to formatting; template apps keep the fast generic runner.

## R4 Which module paths SwiftPM gives a Swift target that imports a C-family target
- **Decision:** `-Xcc -fmodule-map-file=<products>/<Target>.build/module.modulemap` for every generated module map,
  plus `-Xcc -I` of the folder its umbrella header or umbrella directory lives in.
- **Rationale:** SwiftPM's `debug.yaml` for app B passes exactly those module maps (all under `*.build/`); the
  maps use absolute umbrella paths. xcframework headers and frameworks come from `SwiftPmSharedSearchPaths` (the
  kept outside edit).

## R5 Capability errors
- **Decision:** verify by listing capabilities after enabling; report refusals as a coded warning, never stop the
  build except on 401.
- **Rationale:** App Store Connect answers 409 both for "already on" and for conflicts; the Apple ID backend answers
  403/404 when the session cannot change capabilities. Only the list after the call tells the truth.

## R6 Why push was never granted with an Apple ID sign-in (found on the device, 2026-11-03)
- **Finding:** with the 409 no longer swallowed, developerservices2 answered `POST /v1/bundleIdCapabilities` from an
  Apple ID session with "409: The relationship 'capabilities' is required but was not provided with this
  request". The old code returned on 409 and printed "Enabled the PUSH_NOTIFICATIONS capability", so every Apple ID
  build lacked push without saying so.
- **Decision:** switch push (`push`), associated domains (`SKC3T5S89Y`), Game Center, Siri and App Groups on
  through Xcode's plist protocol `QH65B2/ios/updateAppId.action` (already used for App Groups; keys as in AltSign);
  other capabilities get the JSON call with the `capability` relationship the developer portal sends. Verify against
  the issued profile, because that backend's JSON list does not show features switched on the plist way.
- **Evidence:** app A reinstalled → `xcross app info` shows `push: development` (before: `null`).
