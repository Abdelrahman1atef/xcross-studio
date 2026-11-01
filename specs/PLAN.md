# Plan: "XCross Studio" — open-source fork of xcross + desktop GUI for Windows and Linux

## Context

Shipping a real client Flutter app from Windows proved xcross (github.com/arxdeus/xcross, Dart, AGPL-3.0, v2.0.9) can
build iOS apps without a Mac, but only through a long manual chain (WSL + usbipd, hand-written config, Sideloadly,
post-build IPA patching) and with missing features. Gaps proven on a real iPhone X (iOS 16.7) and filed as #145–#149:

- CocoaPods-only plugins skipped silently (Google Maps, Pusher) → runtime failures.
- `build --ipa` is unsigned; signing only happens inside `run`.
- `Runner.entitlements` + project `AppDelegate.swift` ignored → no push, no deep links, no Maps API key.
- No asset catalogs/storyboards → no icon, no launch screen.
- Deploy needs iOS 17+ and checks only after a full build; WSL USB/IP transfers fail.
- Info.plist version from stale `Generated.xcconfig`; `environment.PATH` override breaks iOS linking.

**Goal:** one free, open-source desktop app for **Windows and Linux** where a Flutter developer clicks
*Create/Open project → Build → Install* and gets a **complete** iOS app on a real iPhone (push, deep links, icon,
splash, Maps/Pusher, iOS 16+), no Mac.

**User decisions:** open-source for everyone · desktop GUI first · **Windows + Linux** · full fork · must-haves: push + deep links,
icons + splash, Google Maps/Pusher, iOS 16 install, plus every reported-but-unfixed issue · **spec-driven** method ·
**built-in Sideloadly replacement** (`xcross sign` / `xcross install` for any IPA) · **iPhone log viewer** in the tool.

**Latest trigger (logs):** the push-entitlement test IPA was installed but no notification arrived, and there was no
way to see why — no device logs in the workflow. Debugging push, crashes, black screens and Firebase setup all need
the iPhone's own logs, so a device log viewer becomes an MVP feature (010 below), not an afterthought.

**Hard constraints**
- AGPL-3.0: fork + GUI stay AGPL, full source public, modifications marked.
- Apple Xcode/SDK agreement (§2.5, §2.7) restricts the SDK to Apple hardware → legal risk cannot be removed, only
  reduced: never ship SDK/DDI/Xcode, user brings own `Xcode.xip`, disclaimers, "not affiliated with Apple".
- Native hosts, not WSL/Docker: xcross already runs natively on **Windows and Linux** (both shipped upstream).
  WSL USB/IP breaks device transfers and Docker can't reliably reach the iPhone over USB. Docker-like *simplicity*
  comes from the GUI + one-click setup on each OS. Host differences the plan must cover:

  | | Windows | Linux |
  |---|---|---|
  | Device service | Apple Mobile Device Service (Apple Devices / iTunes driver) | `usbmuxd` system service + udev rules |
  | iOS 17+ tunnel | elevated shell (`Start-Process -Verb RunAs`) | `sudo`/`pkexec` |
  | Cancel long jobs | `taskkill /PID n /T /F` | kill the process group (`setsid` + `kill -TERM -pgid`) |
  | Credentials | Windows Credential Manager | Secret Service (libsecret) |
  | Installer | Inno Setup `.exe` (signed via SignPath) | AppImage + `.deb` (no Flatpak: its sandbox blocks USB/subprocess tools) |

## Approach (simplest path)

The CLI fork does all the work; the GUI is a thin shell. Fork logic lives in **new files** (package
`packages/studio_ext`) and touches upstream files only at small seams, so upstream releases merge easily.
Fixes that are generally useful go upstream as PRs first and are cherry-picked into the fork.

### Repo layout
```
xcross-studio/
  packages/            upstream packages (edited only at seams, marked `// studio:`)
  packages/studio_ext/ all fork features
  apps/studio/         Flutter Windows GUI
  overrides/<plugin>/<semver>/   replacement Package.swift shims (+ override.yaml)
  fixtures/            sample apps: minimal, push_links, branding, maps_pusher
  specs/NNN-slug/      spec.md · plan.md · tasks.md · research.md · device-check.md
  .specify/memory/constitution.md   docs/  legal/  installer/ (Inno Setup)
