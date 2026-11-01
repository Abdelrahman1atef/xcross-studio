# Handoff — start here (for the next Claude Code session)

This repo is the local start of **XCross Studio**: an open-source fork of xcross plus a desktop GUI for Windows and
Linux that builds, signs, installs and debugs complete Flutter iOS apps without a Mac.

- Full plan (milestones, GUI, legal, verification): [PLAN.md](PLAN.md)
- Feature list and order: [ROADMAP.md](ROADMAP.md)
- Rules every spec must follow: [../.specify/memory/constitution.md](../.specify/memory/constitution.md) (v1.0.0)

## State right now (2026-11-01)

| Item | State |
|---|---|
| Upstream clone | `arxdeus/xcross` at v2.0.9 + 2 commits (`ebf0f05`), submodules `examples`, `third_party/OpenAppleMacros` |
| Remotes | `upstream` fetch only (push URL set to `DISABLED-do-not-push-upstream`); `origin` = https://github.com/Abdelrahman1atef/xcross-studio.git |
| GitHub fork | **created by the user**: https://github.com/Abdelrahman1atef/xcross-studio |
| Push-notification test (client app) | **deferred by the user**: do it only after the first XCross Studio build of the client project, using our own tool (`xcross app info` + `xcross logs --preset push`), not the old Sideloadly/rcodesign path |
| Spec Kit | initialised (`specify init --here --integration claude --script py`); skills in `.claude/skills/speckit-*` |
| Specs / features | 001 inspect, 002 quick-wins, 010 device logs, 005 iOS 15/16 + `xcross install`, 003 entitlements, 004 icon + launch screen (Dart port of AssetKit), 008 desktop GUI MVP, 006 plugin overrides (MVP: `xcross_overrides/<plugin>/[<version>/]Package.swift`): **implemented**. 007, 009: not started (009 has a first piece: portable package + Inno Setup installer + GUI CI) |
| Git | stacked branches, all pushed to `origin`: `001-inspect` → `002-quick-wins` → `010-device-logs` → `005-ios16-install-launch` → `003-entitlements-signed-ipa` → `004-icon-launch-screen` → merged into `008-json-events-gui`, which also has `006-plugin-overrides` merged (**the branch with everything**). `main` untouched (= upstream) |
| CI | Unit Tests were red on Linux/macOS from 002 to 004 because of a wrong count in `version_order_test` AC-002-5 (fixed on 008). Architecture was red on 008 until `apps/**` was excluded from the root analysis. New **Studio GUI** workflow: GUI tests on Windows + Linux, package, installer |
| Tomorrow | iPhone X test pass: [DEVICE-TEST-RUNBOOK.md](DEVICE-TEST-RUNBOOK.md). Build with `cd apps/studio && dart run tool/package.dart` → `dist/xcross-studio-windows-x64/` (GUI + bundled `xcross/bin/xcross.exe`) |
| Baseline (008 tip) | `dart analyze --fatal-warnings` clean; studio_ext 140 pass / 3 skipped; xcross 1272 pass / 37 skipped / 1 env fail (`windows_swift_response_test`, needs clang); GUI 20 pass |

## Suggested next steps

1. Run the device runbook; record results in each `specs/NNN-*/device-check.md`.
2. 006 follow-ups: `xcross plugin shim` (draft `Package.swift` from a podspec), remote binary targets and resource
   bundles, Google Maps / Pusher overrides.
3. Open PRs in stack order (001 … 008) against `main` of the fork, or squash into one release branch.
4. Linux verification (deferred by the user): the Studio GUI workflow now builds and tests the GUI on Ubuntu; a real
   Ubuntu host with the iPhone is still needed for the device rows.
5. Remaining roadmap: 007 native runner code, 009 hardening (signing the installer, AppImage/.deb, upstream issue
   sub-specs), NDJSON build events for the GUI.

## Decisions already made by the user

Open source for everyone (stays AGPL-3.0) · desktop GUI first (Flutter desktop) · Windows **and** Linux · full fork ·
spec-driven (Spec Kit) · must-haves: push + deep links, icon + splash, Google Maps / Pusher, iOS 16 install, every
reported-but-unfixed issue · built-in Sideloadly replacement (`xcross sign` / `xcross install` for any IPA) · iPhone
log viewer.

## Key facts from research (verified)

**xcross internals** (X = `packages/xcross/lib/src/`):
- Pipeline: `composition/cli/flutter_build_command.dart` → `FlutterPackOperation.pack` → `FlutterPacker.pack`
  (`shared/flutter/build/flutter_packer.dart`, step injection) → compile (`shared/flutter/flutter_artifact_compiler.dart`,
  plugins via `_buildPlugins` → `GeneratedPluginsPackage.build` in `shared/flutter/build/ios_plugin_package.dart`) →
  link (`RunnerShim`, `AppExtensionBuilder`) → assemble (`shared/flutter/flutter_bundle_assembler.dart`) →
  `IpaPackager` (`shared/cli/shared/ipa_packager.dart`, zip only).
