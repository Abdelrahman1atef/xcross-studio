# XCross Studio — Feature Roadmap

Each row becomes a Spec Kit feature folder `specs/NNN-slug/` created with `/speckit-specify` when work starts.
Order follows value/effort. **MVP = 001–004 + 010 (device logs) + 008 (basic GUI) on Windows and Linux.**
Suggested build order: 001 → 002 → 010 → 003 → 004 → 005 → 006 → 007, with 008 in parallel from 003, then 009.
Governing rules: [.specify/memory/constitution.md](../.specify/memory/constitution.md).

| # | Feature (slug) | Milestone | Goal (one line) | Upstream issues | Upstreamable | Status |
|---|---|---|---|---|---|---|
| 001 | `inspect` | M0 | `xcross inspect <ipa\|app> --json`: plist, entitlements per Mach-O, profile type, icons, Assets.car, frameworks — the base for golden tests and device evidence | — | yes | Implemented |
| 002 | `quick-wins` | M1 | iOS version check before build; version order `--build-name` > pubspec > xcconfig > pbxproj; PATH guard; loud warnings for skipped podspec/xcassets/storyboard | #145 (warning part), #147 (fail-fast), #148 | yes | Implemented (Windows device-checked; Linux deferred) |
| 003 | `entitlements-signed-ipa` | M2 | Apply `Runner.entitlements` (push, associated domains); `build --ipa --sign development\|ad-hoc` via reusable signing; **`xcross sign <any.ipa>`** re-signs any IPA with Apple ID or App Store Connect key (Sideloadly replacement, part 1) | #146, #149 (entitlements) | yes | Entitlements implemented (device row tomorrow); `xcross sign` export deferred (`xcross install` signs + installs) |
| 004 | `icon-launch-screen` | M3 | `Assets.xcassets` → `Assets.car` (AssetKit), `CFBundleIcons`, `UILaunchScreen` from `LaunchScreen.storyboard` | #149 (assets) | warnings only | Implemented (Dart port of AssetKit; device rows tomorrow) |
| 005 | `ios16-install-launch` | M4 | Install/launch/run on iOS < 17 via installation_proxy + user's DDI + dvt launch; **`xcross install <any.ipa>`** for any device (Sideloadly replacement, part 2); host device-service doctor checks (Windows + Linux) | #147 | yes | Implemented (device rows tomorrow) |
| 006 | `plugin-overrides` | M5 | Override `Package.swift` lookup, remote binary targets + resource bundles, Google Maps (`google_maps_flutter_ios_sdk10`), Pusher shim, `xcross plugin shim` | #145 | binary targets: yes | Not started |
| 007 | `native-runner-code` | M6 | Compile project `ios/Runner/*.swift\|*.m` (AppDelegate) with `--runner=shim` fallback | #149 (AppDelegate note) | maybe | Not started |
| 008 | `json-events-gui` | M7 | `--json` NDJSON event stream + Flutter desktop GUI (Windows + Linux): Setup, Project (create/open), Build, Device & Install, Logs | — | `--json`: yes | GUI MVP implemented (Windows build OK; device click-through tomorrow; Linux deferred); NDJSON build events deferred |
| 010 | `device-logs` | M1b | iPhone log viewer: `xcross logs` (live syslog, filters, presets push/crash/flutter, `--json`), `xcross crashes list\|pull`, `xcross app info <bundle-id>` (installed entitlements) — over plain usbmux, works on iOS 16 and 17+ | — (new) | yes | Implemented (Windows device-checked in part; Linux deferred) |
| 009 | `hardening-1.0` | M8 | One sub-spec per unfixed issue: #90, #75, #55, #21 (documented out of scope); close #145–#149; installers (Inno Setup, AppImage, .deb) | #90 #75 #55 #21 | yes | Started: portable package (`apps/studio/tool/package.dart`), Inno Setup per-user installer, GUI CI on Windows + Linux; AppImage/.deb, installer signing, issue sub-specs open |

Device test matrix for every device-affecting feature: {Windows 11, Ubuntu 24.04} × {iPhone X iOS 16.7, one iOS 17+ device}.
