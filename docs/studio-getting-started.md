# Getting started with XCross Studio (Windows and Linux)

XCross Studio is the desktop app plus the `xcross` CLI from this repository. You build, sign, install and debug a
Flutter iOS app on an iPhone from a Windows or Linux PC. It is not affiliated with Apple. You provide your own Apple
ID and your own `Xcode.xip`; nothing from Apple is shipped or downloaded for you.

## 1. Install

| Host | Package | Notes |
|---|---|---|
| Windows 10/11 | `xcross-studio-windows-x64-setup.exe` (per user, no admin) or the portable `.zip` | needs **Apple Mobile Device Service**: install Apple's "Apple Devices" app (Microsoft Store) or iTunes |
| Ubuntu / Debian | `xcross-studio_<version>_amd64.deb` (pulls in `usbmuxd`) | start with `xcross-studio`; the CLI is at `/opt/xcross-studio/xcross/bin/xcross` |
| Other Linux | `xcross-studio-x86_64.AppImage` or the `.tar.gz` | install `usbmuxd` from your distro |

Packages come from the *Studio GUI* CI workflow artifacts, or build them yourself: `cd apps/studio && dart run
tool/package.dart`. Every package bundles `xcross` next to the app, and the app uses it automatically.

## 2. One-time setup

Follow the README's [Requirements](../README.md#requirements) and [Installation](../README.md#installation):
Flutter, a Swift toolchain, LLVM, Python with `pymobiledevice3`, then `xcross setup` and
`xcross sdk install <Xcode.xip>`. Then, in the app:

1. **Setup** → tick *I understand* → **Run doctor**. Every line should be ✔ (device service, SDK, toolchain,
   pymobiledevice3).
2. **Setup** → **Apple sign-in**: your Apple ID and password, or an App Store Connect API key. When Apple asks for
   the two-factor code, type it in the box under the output. A free Apple ID works for development installs. Push
   notifications need a paid team.

## 3. Daily use

| Goal | Page | What happens |
|---|---|---|
| Open a project | **Project** → *Project folder* | bundle id, version, entitlements, icon and launch screen are summarised |
| Plugins that only ship a podspec | **Project** → *Check plugins* → *Draft override* | writes `xcross_overrides/<plugin>/<version>/Package.swift` for you to review |
| Build an IPA | **Project** → *Build* (release, `.ipa`) | `build/xcross-ios/<name>.ipa`; *Install …* jumps to the Device page |
| Run on the iPhone | **Device** → pick the phone → *Build & run* | signed with your Apple ID, installed over USB, opened (iOS 15/16: open it from its icon, or set your own developer disk image folder) |
| Install any IPA | **Device** → *Sign & install* | re-signed with your account; your file is never modified |
| See the app's log | **Device logs** → app → preset *Flutter* / *Push* / *Crash* → *Start* | live table; filters, pause, save |
| Did push survive signing? | **Device logs** → *App info* | ✔/✖ `aps-environment`, associated domains, all entitlements |
| Why does push not arrive? | **Device logs** → preset *Push* → open the app → send a test push | checklist: entitlement → permission → token → delivered |
| Crashes | **Device logs** → *Crashes* → *List* → save | the report plus its exception summary |
| Everything that ran | **Console** | each command, its full output, copy |

The same features are available on the command line: `xcross devices`, `xcross flutter build --release --ipa`,
`xcross flutter run --release`, `xcross install <ipa>`, `xcross logs --app <id> --preset push`,
`xcross app info <id>`, `xcross crashes list`, `xcross plugin list`, `xcross inspect <ipa>`.

## 4. Known limits

- iOS 15/16: debug builds (hot reload) need a debugger and are refused before building. Use profile or release.
- App icon and launch screen are compiled without Xcode. The splash shows the storyboard's background colour and
  its centred image. iOS caches launch screens, so delete the app and reboot the phone to see a change.
- Most Flutter apps use the executable name `Runner`, so `--app` log filtering can't tell two running Flutter apps
  apart.
- When something fails, the error has a stable code (`[device.*]`, `[build.*]`, `[install.*]`) and a hint. For bug
  reports attach `xcross inspect <ipa> --json --normalize`.