```
Remotes: `origin` = fork, `upstream` = arxdeus/xcross; merge each upstream release tag (no rebasing public `main`);
weekly CI job opens an upstream-sync PR. Ask the maintainer about naming and co-maintenance before launch.

### Spec-driven workflow (GitHub Spec Kit)
`specify init --ai claude`, then per feature: `/speckit.specify → /speckit.clarify → /speckit.plan → /speckit.tasks →
/speckit.implement`. ACs are numbered (`AC-004-1`); every AC maps to a test name or a row in `device-check.md`.

Constitution: minimal diff from upstream · never redistribute Apple material · fail fast, never skip silently
(every unsupported input → warning + fix hint) · CLI is the product, GUI holds no build logic (`--json`) · Windows
and Linux are equal first-class hosts (every feature works and is tested on both; OS-specific code only behind the
existing `host/windows` / `host/linux` split) · test-first · smallest change that meets the ACs · AGPL/licence
hygiene (headers, notices, DCO).

Definition of done: all ACs checked · unit + golden-IPA tests green on **Windows and Linux** · device evidence from
both hosts on iPhone X (iOS 16) and one iOS 17+ device for device-affecting features · docs/CHANGELOG · upstream PR
linked when upstreamable.

### Milestones (1–3 devs, ~5 months incl. Linux; **MVP = M0–M3 + M1b device logs + basic GUI on both OSes**)

| M | Feature | Where (upstream seams) | Acceptance |
|---|---|---|---|
| M0 · 1 wk | Fork, Spec Kit, constitution, CI matrix `ubuntu-latest` + `windows-latest`, new `xcross inspect <ipa> --json` (plist, entitlements per Mach-O, profile, icons, frameworks) | new command in `studio_ext`; CI `unit-tests.yml` matrix | CI green on both OSes; inspect works on a v2.0.9 IPA on both |
| M1 · 1 wk | Quick wins: iOS check **before** build; version order `--build-name` > pubspec > xcconfig > pbxproj; PATH guard; loud warnings for podspec/xcassets/storyboard skips | `target/iphone/device/device_run_operation.dart`, `shared/cli/basic/doctor_environment_checks.dart`, `FlutterBundleAssembler._writeInfoPlist`, `darwin_sdk_kit/.../darwin_toolchain_resolver.dart`, `IosNativeAssetsBuilder` | unsupported device fails < 5 s; IPA version = pubspec; polluted PATH still links |
| M1b · 1.5 wk | **Device logs (feature 010)** — new commands, all over plain usbmux/lockdown (no tunnel, no DDI → works on iOS 16 and 17+, Windows and Linux): `xcross logs` = live syslog with filters `--app <bundle-id>` (resolves to running pid via process list), `--process`, `--grep`, `--level`, `--since-launch`, `--save <file>`, `--json` (NDJSON for the GUI); presets `--preset push` (`apsd`, `usernotificationsd`, `SpringBoard` + the app; highlights APNs token/registration/delivery lines and `aps-environment`/entitlement errors), `--preset crash`, `--preset flutter` (only `flutter: ` Dart output); `xcross crashes list\|pull [--app]` (crash-report service); `xcross app info <bundle-id>` = installed app's version, signer type and **entitlements as installed** (installation_proxy) — answers "did the signer keep `aps-environment`?" in one step | generalise `DeviceLog` (`target/iphone/device/device_log.dart`: today pid-only, crash buffer, used by `core_device_launcher.dart`) into a reusable `DeviceLogStream` in `studio_ext`, keep `DeviceLog` as a thin user of it; new `Pymd` wrappers for `syslog live`, `crash ls/pull`, `apps list` next to `PymdDevices` (`dart_mobile_device/.../pymd/`) | live log of a chosen app on iPhone X from Windows **and** Linux; push preset shows the APNs registration lines (or the missing-entitlement error) for a Firebase app; crash pulled and shown; `app info` lists installed entitlements; no UDIDs or tokens printed unless `--show-sensitive` |
| M2 · 2 wk | Entitlements + signed IPA: read `Runner.entitlements` → write `XCrossEntitlements/XCrossCapabilities`; capability mapping (push, associated domains) + ad-hoc profile type; extract signing into reusable `SignOperation`; `build --ipa --sign development\|ad-hoc` | `shared/flutter/flutter_bundle_assembler.dart`, `shared/artifact/app_entitlements.dart`, `apple_developer_kit/.../appstoreconnect.dart` (`AscProvisioning`), `BundleSigner`, `target/iphone/device/device_backend.dart` (`_signAndInstall`) | inspect shows `aps-environment` + associated-domains; FCM message arrives; universal link opens app |
| M3 · 2 wk | Icon + launch screen: compile `Assets.xcassets` → `Assets.car` with **AssetKit** (xtool-org, MIT; spike day 1: build `assetkit.exe`, fallback = port to Dart); write `CFBundleIcons` (+ loose PNGs, proven on device); parse `LaunchScreen.storyboard` (image, colour) → colorset + `UILaunchScreen {UIImageName, UIColorName}` | `shared/flutter/build/ios_bundle_resources.dart`, `shared/artifact/plist_storyboard_policy.dart` | icon shows; splash shows after delete + reboot on iOS 16 and 17 |
| M4 · 2 wk | iOS 16 install/launch: `installation_proxy` install → mount DDI from **user's Xcode** `DeviceSupport/16.x` (never auto-download) → `developer dvt launch`; for `run`: syslog → VM service URL → usbmux forward → attach. Doctor checks Developer Mode + DDI, and the host device service (Windows: Apple Mobile Device Service running; Linux: `usbmuxd` active, socket `/var/run/usbmuxd` reachable, udev rule present) | new `LegacyDeviceLauncher` in `dart_mobile_device`; `PymdDevices`; `device_backend.dart`; doctor host checks under `host/windows` / `host/linux` | install + launch + hot reload on iPhone X from the GUI on Windows **and** Linux |
| M5 · 3 wk | Plugin overrides: lookup `ios/xcross_overrides/` → `overrides/` → plugin's own; remote `binaryTarget` download/cache + resource bundles; doctor suggests `google_maps_flutter_ios_sdk10` (ships Package.swift); hand-written Pusher shim (PusherSwift has SPM); `xcross plugin shim <name>` scaffolds from podspec JSON | `shared/flutter/build/ios_plugins.dart` (`swiftPackageDir`), `swiftpm/plugin_overlay.dart`, `ios_plugin_package.dart` | Maps app links + launches; Pusher receives an event |
| M6 · 3 wk | Compile project native code: `RunnerShim` keeps `main` + registrant; compile `ios/Runner/*.swift\|*.m` via swiftc reusing `AppExtensionBuilder._compile`; `--runner=shim` fallback | `shared/flutter/build/runner_shim.dart`, `app_extension_builder.dart` | Maps tiles render (API key from AppDelegate) |
| M7 · 5 wk (parallel from M2) | `--json` NDJSON events + GUI v1 for Windows and Linux (below) | composition root + `studio_ext`; `apps/studio` | full click-through on a clean Windows 11 VM and a clean Ubuntu 24.04 VM |
| M8 · 2 wk | 1.0 hardening: one spec per open issue — #145–#149 (close on DoD), #90 native-assets hang (timeouts + diagnostics), #75 Xcode 27 TAPI (doctor pins Xcode 26, clear message), #55 Nix (merge PR #56), #21 React Native (out of scope, documented) | various | all specs meet DoD; installer released |

### GUI v1 (`apps/studio`, Flutter desktop: Windows + Linux from one codebase)
- Runs the `xcross` binary as a subprocess with `--json` (event types: step, progress, log, warning{code,hint},
  error{code,hint}, artifact, device, done); schema in `specs/0xx-json-events/contracts/events.schema.json`.
  Never imports `@internal` xcross code. State with `ChangeNotifier`.
- One small `HostPlatform` interface in the GUI (`windows_host.dart`, `linux_host.dart`) hides the OS differences from
  the table above: binary path, cancel/kill tree, elevation for the tunnel, credential store, opening folders,
  device-service checks. Everything else is shared.
- Screens:
  1. **Setup wizard / doctor** — Xcode.xip import, Swift, device service (Windows: Apple Mobile Device Service; Linux: install/enable `usbmuxd` with the right `apt`/`dnf`/`pacman` hint + udev rule), pymobiledevice3 (one-click via `uv`), Apple ID or App Store Connect key, legal acknowledgement.
  2. **Project** — *Create new* (`flutter create` + iOS-ready defaults) or *Open*; shows bundle ID, version, entitlements, icon/splash, plugin table (SPM / override / unsupported).
  3. **Build** — mode, signing (none/development/ad-hoc), output IPA, progress, open folder.
  4. **Device & Install** — devices with iOS version, trust, Developer Mode; Install / Launch / Run; elevated "Start tunnel" for iOS 17+.
  5. **Device Logs** (iPhone) — live table (time, process, level, message) from `xcross logs --json`; app picker
     (installed apps), filters (process, text, level), preset buttons **Push / Crash / Flutter**, pause/resume,
     colour by level, save to file; **Crashes** tab (list, open, save); **App info** panel showing installed
     entitlements with a red badge when `aps-environment` / associated-domains are missing; a **Push diagnostics**
     checklist (entitlement present → notification permission granted → APNs token registered → message received)
     filled from `app info` + the push preset.
  6. **Tool Logs** — the xcross build/install output; filter, copy, bug-report zip (doctor + logs, credentials stripped).
- Packaging: Windows = Inno Setup installer (GUI + `xcross.exe` + `assetkit.exe`) signed via SignPath Foundation
  (free for OSS); Linux = AppImage + `.deb` (GUI + `xcross` + `assetkit`; `.deb` declares `usbmuxd` as a dependency
  and ships the udev rule). Update check against GitHub Releases. Credentials in the OS store (Credential Manager /
  libsecret); no telemetry.

### Open-source project & sustainability
- **Audience:** Flutter devs on Windows and Linux, students, small agencies, regions where Macs are expensive.
- **Funding:** GitHub Sponsors + Open Collective; optional paid onboarding/priority support (no dual licensing: we don't own upstream copyright).
- **Governance:** CODEOWNERS, spec PR required for features, CONTRIBUTING, Code of Conduct, DCO, issue templates asking for `doctor --json`.
- **Legal checklist:** "not affiliated with Apple" (README + GUI) · first-run Xcode SLA acknowledgement · never ship SDK/DDI/Xcode · no Apple logos · AGPL LICENSE/NOTICE + source offer · third-party notices (AssetKit MIT, pymobiledevice3 GPL via subprocess, rcodesign MPL if used) · ask upstream for a generated-output exception, because RunnerShim code ends up inside user apps; until then document the risk · get a lawyer review before 1.0.
- **KPIs:** time to first installed app < 60 min · plugin compatibility matrix (top 50 iOS plugins) · device-check pass rate per release · upstream PRs merged · first issue response < 72 h · downloads/stars.

## Reuse (don't rebuild)
- Signing: `BundleSigner.signApp` + `MachOSigner` (apple_developer_kit), `AscProvisioning`, `SigningAsset` entitlement merge.
- Entitlement plumbing: `XCrossEntitlements` / `XCrossCapabilities` keys already used by the Compose assembler (`shared/compose/build/compose_entitlements.dart`).
- Swift compilation: `AppExtensionBuilder._compile`. Step injection: `FlutterPacker` step parameters.
- Device: `PymdDevices.install`, `DeveloperDiskImage`, `OsVersion.deviceOSMajorVersion`.
- Logs: `DeviceLog` (`packages/xcross/lib/src/target/iphone/device/device_log.dart`) — already runs `pymobiledevice3 syslog live --pid N --format json` over usbmux without tunnel/DDI, parses JSON lines, recognises `flutter: ` Dart output, kills the stream with `runner.killTree`, keeps a crash-reason buffer. Generalise rather than rewrite.
- Session proof: `pymobiledevice3 apps list` returns each installed app's `Entitlements` (used here to prove the missing `aps-environment`); `crash ls` works on iOS 16.
- External: AssetKit (xcassets → Assets.car), `google_maps_flutter_ios_sdk10`, PusherSwift SPM, pymobiledevice3.
- From this session: icon PNG + `CFBundleIcons` patch logic and the entitlement findings (`Downloads\xcross-issue-5-asset-catalogs.md`).

## Verification
- **Unit:** per package (upstream layout) + `studio_ext/test` + `apps/studio/test` (incl. `HostPlatform` fakes), on ubuntu-latest and windows-latest with fake toolchains.
- **Golden IPA:** build `fixtures/*`, `xcross inspect --json`, normalise hashes/timestamps, diff against committed goldens (plist keys, entitlements per Mach-O, profile type, CFBundleIcons, Assets.car renditions, frameworks, valid signature).
- **Golden parity:** the same fixture built on Windows and on Linux must produce identical `inspect --json` output (after normalisation) — catches host-specific drift.
- **Device checklist** (`docs/release-checklist.md`, run from **both** a Windows 11 host and an Ubuntu 24.04 host, on iPhone X iOS 16.7 + one iOS 17+ device): install/launch, icon, splash after delete + reboot, FCM push, universal link, Maps tiles, Pusher event, hot reload, signed IPA reinstall, **live device logs for the app + push preset + crash pull + `app info` entitlements**, GUI flow on clean VMs.
- **Log feature unit tests:** feed recorded `syslog live --format json` fixtures (iOS 16 and 17, with the client-app-style missing-entitlement case) into the filter/preset code; assert sensitive fields (device UDID, APNs token) are masked by default.
- **CI:** upstream workflows + spec-lint (PR names `NNN-*`, all `tasks.md` boxes ticked) + weekly upstream-sync PR + release job building on both OSes: `xcross.exe`/`xcross`, `assetkit.exe`/`assetkit`, GUI, Inno Setup installer, AppImage and `.deb`.

## Progress so far (local, uncommitted, `D:\Programing\xcross-studio`)
- Upstream v2.0.9 cloned with submodules; `upstream` push disabled. GitHub fork not yet created (public-repo creation
  needs the user: `gh repo fork arxdeus/xcross --fork-name xcross-studio --clone=false`).
- Spec Kit initialised (`--integration claude --script py`); constitution v1.0.0 written; `specs/ROADMAP.md` (001–009,
  with `xcross sign`/`xcross install` added); `specs/001-inspect/spec.md` drafted. Baseline `cli_kit` tests: 228 pass on Windows.
- **Remaining work in this session (then stop; the user continues in a new Claude Code session opened at the root of
  `D:\Programing\xcross-studio`, where the `/speckit-*` skills are installed):**
  1. Add row 010 `device-logs` (milestone M1b, MVP) to `specs/ROADMAP.md`.
  2. Draft `specs/010-device-logs/spec.md` (Spec Kit template; ACs as in the M1b row; reuse `DeviceLog`).
  3. Write `specs/HANDOFF.md` for the new session: what exists, decisions (open source, AGPL, Windows + Linux, desktop
     GUI, full fork, spec-driven, Sideloadly replacement, device logs), key research facts (xcross file map, AssetKit,
     `google_maps_flutter_ios_sdk10`, Pusher shim, iOS 16 path, legal limits, WSL/usbipd pitfalls), proven
     workarounds from the client app session, pending items (create GitHub fork, first commit on a branch, client app push
     check), and the suggested next command (`/speckit-plan` for 001-inspect, then 010-device-logs).
  4. Copy this plan into the repo as `specs/PLAN.md` so the new session has the full roadmap.
  No commits and no GitHub actions in this session (user decides in the new session).

## Immediate help for the client app push test (before the feature exists)
When the iPhone is reconnected: run the existing read-only entitlement check (installation_proxy) to see whether
Sideloadly kept `aps-environment`; if it did, capture `pymobiledevice3 syslog live` filtered to `apsd` +
`usernotificationsd` + the app while sending a test message from the Firebase console. These two manual steps are
exactly what `xcross app info` and `xcross logs --preset push` will automate.

## First steps after approval
1. Fork `arxdeus/xcross` → `xcross-studio`; add `upstream` remote; enable Actions with an `ubuntu-latest` + `windows-latest` matrix.
2. `specify init --ai claude`; write the constitution; create `specs/001-inspect` … `specs/008-hardening` stubs from the table.
3. Implement M0 (`xcross inspect`) and M1 quick wins; open the M1 fixes as upstream PRs.
4. Day-1 spike for M3: AssetKit is Swift, so it should build on Linux directly; confirm it also builds as a Windows binary in CI (fallback: port to Dart, which covers both OSes).

## Risks
- Apple licence conflict (§2.5/§2.7) — unavoidable; mitigated, lawyer review before 1.0.
- Newer Xcode may not ship iOS 16 DDIs → user may need an older Xcode.xip for M4.
- AssetKit `.car` is fine on devices but App Store processing may stall → store builds still need actool output (documented limitation).
- Mixed ObjC/Swift plugins (M5) and compiling arbitrary AppDelegate code (M6) are the hardest parts; `--runner=shim` fallback keeps builds working.
- Upstream drift: keep changes at seams, merge every release, push fixes upstream.
- Linux distro fragmentation (usbmuxd versions, udev, GTK/glibc for the GUI): officially support Ubuntu 22.04/24.04 and
  Fedora latest; AppImage for the rest; document others as community-supported.
- Two hosts double the device testing; keep the checklist short and automate everything that doesn't need a phone.