- Plugins: SPM is decided only by `<pkg>/{ios|darwin}/<name>/Package.swift` existing (`ios_plugins.dart`,
  `swiftPackageDir`); podspec-only plugins are skipped with a warning in `_buildPlugins`. No override mechanism.
- Runner: `RunnerShim.runnerObjcSource` (`shared/flutter/build/runner_shim.dart`) generates `Runner.m`; the project's
  `AppDelegate.swift` is never compiled. `AppExtensionBuilder._compile` already compiles Swift (reuse for M6).
- Versions: from `ios/Flutter/Debug.xcconfig`/`Generated.xcconfig` or pbxproj, not pubspec
  (`ios_bundle_versions_resolver.dart`, `_writeInfoPlist`).
- Signing: `AscProvisioning.provisionDevelopmentIdentity` (`packages/apple_developer_kit/lib/shared/appstoreconnect/appstoreconnect.dart`),
  `BundleSigner.signApp` + own `MachOSigner`. Entitlements come from private Info.plist keys `XCrossEntitlements` /
  `XCrossCapabilities` (`shared/artifact/app_entitlements.dart`), written only by the Compose assembler. Signing only
  happens in `NativeBackend.install` → `_signAndInstall` (`target/iphone/device/device_backend.dart`); build is unsigned
  by design.
- Assets: `IosBundleResources.stage` silently skips `.xcassets`; `PlistStoryboardPolicy` swaps the launch storyboard for
  an empty `UILaunchScreen`. No `CFBundleIcons` handling.
- Devices: iOS 17 check in `DeviceRunOperation.run` runs **after** the build; install via `PymdDevices.install`
  (`packages/dart_mobile_device/lib/target/iphone/device/pymd/pymd_devices.dart`); launch only via iOS 17 RSD tunnel.
- Logs: `DeviceLog` (`target/iphone/device/device_log.dart`) streams `pymobiledevice3 syslog live --pid N --format json`
  over usbmux (no tunnel, no DDI) during `run` only — basis for feature 010.

**External**:
- Google Maps: use `google_maps_flutter_ios_sdk10` (ships `Package.swift`, depends on `googlemaps/ios-maps-sdk`
  binary xcframework + resources). Tool must support remote `binaryTarget` and resource bundles.
- Pusher: `pusher-websocket-swift` has SPM; the Flutter plugin does not → shim `Package.swift` in `overrides/`.
- Asset catalogs: `xtool-org/AssetKit` compiles `.xcassets` → `Assets.car` (devices OK; App Store processing may stall).
  **GitHub reports its licence as NOASSERTION — confirm the licence before use.** No open-source storyboard compiler.
- iOS 16: pymobiledevice3 `apps install` (installation_proxy), `mounter auto-mount` with the DDI from the user's Xcode
  `DeviceSupport/16.x` (do **not** use the third-party auto-download), `developer dvt launch`; Developer Mode required.
- Sideloadly is closed source; open alternatives: Sideloader (Dadoum, GPL-3.0), AltStore / SideStore (AGPL-3.0);
  xcross itself already does Apple ID login + certificate/profile creation + install.
- Signing tools: zsign (MIT), rcodesign 0.29.0 (apple-platform-rs; licence not detected by GitHub — check), ldid.
- Legal: the Xcode/SDK agreement (§2.5, §2.7) restricts the SDK to Apple hardware — unavoidable risk; never
  redistribute SDK/DDI/Xcode; disclaimers; lawyer review before 1.0.

## Proven in a real project (client Flutter app, iPhone X, iOS 16.7.16)

- xcross runs natively on Windows; **WSL + usbipd is unreliable** for device transfers (`AFC Write error: 30`).
- `environment.PATH` pointing at the Swift toolchain in `XCROSS_CONFIG` breaks native-asset linking (bundled LLD can't
  link iOS); remove it and xcross uses system clang/lld.
- Upgrading `flutter_secure_storage` to 10.3.4 (darwin package has `Package.swift`) and `fluttertoast` to 10.0.2 made
  those plugins build; version 11 of secure storage conflicts with `share_plus` 10 (`win32`).
- Loose icon PNGs (`AppIcon60x60@2x.png` …) + `CFBundleIcons` in Info.plist **show the icon** on device.
- `UILaunchScreen` with a loose PNG as `UIImageName` does **not** show a splash (needs an asset catalog).
- Installed app had **no `aps-environment`** → no push. Ad-hoc signing with rcodesign embeds the entitlement into the
  binary; whether Sideloadly keeps it after re-signing was **not yet confirmed** (push still failed; no logs).
- Firebase release builds print nothing from Dart; device syslog shows only system lines → logs feature must say so.
- `pymobiledevice3 apps list` returns each installed app's entitlements (read-only check used above).

## Upstream issues we filed (arxdeus/xcross)

#145 CocoaPods-only plugins skipped · #146 unsigned IPA / no sign-install command · #147 iOS 16 support + fail fast ·
#148 native-assets failure (later corrected: caused by our PATH config) · #149 icon, launch screen and entitlements
missing. No maintainer replies yet.

## Before anything goes public

Scrub client/company names and bundle IDs from any committed file; keep credentials out of the repo; add NOTICE and the
"not affiliated with Apple" disclaimer.
