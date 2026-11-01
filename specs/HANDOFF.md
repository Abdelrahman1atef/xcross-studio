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
| Specs / features | **implemented**: 001 inspect · 002 quick-wins · 010 device logs · 005 iOS 15/16 + `xcross install` · 003 entitlements · 004 icon + launch screen (Dart AssetKit port) · 006 plugin overrides + `xcross plugin list/shim` · 007 project runner (opt-in `XCROSS_RUNNER=project`) · 008 desktop GUI · 009 packaging (zip, Inno Setup, .deb, AppImage) + issue triage · 011 `xcross sign` + `install --no-resign` · 012 NDJSON build events (`XCROSS_EVENTS=ndjson`) used by the GUI |
| Git | `008-json-events-gui` is **the branch with everything** (feature branches 001…012 are also pushed; 004/006/007/011/012 were merged into it, 009 and the plugin shim fast-forwarded). `main` untouched (= upstream) |
| CI | **all green on `955078a`** (every feature merged): Unit Tests on linux-x64/arm64, macos-arm64, windows-x64/arm64; Architecture; Studio GUI on Windows + Linux (tests, packages, installer, .deb, AppImage) |
| **This PC** | 2026-11-01: `xcross setup` installed Swift 6.4.2 (+ Python 3.10 as its dependency), stock LLVM 23.1.4 installed, Darwin SDK built from `Xcode_27.1.xip` → iOS toolchain ✓. Open: `xcross auth` (needs the user's Apple ID + 2FA) and **Flutter 3.47.6** for release/profile builds (no Windows `gen_snapshot` for 3.47.8; runbook step 0.4). A debug build of the Flutter template succeeded and verified 003/004/007 at build level |
| Tomorrow | iPhone X test pass: [DEVICE-TEST-RUNBOOK.md](DEVICE-TEST-RUNBOOK.md). Package: `cd apps/studio && dart run tool/package.dart` → `dist/xcross-studio-windows-x64/` (GUI + bundled `xcross/bin/xcross.exe`) |
| Baseline (tip) | `dart analyze --fatal-warnings` clean; xcross 1300 pass / 37 skipped / 1 env fail (`windows_swift_response_test`, needs clang); studio_ext 157; cli_kit 232; dart_mobile_device 135; GUI 30 |

## Suggested next steps

1. One-time toolchain setup on this PC, then the device runbook; record results in each `specs/NNN-*/device-check.md`.
2. Fix whatever the device pass finds (004 catalog on iOS 16, 007 swiftc/ld flags against the real SDK, 011 real
   signing, 012 events during a real build are the least verified).
3. Open PRs in stack order against `main` of the fork, or squash into one release branch; then upstream PRs for the
   generally useful fixes (#146, #147, #149).
4. Linux device verification on Ubuntu 24.04 (deferred by the user; CI already builds and tests the GUI on Linux).
5. Later: `--runner` / `--json` flags (need build_cli regeneration), ad-hoc/App Store profiles for `xcross sign`,
   installer code signing, plugin remote binary targets.

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
