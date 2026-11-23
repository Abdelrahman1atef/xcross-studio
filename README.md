<div align="center">

# xcross · XCross Studio edition

[![Unit Tests](https://img.shields.io/github/actions/workflow/status/Abdelrahman1atef/xcross-studio/unit-tests.yml?branch=main&style=flat-square&label=tests)](https://github.com/Abdelrahman1atef/xcross-studio/actions/workflows/unit-tests.yml)
[![Latest release](https://img.shields.io/github/v/release/Abdelrahman1atef/xcross-studio?style=flat-square&label=release)](https://github.com/Abdelrahman1atef/xcross-studio/releases)
[![iOS compilers](https://img.shields.io/github/v/release/Abdelrahman1atef/xcross-compilers?style=flat-square&label=newest%20iOS%20compiler)](https://github.com/Abdelrahman1atef/xcross-compilers/releases)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-3C873A?style=flat-square)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg?style=flat-square)](https://www.gnu.org/licenses/agpl-3.0)

**Build, run, hot-reload and ship Flutter iOS apps natively from Windows or Linux.**

No Mac. No Xcode. No WSL.

[What's new](#what-this-edition-adds) • [Flutter versions](#flutter-versions-and-ios-compilers) • [Install](#installation) • [Quick start](#quick-start) • [Wi-Fi](#run-over-wi-fi) • [Commands](#command-reference) • [App Store](#app-store-builds) • [IDE](#ide-integration) • [FAQ](#faq) • [Under the hood](#under-the-hood)

</div>

---

xcross reimplements the Flutter iOS build pipeline and the iOS 17+ CoreDevice launch protocol in pure Dart. It compiles your Flutter app with the official Swift and LLVM toolchains, signs it with your Apple ID or an App Store Connect API key, installs it on a physical iPhone, launches it, and gives you full hot reload - all from a Windows or Linux machine.

This repository is the **XCross Studio edition** of [arxdeus/xcross](https://github.com/arxdeus/xcross): the same engine, with the additions below, released here and used by the XCross Studio desktop app. It is the command-line engine only; everything it does works on its own.

| Feature | Details |
|---|---|
| **Native Windows & Linux** | Runs directly on the host with official Swift and LLVM toolchains - no VM, no WSL, no macOS anywhere |
| **Hot reload & hot restart** | Full `r` / `R` workflow on a real iPhone over an iOS 17+ RSD tunnel |
| **Release builds for every Flutter version** | iOS AOT compilers for Windows and Linux, built for each Flutter release and checked byte for byte against Flutter's own ([details](#flutter-versions-and-ios-compilers)) |
| **Plugins without CocoaPods** | SwiftPM plugins, CocoaPods pods converted to Swift packages, and podspec-only plugins drafted automatically |
| **App Store from your PC** | Preflight checks, IPA, upload, TestFlight, store listing, icons and splash screens |
| **Native signing & install** | Apple ID (free account works) or App Store Connect API key; signing runs in-process |
| **USB and Wi-Fi devices** | Pair wirelessly over a trusted USB connection, or directly from Paired Devices on iOS 27+ |
| **IDE debugging** | One command sets up VS Code (F5, breakpoints, DevTools) or JetBrains IDEs via DAP |
| **Direct build pipeline** | `frontend_server` → `clang` → `ld64.lld` → `.app` / `.ipa` - no Xcode build system involved |

> [!IMPORTANT]
> xcross builds **debug (JIT)** device and simulator apps, and **profile/release (AOT)** device apps. Launching with xcross requires **iOS 17 or later** on the device (`xcross install` also installs on iOS 15 and 16).

## What this edition adds

Everything below is in this repository's releases, on top of [arxdeus/xcross](https://github.com/arxdeus/xcross). The [changelog](CHANGELOG.md) has the details of each.

- **iOS compilers for every Flutter release.** Release and profile builds need Flutter's iOS AOT compiler, which Flutter ships for macOS only. xcross downloads Windows and Linux builds of it from [xcross-compilers](https://github.com/Abdelrahman1atef/xcross-compilers), built for each Flutter stable release from the Dart SDK sources and published only when its output is byte-identical to Flutter's own compiler, then from [xcross_gen_snapshot](https://github.com/arxdeus/xcross_gen_snapshot). A Flutter patch release with no compiler of its own uses the one built from the same Dart revision. See [Flutter versions and iOS compilers](#flutter-versions-and-ios-compilers).
- **Flutter SDKs for iOS builds.** `xcross flutter sdk list | install | use | auto | reset` keeps a Flutter that has an iOS compiler for iOS builds only, without touching your own Flutter. A failed download names the cause (GitHub not reachable, connection dropped, disk full, path too long) and retries by itself.
- **Plugins that use CocoaPods, without CocoaPods.** Pods are fetched from the CocoaPods CDN and converted into local Swift packages: binary, Objective-C, Swift and mixed pods, with version resolution and lock files ([Flutter plugins](#flutter-plugins)).
- **Podspec-only plugins keep their native code.** The build drafts a `Package.swift` override from the podspec, and knows the vendors' own Swift packages for many common pods (Google Maps, Firebase, OneSignal, RevenueCat, AppsFlyer, WebRTC and more).
- **App Store pipeline.** `xcross release preflight` stops a build on problems App Store Connect would reject (icon alpha, missing purpose strings, privacy manifest, export compliance) before it compiles; then `release check`, `publish`, `testflight` and `appstore metadata`. `xcross privacy init` writes the privacy manifest without Xcode.
- **Icons and splash screens.** `xcross icons` and `xcross splash` generate and check every size for iOS, Android, web and macOS from one image.
- **Permissions, capabilities and launch screens like Xcode.** Real compiled launch storyboards, push and capability entitlements, and permission strings that make iOS actually ask.
- **Device tools.** `xcross logs`, `crashes`, `app info`, `app list`, `inspect`, `sign` and `install` for any `.ipa`.
- **Built for GUIs.** `XCROSS_EVENTS=ndjson` turns builds, runs and checks into a stream of JSON events, with stable diagnostic codes and hints ([Using xcross from a GUI](#using-xcross-from-a-gui)).

## Requirements

Both platforms need the same five ingredients:

| Requirement | Purpose |
|---|---|
| [Flutter](https://flutter.dev) | Your app's SDK; xcross reuses its engine artifacts |
| [Swift toolchain](https://www.swift.org/install/) 6.4 or newer (on macOS, the Swift paired with your Xcode) | Compiles SwiftPM plugins and runner glue code |
| [LLVM](https://releases.llvm.org/) (`clang`, `clang++`, `llvm-ar`, `ld64.lld` on `PATH`) | Compiles and links the iOS Mach-O binaries |
| Python 3 + [`pymobiledevice3`](https://github.com/doronz88/pymobiledevice3) | Device communication and the iOS 17+ RSD tunnel |
| A complete `Xcode.xip` ([xcodereleases.com](https://xcodereleases.com/)) | Processed **once** by `xcross sdk install` into a private Darwin Swift SDK |

> [!IMPORTANT]
> **Install the Swift toolchain before running `xcross setup` or `xcross sdk install`.** xcross never installs Swift for you on any host, and both commands refuse to run without it.
>
> `xcross sdk install` patches the Darwin SDK with the *selected* Swift toolchain's clang headers and records which toolchain that was. The resulting SDK is only usable by that toolchain, so changing Swift afterwards (`swiftly use`, `mise use`, a distro upgrade) means re-running `xcross sdk install`. Pick your Swift version first and stay on it.
>

> [!NOTE]
> Download the Xcode archive from [xcodereleases.com](https://xcodereleases.com/) (requires an Apple ID). It is only used as SDK *input* - neither Xcode nor macOS is ever installed or executed. xcross extracts the iOS SDK and frameworks from the archive with its own pure-Dart xar/pbzx/cpio readers. Don't redistribute the extracted Apple SDK.

## Flutter versions and iOS compilers

| Build | Flutter versions |
|---|---|
| **Debug** (`xcross flutter run`, hot reload) | Any Flutter version xcross supports: debug builds need no extra compiler |
| **Profile and release** (`--profile`, `--release`, App Store) | Every Flutter version with an iOS compiler for your host (below) |

Flutter publishes its iOS AOT compiler (`gen_snapshot`) for macOS only, and each compiler fits exactly one Flutter version. On Windows and Linux, xcross looks for the compiler of your Flutter version in this order:

1. **[xcross-compilers](https://github.com/Abdelrahman1atef/xcross-compilers/releases)**: built for every Flutter stable release, newest first, for `windows-x64`, `windows-arm64`, `linux-x64` and `linux-arm64`, release and profile. A compiler is published only after it compiled a real `flutter build ios` app to an `App` and `app.o` byte-identical to what Flutter's official compiler wrote on a Mac. New Flutter releases are picked up automatically.
2. **[xcross_gen_snapshot](https://github.com/arxdeus/xcross_gen_snapshot/releases)**, the upstream project's compilers.
3. **The same Dart revision.** A patch release with no compiler of its own (for example 3.47.7) uses the one of its line built from the same Dart revision: the compiler depends only on the Dart revision, so they are byte-identical. It is checked like any download, and its `--version` must name your SDK's Dart version.

Every download is checked against its release's SHA-256 digests (archive and executable) before it runs, and cached per engine revision.

```sh
xcross flutter doctor        # says, for profile and release, where the compiler comes from (or that none exists)
xcross flutter sdk list      # the Flutter used for iOS builds, and whether it has a compiler
xcross flutter sdk auto      # no compiler for yours? install the nearest Flutter that has one, for iOS builds only
xcross flutter sdk install 3.47.8 && xcross flutter sdk use 3.47.8   # or pick one yourself
xcross flutter sdk reset     # back to your own Flutter
```

Your own Flutter installation is never changed: iOS builds use the one xcross installed under `<config>/xcross/flutter-sdks/`. A compiler of your own can be pinned with `ios_gen_snapshot` in the [configuration](#configuration).

## Installation

Both installers download the latest release of this repository, install it, **add xcross to your `PATH`**, verify the binary, and print any missing prerequisites with install hints. (The XCross Studio desktop app installs and updates the engine by itself.)

### Windows (native)

1. One-line install (PowerShell). It picks the native x64 or ARM64 build, even when run from an emulated x64 PowerShell on Windows on ARM:

   ```powershell
   irm https://raw.githubusercontent.com/Abdelrahman1atef/xcross-studio/main/install.ps1 | iex
   ```

2. Install [Flutter](https://docs.flutter.dev/get-started/install/windows), then let xcross install everything else:

   ```powershell
   xcross setup
   ```

   This runs the setup script for your package manager, which is built into the xcross you installed (nothing is downloaded to get it): [`winget.ps1`](setup/winget.ps1), [`scoop.ps1`](setup/scoop.ps1), or [`choco.ps1`](setup/choco.ps1). If several are installed, xcross asks which one to use. If none is, it runs [`direct.ps1`](setup/direct.ps1), which downloads the vendor installers itself. Pick one explicitly with `xcross setup --manager winget|scoop|choco|direct`. xcross first prints the script's name, source, and SHA-256 and waits for `y`. The script then asks before each package: Visual Studio Build Tools (MSVC + Windows SDK, which Swift links against), Swift, LLVM (its `bin` goes on your `PATH`), and Python 3. Then it installs `pymobiledevice3`. Installers that need elevation raise their own UAC prompt. `xcross setup --yes` accepts every prompt, and `xcross setup --only llvm,python` (any of `vs`, `swift`, `llvm`, `python`, `pymobiledevice3`) installs just those.

   | | `winget.ps1` | `scoop.ps1` | `choco.ps1` | `direct.ps1` |
   |---|---|---|---|---|
   | VS Build Tools | `Microsoft.VisualStudio.2022.BuildTools` | vendor installer¹ | `visualstudio2022buildtools` | vendor installer¹ |
   | Swift | `Swift.Toolchain` | `main/swift` | vendor installer¹ | vendor installer¹ |
   | LLVM | `LLVM.LLVM` | `main/llvm` | `llvm` | GitHub release² |
   | Python | `Python.Python.3.13` | `main/python` | `python313` | python.org² |

   ¹ Scoop's official buckets have no Build Tools, and Chocolatey has no Swift package. For those, the script downloads `aka.ms/vs/17/release/vs_BuildTools.exe` or the latest release from `download.swift.org` and runs it only with a valid Authenticode signature from Microsoft or Apple. ² The installer must also match the SHA-256 that GitHub or python.org publishes (and, for Python, the Python Software Foundation signature). `XCROSS_SWIFT_VERSION`, `XCROSS_LLVM_VERSION`, and `XCROSS_PYTHON_VERSION`, with optional `*_SHA256`, pin versions for `direct.ps1`. Chocolatey needs an Administrator PowerShell. Scoop expects a normal one.

3. Open a new terminal so the new `PATH` applies, then build the Darwin SDK:

   ```powershell
   xcross sdk install C:\Downloads\Xcode.xip   # once, takes a while
   ```

   The SDK is tied to the Swift active here, so re-run `xcross sdk install` if you later switch Swift versions.

### Linux

1. One-line install:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/Abdelrahman1atef/xcross-studio/main/install.sh | sh
   ```

2. Install the Swift toolchain, which xcross does not install for you ([swiftly](https://www.swift.org/install/linux/) is the easiest route):

   ```sh
   curl -fsSL https://swiftlang.github.io/swiftly/swiftly-install.sh | bash
   swiftly install latest
   swift --version   # must work before the next step
   ```


3. Let xcross install its distro dependencies and `pymobiledevice3` (via `pipx`), and build the Darwin SDK:

   ```sh
   xcross setup
   xcross sdk install ~/Downloads/Xcode.xip   # once, takes a while
   ```

   `xcross setup` detects `apt`, `dnf`, or `pacman` (and asks which to use when the answer is ambiguous). It also installs `usbmuxd`, `usbutils`, and `libimobiledevice` for USB device access and diagnostics. `pymobiledevice3` goes into its own `pipx` venv, and `pipx ensurepath` puts `~/.local/bin` on your `PATH` - open a new shell for that to take effect.

   The SDK is tied to the Swift you had active here. If you later switch Swift versions, re-run `xcross sdk install`.

   Prefer a script you can read first? [`setup/apt.sh`](setup/apt.sh), [`setup/dnf.sh`](setup/dnf.sh), and [`setup/pacman.sh`](setup/pacman.sh) install the same packages, plus Swift through swiftly if it is missing. Run one directly (`sh setup/apt.sh`) or point `setup:` in your config at it (see [Configuration](#configuration)). Before any third-party installer (apt.llvm.org's `llvm.sh`, swiftly) runs, they print its name and URL and wait for `y`.

### Verifying a release

Every release archive is built by [`release.yml`](.github/workflows/release.yml) and signed with a [SLSA build provenance attestation](https://docs.github.com/actions/security-for-github-actions/using-artifact-attestations) that binds the archive's digest to the commit it was built from. The release job refuses to publish an artifact whose provenance does not match, so a bundle produced outside this repository can never reach the release page.

To check an archive yourself with the [`gh`](https://cli.github.com) CLI (`SHA256SUMS.txt` is published alongside the archives for plain integrity checks):

```sh
gh attestation verify xcross-linux-x64.tar.gz \
  --repo Abdelrahman1atef/xcross-studio \
  --signer-workflow Abdelrahman1atef/xcross-studio/.github/workflows/release.yml \
  --source-digest <commit-sha-from-the-release-notes>
```

### Updating

```sh
xcross --version          # what you are running
xcross update --check     # what the latest release is
xcross update             # download, verify, and swap it in
```

`xcross update` downloads the release archive for your platform, verifies it against the release's `SHA256SUMS.txt` before touching anything, and replaces the installed `bin/` and `lib/` files in place. A checksum that does not match aborts the update, and a failure part-way through restores the previous version. On Linux a system-wide install (`/usr/local/...`) prompts for `sudo`; on Windows a machine-wide install needs an Administrator terminal.

Other commands print a one-line hint when a newer release exists. That hint comes from a cache refreshed at most once a day, so it costs no time on the command you actually ran. Set `XCROSS_NO_UPDATE_CHECK=1` to turn it off; it is already off in CI, for non-interactive output, and for builds from source.

Use `xcross update --ref <ref>` to target a specific git ref. `<ref>` may be a released tag, a branch name, a full 40-character commit SHA, or a full ref such as `refs/tags/1.2.0` or `refs/heads/main`.

```sh
xcross update --ref 1.2.0                    # install verified assets from release tag 1.2.0
xcross update --ref main                     # build and install from the main branch tip
xcross update --ref 85e325fb487cc816c9839bf64439f65771c92f62  # build and install from a specific commit
xcross update --check --ref refs/heads/main  # report ref kind + commit, do not install
```

If a tag and branch share the same short name, the exact tag wins. Tag refs install the existing verified release assets for that version. Branch and commit refs clone this repository (`Abdelrahman1atef/xcross-studio`) into temporary storage, fetch the exact commit, run local `dart pub get` and the shared `tool/build_xcross.dart` wrapper, install the resulting bundle with the same atomic swap and rollback path as release updates, and delete the temporary checkout whether the install succeeds or fails.

A source-ref install reports the normalized ref, for example `xcross main (unreleased build)`. Running `xcross update` from any unreleased build always returns to the latest official release.

Source refs require both `git` and `dart` on `PATH`. `xcross update --check --ref <ref>` resolves the ref first, then reports its kind and commit without installing anything. Use `--force` to reinstall the current release when you are updating without `--ref`.

## Authentication

xcross talks to Apple's Developer Services directly. Two options:

|  | Apple ID | App Store Connect API key |
| --- | --- | --- |
| Apple account needed | free account works | paid Developer Program |
| Interactive login | password + 2FA once | none, good for CI |
| Protocol | the one Xcode speaks, undocumented | official and documented |
| Build, sign, install, run | yes | yes |
| **App Groups** (share extensions) | **created and attached automatically** | cannot be created; use one you attached yourself, see [app extensions](docs/app-extensions.md#app-store-connect-api-keys) |

The App Groups row is the only functional difference, and it is Apple's doing
rather than xcross's: the public App Store Connect API has no App Groups
resource at all, while the older protocol Xcode itself uses does. It only
matters if your app ships a share or action extension that hands data back to
the app.

### Apple ID (free account works)

```sh
xcross auth --apple-id you@example.com
```

The command prompts for your password and 2FA code, then stores **only** the resulting Developer Services session - never your password.

> [!WARNING]
> Do not use your primary Apple ID. xcross signs in through a non-standard path for non-macOS systems, and Apple may treat that as unusual activity: an account used with xcross can end up locked, and an appeal may not reinstate it. Creating a throwaway Apple ID takes a minute and a free account is all you need, which keeps that a minor inconvenience rather than losing your purchases, iCloud data, and devices.

Apple's GrandSlam login expects **Mac**-matching machine attestation (anisette).
By default `xcross auth` uses a remote [Omnisette](https://github.com/SideStore/omnisette-server)
**v3** server (`https://mac-ani.jkcoxson.com`) that synthesizes those headers:

```sh
xcross auth --apple-id you@example.com
# override the default server:
xcross auth --apple-id you@example.com --anisette-url https://example.test
# or:
XCROSS_ANISETTE_URL=https://example.test xcross auth --apple-id you@example.com
```

Pick any Mac Omnisette server from the
[public list](https://xcross.sh/docs/authentication/#remote-anisette), or
[self-host](https://github.com/SideStore/omnisette-server). The URL is stored
with the session so later signing keeps using it; set `XCROSS_ANISETTE_URL`
again to point at a different server.

`--adi-library-dir` is a legacy opt-in to local Android ADI libraries
(`libCoreADI.so`, `libstoreservicescore.so`). Apple currently rejects that
identity (`-80046`); prefer the Omnisette default.

> [!WARNING]
> A public Omnisette server is a third party: the operator sees your IP and
> login/signing traffic and holds the device identity your account is attested
> against. Prefer a self-hosted server, and use a secondary Apple ID.

### App Store Connect API key

```sh
xcross auth --issuer-id <uuid> --key-id <id> --private-key /path/to/AuthKey.p8
```

Non-interactive, so this is the one to use on CI. It provisions everything
except App Groups, which Apple's public API cannot manage at all. If your app
has a share extension, attach the group to your App IDs once (in Xcode or at
developer.apple.com) and point xcross at it:

```sh
XCROSS_APP_GROUP=group.com.example.Shared xcross flutter run
```

See [iOS app extensions](docs/app-extensions.md) for the details.

App Store Connect has two kinds of key. A **Team key** (Users and Access →
Integrations → Team Keys, role Admin or App Manager) is the one that signs and
installs. An **Individual key** (Integrations → Individual Keys) has no Issuer
ID: leave out `--issuer-id`, or pass one anyway and xcross notices Apple only
accepts the key as individual and saves it that way.

```sh
xcross auth --key-id <id> --private-key /path/to/ApiKey_<id>.p8
```

Apple lets individual keys read App Store Connect but not manage devices,
certificates, bundle IDs or profiles, so `xcross auth` and `xcross flutter
doctor` warn that installing on an iPhone needs a Team key or your Apple ID.

### Working offline

Apple is only needed to provision: the first run of an app on a device, or
when something about it changes. After that, `xcross flutter run` keeps working
without a network. When Apple cannot be reached (or the saved Apple ID session
has expired), xcross signs with the certificate and provisioning profile the
last online run cached, prints a warning, and installs as usual.

```sh
XCROSS_OFFLINE=1 xcross flutter run   # skip Apple entirely, even when online
```

Offline signing still needs, for that app and device:

- one earlier online run, so a profile is cached;
- a profile that lists the device and has not expired (free accounts: 7 days);
- no new extension, capability, or App Group since then.

If any of those is missing, xcross says which and asks you to reconnect once.

### Sign out

```sh
xcross auth clean
```

Deletes the saved App Store Connect key, the Apple ID session and its machine attestation state, and every certificate, private key, and provisioning profile xcross minted. The downloaded ADI libraries stay - they are architecture-specific binaries that identify no account.

## Quick start

```sh
# 1. One-time machine setup (see Installation above)
#    Swift must already be installed: xcross does not install it, and both
#    commands below refuse to run without it.
xcross setup
xcross sdk install ~/Downloads/Xcode.xip
xcross auth --apple-id you@example.com

# 2. Check build and run requirements without changing anything
cd my_flutter_app
xcross flutter doctor

# 3. Once per device reconnect: mount DDI + start the RSD tunnel
#    (Administrator PowerShell on Windows; root on Linux)
xcross tunnel

# 4. Build, sign, install, launch, hot-reload
xcross flutter run

# 5. Optional: wire up your IDE
xcross ide vscode      # or: xcross ide idea
```

While the app is running:

| Key | Action |
|---|---|
| `r` | Hot reload |
| `R` | Hot restart |
| `q` / `Ctrl-C` / `Ctrl-D` | Quit |

With multiple iPhones connected, an interactive terminal shows a numbered device picker; pass `-u <UDID>` for CI or piped runs.

`xcross flutter doctor` and `xcross compose doctor` are read-only: each checks only what its own framework needs (the project, the toolchain its build drives, and the Darwin SDK), plus the shared deployment requirements (device tooling, authentication, and connected iOS versions), without building, installing, or launching. Results are grouped into sections, each headed by its worst status. Missing project or device context is a warning; failed requirements return a nonzero exit code.

## Run over Wi-Fi

Prepare the wireless pairing and RSD tunnel first:

```sh
xcross tunnel --wifi
```

The command automatically follows this order:

1. **USB connected:** pairs RemotePairing through the iPhone's trusted lockdown connection, enables Wi-Fi connections, opens the RSD tunnel, and mounts the Developer Disk Image. Unplug USB when it reports that the device is ready.
2. **No USB, saved pairing available:** tries to reconnect to the saved wireless device.
3. **Saved device does not reconnect:** starts a fresh, suffixed `remote pair-host` advertisement so iOS does not reuse the stale entry.
4. **No USB and no saved pairing:** starts `remote pair-host` immediately.

Then run the app over Wi-Fi:

```sh
xcross flutter run --wifi
```

Device-initiated pairing without USB requires **iOS 27 or later**. When prompted, open **Settings > Privacy and Security > Developer Mode > Paired Devices > Other Devices**, tap the exact `xcross-...` name printed in the terminal, and enter the six-digit code. On iOS 17 through 26, connect USB once and run `xcross tunnel --wifi` to create the wireless pairing through lockdown.

Keep the iPhone unlocked and on the same local subnet during setup. Wireless discovery uses mDNS on UDP port 5353, so guest-network isolation, VPN routing, firewalls, NAT, and unbridged VM or WSL networking can block it. For diagnostics, put the verbose flag at the end:

```sh
xcross tunnel --wifi -v
```

Without an explicit transport flag, `xcross flutter run` prefers a locally attached USB device and falls back to Wi-Fi when no USB device is available. Use `--wifi` or `--usb` to force one transport.

See the full [Wi-Fi setup and troubleshooting guide](https://xcross.sh/docs/wireless).

## Configuration

By default xcross takes the world as it finds it: whatever is on `PATH`. One optional YAML file changes that. Declare where Swift, LLVM, Flutter, and the SDK actually live, and every command - plus every process it spawns, including IDE launches - is rebuilt around that declaration before anything compiles.

It is read from `XCROSS_CONFIG`, else `config.yaml`/`config.yml` under the platform xcross config directory. Configured executables win and must be real executable paths; everything unspecified (`git`, device utilities, system commands) still resolves through the invoking `PATH`. `environment.PATH` prepends its entries to that inherited `PATH` for child processes. No file means nothing changes.

```yaml
toolchains:
  swift: /absolute/swift/bin
  llvm:
    - /absolute/clang/bin
    - /absolute/lld/bin
    - /absolute/llvm/bin
roots:
  darwinSdk: /absolute/path/to/xcross-darwin.artifactbundle
  flutterSdk: /absolute/path/to/flutter
  xcross: /absolute/path/to/xcross
  javaHome: /absolute/path/to/jdk
  konanData: /absolute/path/to/konan-data
environment:
  PATH:
    - /absolute/toolchain/bin
setup: https://raw.githubusercontent.com/Abdelrahman1atef/xcross-studio/main/setup/apt.sh
```

Edit it with `xcross config`, inspect it with `xcross config show`, prove it with `xcross config validate`.

`setup` makes `xcross setup` run that script (an absolute path or an HTTP(S) URL) instead of its built-in installer. Before running anything, xcross prints the script's name, source, and SHA-256 and asks for confirmation. Pass `--yes` to skip the prompt, which is required when there is no terminal. Remote scripts are cached by content hash, and `xcross update` refreshes them.

**Full reference: [xcross.sh/docs/configuration](https://xcross.sh/docs/configuration)** - every key, discovery order, variable expansion, and the runtime overlay.

## Command reference

| Command | Description |
|---|---|
| `xcross setup` | Install host dependencies: apt/dnf/pacman or Homebrew packages, `pipx`, and `pymobiledevice3` (Linux/macOS need Swift on `PATH` first). On Windows, or when `setup:` is configured, runs a setup script after showing its name, URL, and SHA-256 and asking first (`--yes` skips the prompt) |
| `xcross config` | Interactively create or edit executable overrides, Swift/LLVM toolchain directories, roots, and child-environment paths |
| `xcross config show` / `validate` | Print the selected YAML configuration or validate all configured paths |
| `xcross sdk install <Xcode.xip>` | Extract a private Darwin Swift SDK from an Xcode archive, patched against the Swift toolchain currently on `PATH` |
| `xcross sdk clean` | Remove the installed Darwin Swift SDK and any leftover backup or staging copies |
| `xcross flutter precache [--mode debug\|profile\|release\|all]` | Download the iOS engine artifacts and, for profile and release, the iOS AOT compiler for the current Flutter SDK, so CI images and offline machines build without the network |
| `xcross cache prune [--dry-run] [--older-than <days>]` | Remove cached Flutter engine artifacts and AOT compilers for engines no discoverable Flutter SDK uses and that went unused for `--older-than` days (default 30) |
| `xcross auth` | Save Apple ID or App Store Connect credentials |
| `xcross auth status` | Show how you signed in and what each kind of build uses, offline |
| `xcross auth clean` | Delete saved credentials, sessions, and signing material |
| `xcross tunnel` | Mount the Developer Disk Image + start the iOS 17+ RSD tunnel over USB |
| `xcross tunnel --wifi` | Prepare wireless pairing, reconnect or advertise pair-host, mount DDI, and open the Wi-Fi RSD tunnel |
| `xcross flutter run` | Build → sign → install → launch → hot reload |
| `xcross flutter build --release` | Build an ahead-of-time compiled `.app` or `.ipa` (also `--profile`) |
| `xcross flutter doctor` | Read-only check of the Flutter project, Swift/LLVM iOS toolchain, Darwin SDK, authentication, and devices |
| `xcross compose setup` | Install Kotlin/Compose iOS cross-build helpers |
| `xcross compose doctor` | Read-only check of the Gradle project, Kotlin/Native, JDK 21+, Gradle, swiftc, clang, Darwin SDK, `ld64.lld`, authentication, and devices |
| `xcross compose build` | Build a KMP iOS framework or `.app` from the current Gradle project |
| `xcross compose run -d <device>` | Build, sign, install, and launch a runnable KMP iOS app |
| `xcross compose run --watch` | Same, plus `r` to rebuild + reinstall + relaunch (Compose has no in-place reload) |
| `xcross flutter clean` | Clear this Flutter project's xcross native asset and SwiftPM build caches (device and simulator) |
| `xcross compose clean` | Clear this Compose project's xcross build output and Kotlin/Native caches (device and simulator) |
| `xcross flutter dap` | Run the Debug Adapter Protocol server (used by IDEs) |
| `xcross ide vscode` | Upsert `.vscode/*` for Run & Debug / Hot Reload |
| `xcross ide idea` | Write a JetBrains DAP run configuration (needs LSP4IJ) |
| `xcross update` | Update xcross to the latest release, verified against its checksums |
| `xcross completion` | Print a shell-completion script |
| `xcross sign <ipa\|app> [-o <out.ipa>] [--udid <id>]... [--bundle-id <id>]` | <!-- studio: --> Re-sign any app with your Apple ID or App Store Connect key and write an installable `.ipa` (nothing is installed; `--udid` adds testers' devices). Install it later with `xcross install --no-resign` or any tool |
| `xcross install <ipa\|app> [--udid <id>] [--ddi <dir>]` | <!-- studio: --> Sign any app with your Apple ID and install it on the iPhone (iOS 15+); iOS 15/16 open via your own developer disk image or from the icon |
| `xcross logs [--app <bundle-id>] [--preset push\|crash\|flutter] [--json]` | <!-- studio: --> Live iPhone log over USB (iOS 16 and 17+), with filters, presets, `--save`, NDJSON. XCross Studio fork addition |
| `xcross app info <bundle-id>` | <!-- studio: --> Installed app's version, signer type, team and entitlements as installed (push / associated domains ✔/✖) |
| `xcross crashes list\|pull` | <!-- studio: --> List crash reports on the iPhone and pull one with its exception summary |
| `xcross devices [--json] [--watch]` | <!-- studio: --> List the iPhones connected by USB with their iOS version (used by the XCross Studio GUI); `--watch` keeps running and reports the list again on every plug, unplug or device service restart (studio: 017) |
| `xcross app list [--json]` | <!-- studio: --> List the apps you installed on the iPhone (used by the GUI's app picker) |
| `xcross plugin list` / `xcross plugin shim <plugin>` | <!-- studio: --> Show how each iOS plugin is built; draft a `Package.swift` override from a podspec-only plugin's podspec |
| `xcross inspect <ipa\|app> [--json] [--normalize]` | <!-- studio: --> Read-only report of what is inside an `.ipa` or `.app`: Info.plist, entitlements per Mach-O, provisioning profile summary, icons, launch screen, frameworks and extensions. XCross Studio fork addition |
| `xcross flutter sdk list \| install <version> \| use <version\|path> \| auto \| reset` | <!-- studio: 014 --> Flutter SDKs for iOS builds only: list them, install one, select one (or your own folder), pick the nearest with an iOS compiler, or go back to your own Flutter ([details](#flutter-versions-and-ios-compilers)) |
| `xcross plugin check` / `plugin status [--json]` | <!-- studio: --> What a build will do with each iOS plugin (SwiftPM, drafted, converted pods, left out) without compiling |
| `xcross pods report [<Pod>] [--json]` / `cache clear pods` | <!-- studio: 046 --> Redacted reports for pods a build left out; clear cached pod downloads and converted packages |
| `xcross release preflight [--json]` | <!-- studio: --> App Store problems the project already shows (icon alpha, purpose strings, privacy manifest, export compliance), in seconds and before compiling |
| `xcross privacy init` | <!-- studio: --> Write `ios/Runner/PrivacyInfo.xcprivacy` and add it to the Runner target, without Xcode |
| `xcross icons generate\|check` / `xcross splash generate\|check` | <!-- studio: 023, 024 --> App icons and splash screens for every size from one image ([App Store builds](#app-store-builds)) |
| `xcross engine info --json` | <!-- studio: 008 --> Which engine and protocol version a GUI is talking to |

<details>
<summary><b><code>xcross flutter run</code> options</b></summary>

```text
-t, --target <path>          entrypoint (default: lib/main.dart)
-D, --dart-define k=v        repeatable
    --dart-define-from-file  .json / .env, repeatable
    --[no-]pub               run flutter pub get first (default: on)
    --build-name             CFBundleShortVersionString
    --build-number           CFBundleVersion
    --flavor                 flavor entrypoint selection
-i, --ipa                    package an .ipa instead of an .app
-d, --device-id              device id or name
-u, --udid                   device UDID; wins if both selectors are set
    --usb / --wifi           search USB-attached or wireless devices only
    --device-connection      attached | wireless | both
    --route
-a, --dart-entrypoint-args   repeatable
-v, --verbose
```
</details>

<!-- studio: XCross Studio feature 001 (specs/001-inspect) -->
<details>
<summary><b><code>xcross inspect</code> options</b></summary>

```text
<path>           an .ipa file or a .app directory
    --json       print one JSON document (schema: specs/001-inspect/contracts/inspect.schema.json)
    --normalize  with --json: replace hashes, sizes, profile UUIDs and dates with
                 stable placeholders so two builds of the same source compare equal
```

Exit codes: `0` report printed (problems are listed as issues), `1` the input cannot be inspected (stable
`inspect.*` error code; with `--json` an error document is printed), `64` usage error. The command never modifies the
input and never contacts the network or a device.

<!-- studio: 002 -->
**Diagnostics codes:** errors and warnings from the fork carry stable codes such as `device.ios_unsupported`,
`toolchain.path_linker_unusable` or `build.asset_unsupported`, each followed by a `hint:` line; see
`specs/002-quick-wins/contracts/diagnostics.md`. Bundle versions come from `--build-name`/`--build-number`, then
`pubspec.yaml`, then the xcconfig, then the Xcode project, then 1.0.0 (1).

**Reporting a bug:** attach the output of `xcross inspect <ipa> --json --normalize`. By design it contains no device
UDIDs, certificate data, API keys or Info.plist values outside a short allow-list, and no absolute paths.
</details>

<!-- studio: 008 -->
## Using xcross from a GUI

This repository holds only the `xcross` engine (CLI). Desktop apps drive it as a subprocess and keep no build logic
of their own. `xcross engine info --json` tells a GUI which engine and protocol version it is talking to.

<!-- studio: 012 -->
**Machine-readable output:** with `XCROSS_EVENTS=ndjson` set, `xcross flutter build`, `flutter run`, `install` and
`flutter doctor` print one JSON event per line on stdout: `step`, `progress`, `log`, `warning`/`error` (with `code` and
`hint`), `artifact` (the `.app`/`.ipa` path), `device`, `check` and `done` (exit code). A GUI can use it for a
step list, progress bar, issue list and Install button. Schema:
[specs/012-build-events/contracts/events.schema.json](specs/012-build-events/contracts/events.schema.json).

<!-- studio: 014 -->
**No iOS compiler for a Flutter version?** A release or profile build stops with `[build.gen_snapshot_unavailable]`,
names the nearest Flutter version that has one, and `xcross flutter sdk auto` installs it for iOS builds only. See
[Flutter versions and iOS compilers](#flutter-versions-and-ios-compilers) for where compilers come from.

## Compose Multiplatform

`xcross compose` builds Kotlin Multiplatform iOS targets on Windows x64 and Linux x64 using the same private Darwin SDK, Swift, LLVM, and `xcross auth` signing flow as Flutter. Linux arm64 can run the CLI, but Compose iOS builds are limited by missing upstream Kotlin/Native host artifacts.

```sh
xcross setup
xcross sdk install /path/to/Xcode.xip
xcross compose setup
cd examples/compose_app        # or examples/kmp_swift_app
xcross compose doctor
xcross compose build
xcross compose run -d <device>
```

Projects with a Kotlin `ComposeUIViewController` entry or a SwiftUI `@main` host produce an `.app`. Framework-only KMP modules still build the iOS framework, but `xcross compose run` and `--ipa` are unavailable until the project has a runnable app entry. Physical-device launch requires iOS 17 or later.

Compose launches use native attached debugging to supervise the process after install. There is no Kotlin source DAP yet.

Compose has no in-place hot reload, and cannot have one the way Flutter does: Kotlin/Native compiles the app ahead of time to a Mach-O binary, and JetBrains' own [Compose Hot Reload](https://kotlinlang.org/docs/multiplatform/compose-hot-reload.html) works only on a JVM target, through JetBrains Runtime class redefinition. What xcross offers instead is a fast restart loop:

```bash
xcross compose run --watch   # press r to rebuild + reinstall + relaunch, q to quit
```

`r` rebuilds only when a watched source (`.kt`, `.kts`, `.toml`, `.properties`) actually changed, then reinstalls and relaunches while keeping the device, RSD tunnel, and console session warm. An unchanged `r` leaves the running app alone.

Rebuilds are dominated by the Kotlin/Native compile (~133s of a ~147s cycle on the Compose sample, since it is a whole-program AOT compile). xcross fingerprints the framework's inputs and compiler flags, so a build whose inputs did not change skips `konanc` entirely: **~145s → ~12s** on the sample.

## Flutter plugins

Swift Package Manager iOS plugins work on both Windows and Linux. Their native code is compiled against the extracted Darwin SDK into `Frameworks/libFlutterPluginsGenerated.dylib` and registered by the generated runner.

### Plugins that use CocoaPods

With the CocoaPods pod converter (feature 046), xcross compiles plugins that depend on CocoaPods pods on Windows and Linux without running CocoaPods, Ruby, or Xcode.

Each pod is fetched from the CocoaPods CDN, converted into a local Swift package under `.dart_tool/xcross/Packages/pod-<Pod>`, and integrated directly into SwiftPM compilation:
- **Binary pods** (`binary`): Vendor `.xcframework` archives, legacy `.framework` bundles (converted to xcframeworks), and static `.a` libraries with header trees.
- **Source pods** (`objc`, `swift`, `mixed`): C, Objective-C, Objective-C++, and Swift sources with automatic header trees, synthetic umbrella headers, module maps, and language standard configuration.
- **Dependency resolution**: Parses `ios/Podfile.lock` or uses the built-in backtracking resolver against CDN specs, writing `ios/xcross-pods.lock` when no `Podfile.lock` is present.
- **Gating & switches**: Enable with `XCROSS_POD_CONVERTER=on`. Fine-tune enabled kinds with `XCROSS_POD_KINDS=binary,objc,swift,mixed` or exclude specific pods with `XCROSS_POD_SKIP=pod1,pod2`.
- **Automatic fallback**: If a converted pod fails compiling or linking during development, xcross logs a 4-part warning and rebuilds once with that pod excluded so the rest of your app continues running. Strict mode (`--strict`) and distribution builds fail immediately to guarantee full integrity.

#### Inspecting and Reporting Pods

```sh
xcross plugin status --json          # View converted pods and their resolution source
xcross pods report [<Pod>] [--json]  # View redacted diagnostic reports for left-out pods
xcross cache clear pods              # Clear cached pod downloads and converted packages
```

#### Troubleshooting Diagnostic Codes

| Code | Explanation | Recommended Action |
|---|---|---|
| `pod.resolve_conflict` | No version satisfies all plugin constraints | Align plugin versions in `pubspec.yaml` or run `pod update` on macOS. |
| `pod.lock_stale` | `Podfile.lock` pin no longer matches constraints | Refresh lockfile or delete `ios/Podfile.lock` to resolve afresh. |
| `pod.download_failed` | Failed to download pod source archive or git repo | Check network connection, proxies, or ensure Git is installed. |
| `pod.no_slice` | Binary framework missing slice for active build target | Build for arm64 iOS device instead of simulator if slice is missing. |
| `pod.bitcode` | Dynamic framework contains deprecated Bitcode | Update to a modern version of the pod built without Bitcode. |
| `pod.swift_binary_incompatible` | Swift binary lacks `.swiftinterface` | Request vendor build with `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`. |
| `pod.duplicate_with_swift_package` | Converted pod collides with a Swift package dependency | Prefer the official Swift package. |
| `pod.duplicate_symbols` | Duplicate symbols between colliding libraries | Exclude redundant dependencies or report the conflict. |
| `pod.compile_failed` | SwiftPM failed compiling converted pod sources | Inspect compiler output or submit diagnostic report. |
| `pod.converter_off` | Pod requires converter but `XCROSS_POD_CONVERTER` is off | Set `XCROSS_POD_CONVERTER=on`. |


<!-- studio: 006 -->
### Plugin overrides

A build drafts the `Package.swift` of a plugin that only ships a podspec, into `xcross_overrides/<plugin>/<version>/`
in the project, and says so with `[build.plugin_drafted]`. Review it and commit it. A plugin needing a pod with no known
Swift package is left out and named by `[build.plugin_unknown_pods]`. See what a build will do without compiling:
`xcross plugin check`. `XCROSS_PLUGIN_DRAFTS=off` turns drafting off.

Give xcross your own `Package.swift` for a plugin: for one that only ships a podspec, or one whose manifest does not
build. Put it in the project (or in `~/.xcross/overrides/` for all projects):

```text
my_app/xcross_overrides/
  some_plugin/
    Package.swift          # any version of some_plugin
    override.yaml          # optional: versions: ">=1.2.0 <2.0.0"
    1.4.0/Package.swift    # only for some_plugin 1.4.0 (wins over the folder above)
```

xcross searches `xcross_overrides/<plugin>/<version>/`, then `xcross_overrides/<plugin>/`, then the same two under
`~/.xcross/overrides/`. The override's files are laid over a staged copy of the plugin's `ios/` (or `darwin/`) folder,
which becomes the Swift package root, so targets can point at the plugin's own sources. The pub cache is never touched.

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "some_plugin",
    platforms: [.iOS("13.0")],
    products: [.library(name: "some-plugin", targets: ["some_plugin"])],
    dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
    targets: [
        .target(
            name: "some_plugin",
            dependencies: [.product(name: "FlutterFramework", package: "FlutterFramework")],
            path: "Classes",
            publicHeadersPath: "include"
        )
    ]
)
```

Let xcross draft the `Package.swift` from the plugin's podspec, then review it:

```sh
xcross plugin list                  # ✖ marks podspec-only plugins
xcross plugin shim some_plugin      # writes xcross_overrides/some_plugin/<version>/Package.swift
```

The draft maps common pods (Google Maps, Firebase, Pusher, Alamofire, SDWebImage, Kingfisher) to their Swift packages,
splits mixed Swift/Objective-C sources into two targets, copies in a privacy manifest kept outside the source folder, and
prints what still needs a human (unknown pods, other resources outside the source folder).

The build reports `build.plugin_override_applied` for each override it uses, and `build.plugin_override_invalid` for a
folder it skips (no `Package.swift`, bad `override.yaml`, other plugin versions). See
[specs/006-plugin-overrides](specs/006-plugin-overrides/spec.md).

<!-- studio: 007, 016 -->
## Your own AppDelegate code

When `ios/Runner/AppDelegate.swift` (or `.m`) has code beyond Flutter's template, such as `GMSServices.provideAPIKey`
or Firebase setup, xcross compiles the app target's own Swift/Objective-C sources into the `Runner` executable
(`XCROSS_RUNNER=auto`, the default; Swift toolchain required). A template AppDelegate keeps xcross's faster generic
runner. `XCROSS_RUNNER=project` or `shim` forces one or the other:

```sh
XCROSS_RUNNER=shim xcross flutter run --release      # PowerShell: $env:XCROSS_RUNNER = 'shim'
```

The app's code sees every plugin module, including SwiftPM C-family targets (`import FirebaseCore`) and binary
frameworks (`import GoogleMaps`). Even with the generic runner, the Google Maps key the AppDelegate passes to
`GMSServices.provideAPIKey` (a literal, or an Info.plist value such as `$(MAPS_API_KEY)` from xcconfig) is applied at
launch; `build.maps_key_unresolved` names a form xcross cannot read.

xcross supplies `GeneratedPluginRegistrant` (plugins are one Swift package) and a scene delegate that creates the
Flutter window (`Main.storyboard` cannot be compiled), so put custom code in `AppDelegate`, not `SceneDelegate`. If the
sources do not compile, the build continues with the generic runner and prints `build.runner_project_failed` with the
compiler errors. See [specs/007-native-runner-code](specs/007-native-runner-code/spec.md).

## App extensions

Share and action extensions are built, embedded under `PlugIns/`, signed with their own provisioning profiles and installed alongside the app, so plugins like [receive_sharing_intent](https://github.com/KasemJaffer/receive_sharing_intent) put your app in the iOS share sheet. No configuration needed.

Sharing data back to the app needs an App Group. Signed in with an Apple ID, xcross registers and attaches it for you. With an App Store Connect API key, Apple's public API cannot manage App Groups at all, so attach one yourself and pass `XCROSS_APP_GROUP`. See **[docs/app-extensions.md](docs/app-extensions.md)**.

## Bundle identity

The bundle id is read from the Flutter iOS project, using the same sources as Flutter's own tooling on non-macOS hosts:

1. A literal `CFBundleIdentifier` in `ios/Runner/Info.plist` (no `$(…)` variables), otherwise
2. the `PRODUCT_BUNDLE_IDENTIFIER` of the **application** target in `ios/Runner.xcodeproj/project.pbxproj`.

Step 2 reads the application target specifically: a project with app extensions declares several `PRODUCT_BUNDLE_IDENTIFIER`s, and the extension's often comes first in the file.

The packed `.app`'s `Info.plist` is always derived from `ios/Runner/Info.plist` when present. `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)` are expanded from the application target's build settings, and embedded extensions inherit those versions, as iOS requires.

### App ID on device

xcross signs the app under its **real App ID** (the project's bundle id) unless told otherwise:

- **Original** (`com.example.app`, the default) is what push, Firebase, Sign in with Apple, passkeys, associated domains and the App Store record are bound to. If another team already owns it, xcross falls back to the prefixed id and warns that those services will not work.
- **Prefixed** (`XCR-<TEAM>.com.example.app`) never collides with another team that owns the same bundle id.

On an app's first device build for your team, `xcross flutter run` and `xcross compose run` on a terminal ask, with the real id as the default answer. `xcross project bundle-id` shows the choice and `xcross project bundle-id original|prefixed` changes it (XCross Studio: Signing → App ID).

The answer is saved to the project so it can be committed: under `xcross:` in `pubspec.yaml` for Flutter, or in `xcross_project.yaml` for projects without a pubspec (Compose). If `xcross_project.yaml` exists, it is used even in a Flutter project.

```yaml
# pubspec.yaml
xcross:
  bundle_id: original # or prefixed
```

The order of precedence is: `XCROSS_BUNDLE_ID=original|prefixed` for a single run, then the saved `bundle_id`, then whichever App ID already exists on the team, and only then the question.

CI, IDE debug sessions and XCross Studio cannot be asked, so they use the saved `bundle_id` from `xcross_project.yaml` or `pubspec.yaml`. When nothing is saved and the team has no App ID yet, they register the real id and save nothing. `xcross install <ipa>` run in the project folder uses the project's saved choice for that project's IPA.

Push needs `aps-environment`: when the app uses `firebase_messaging` or the `remote-notification` background mode and declares no entitlements, xcross adds it (`build.push_entitlement_inferred`). `xcross flutter doctor` shows a "Push notifications" section (entitlement, App ID, and the bundle id in `GoogleService-Info.plist` / `firebase_options.dart`).

<!-- studio: 018 -->
## App Store builds

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
app's **App icon** page previews the icon as iOS masks it. See [specs/023-icon-studio](specs/023-icon-studio/spec.md).

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
`.xcross/icon-backups/`. See [specs/024-icon-splash-studio](specs/024-icon-splash-studio/spec.md). In XCross Studio, the
App icon page and the studio's `All screens` tab show both on every screen size
([specs/026-all-screens-preview](specs/026-all-screens-preview/spec.md)). iOS keeps showing the splash it saved: to see a
new one, restart the iPhone and install again. Deleting the app is not enough.

The build signs the app and its extensions with an Apple Distribution certificate and App Store profiles, and writes
`build/xcross-ios/ipa/<name>.ipa` and `build/xcross-ios/archive/Runner.xcarchive` (with dSYMs when `dsymutil` is on
PATH). The certificate is reused across runs; in CI pass its private key (PEM) in `XCROSS_CERTIFICATE_PRIVATE_KEY`.
Answer the export compliance question once with `uses_non_exempt_encryption: false` (or `true`) under `xcross:` in
`pubspec.yaml`. `xcross release check [--online] [--json]` lists signing, SDK, SwiftSupport, Info.plist, permission,
privacy-manifest, icon and iPad issues with `release.*` codes; `--online` also asks App Store Connect (read-only) whether
the app, build number, version and App ID capabilities are accepted. `xcross publish` resumes an interrupted upload, refuses a build number App Store
Connect already has, and writes `build/xcross-ios/release.json`; `--build-number auto` on the build picks the next
number. See [specs/018-app-store-build](specs/018-app-store-build/spec.md) and
[specs/019-upload-processing](specs/019-upload-processing/spec.md).

## IDE integration

### VS Code

```sh
xcross ide vscode
```

Writes the DAP shim and upserts two xcross launch entries + DAP settings into `.vscode/`: **xcross: iPhone · debug (iOS 17+)** (hot reload) and **xcross: iPhone · release (iOS 15/16)** (`--release`; iOS 15/16 cannot run debug builds). Pick one in the Run and Debug dropdown and press **F5** to build, sign, install, and launch. Flutter's own device picker never lists an iPhone on Windows/Linux; these entries are where it shows up. Hot Reload / Restart buttons drive the same `r`/`R` commands as the CLI, and DevTools attaches to the same VM Service connection.

- Works in VS Code forks with the Dart-Code extension installed.
- The xcross launch config sets `"env": { "XCROSS": "true" }`; other Flutter launch configs in the workspace keep working - sessions without that marker are handed to Flutter's own debug adapter.
- For multiple iPhones, set `"args": ["--udid", "<UDID>"]` on the xcross entry; re-running the command preserves those args.
- Existing `launch.json` / `settings.json` are merged in place (xcross keys upserted, everything else kept). A second run is a no-op when already current.
- Run the *installed* `xcross`; the generated DAP shim records that binary's path.

### JetBrains IDEA / Android Studio

```sh
xcross ide idea
```

Writes `.run/xcross_ios_device.run.xml` (debug, iOS 17+) and `.run/xcross_ios_release.run.xml` (release, iOS 15/16) - shared [LSP4IJ](https://plugins.jetbrains.com/plugin/23257-lsp4ij) Debug Adapter Protocol run configurations that start `xcross flutter dap` over stdio. They appear in the run-configuration dropdown next to the device picker.

- Install the LSP4IJ plugin, then pick **xcross: iPhone · debug (iOS 17+)** or **xcross: iPhone · release (iOS 15/16)** and press Debug (don't use Flutter's Run button - it still calls `flutter run`).
- Breakpoints and stepping use the DAP/VM Service path; Restart maps to hot restart. Console `r`/`R` still work.
- Re-running updates the files xcross wrote (for example after moving xcross; the old version is kept as `.bak`). A run configuration you wrote yourself is never overwritten; it is printed for you to merge.

## FAQ

<details>
<summary><b>How does it build release/AOT?</b></summary>

Flutter publishes its iOS AOT compiler (`gen_snapshot`) for macOS only. On macOS xcross uses that compiler. On Linux and Windows it downloads a build of the same compiler, made from the Dart revision the Flutter release pins: first from [xcross-compilers](https://github.com/Abdelrahman1atef/xcross-compilers), then from [xcross_gen_snapshot](https://github.com/arxdeus/xcross_gen_snapshot), and for a patch release without one, the compiler of its line built from the same Dart revision ([details](#flutter-versions-and-ios-compilers)). Each published compiler produced output byte-identical to Flutter's own on a real `flutter build ios` before it was released. xcross checks the engine revision and both digests before it uses a download. To use a compiler of your own, set `ios_gen_snapshot` in the xcross config. Simulators stay debug-only, because Flutter's simulator engines are JIT-only.

A downloaded compiler is cached per engine revision. Once a day a build checks the release again (a few seconds at most, and never failing offline), so a compiler republished for the same Flutter version replaces the cached one. `xcross flutter doctor` reports for profile and release whether a compiler is shipped, cached, pinned, published, or missing. `xcross flutter precache` fetches it ahead of time. `xcross cache prune` removes engine artifacts and compilers left behind by Flutter versions you no longer use; Kotlin/Native in `~/.konan` is shared with Gradle and never pruned. A release manifest written for a newer xcross asks you to run `xcross update`.

On Windows, output byte-identical to a macOS build needs an LF checkout of the Flutter SDK (`git config --global core.autocrlf false` before cloning). A CRLF checkout still produces working snapshots, but not byte-identical ones, because the source offsets they record shift.
</details>

<details>
<summary><b>What does <code>xcross tunnel</code> do, and why does it need elevation?</b></summary>

It mounts the Developer Disk Image and starts the `pymobiledevice3` RSD tunnel - the encrypted QUIC/TUN tunnel iOS 17+ requires for developer services. Creating the TUN interface needs an Administrator PowerShell on Windows or root on Linux. Run it once per device reconnect.
</details>

<details>
<summary><b>How does <code>--wifi</code> (wireless run) work?</b></summary>

Wireless devices are discovered and reached through `pymobiledevice3 remote tunneld`, which finds the phone over mDNS (RemotePairing) and builds the RSD tunnel - usbmuxd is not involved, since the open-source usbmuxd on Linux and Windows never sees network devices. Requirements: iOS 17+, Developer Mode enabled, a one-time pairing with the host, and the phone unlocked on the same subnet (mDNS/UDP 5353 does not cross NAT - use bridged networking in a VM). `xcross tunnel --wifi` does the whole wireless setup with no cable: it advertises this host for device-initiated pairing (iOS 27+; the phone lists it as `xcross-<hostname>` under Settings > Privacy and Security > Developer Mode > Paired Devices > Other Devices and the 6-digit code prints in the terminal), builds the tunnel, and mounts the DDI through it. `xcross flutter run --wifi` also sets pairing up itself when needed (over the cable when USB is attached, via the same advertisement when not) and starts tunneld on demand; the tunnel needs root/Administrator for the TUN interface.
</details>

<details>
<summary><b>Does it support Compose Multiplatform?</b></summary>

Yes. Use `xcross compose setup`, then `xcross compose build` or `xcross compose run -d <device>` from a KMP project. Windows x64 and Linux x64 are supported; Linux arm64 is blocked by upstream Kotlin/Native host artifacts.
</details>

<details>
<summary><b>Is my Apple password stored anywhere?</b></summary>

No. `xcross auth` performs the login handshake locally and persists only the resulting Developer Services session token.
</details>

<details>
<summary><b>Why does an App Store Connect API key have fewer capabilities than an Apple ID?</b></summary>

Only for App Groups, and the cause is Apple's. The public App Store Connect API has no App Groups resource at all: its OpenAPI specification declares 966 paths and none of them mentions one, so a key cannot create a group or attach it to an App ID. The older protocol Xcode itself speaks does expose them, and that is what an Apple ID session uses.

So the documented, officially supported credential is the less capable one here, and the undocumented path is the complete one, with the stability caveat that implies.

It only matters if your app ships a share or action extension. A key still issues profiles that carry a group attached by other means, so attach one once in Xcode or at developer.apple.com and pass `XCROSS_APP_GROUP=group.your.id`. Everything else works identically. See [docs/app-extensions.md](docs/app-extensions.md).
</details>

<details>
<summary><b>Builds fail with "this SDK is not supported by the compiler"</b></summary>

`xcross sdk install` patches the Darwin SDK against the Swift toolchain that was selected at the time, and the SDK's Swift module interfaces can only be compiled by that toolchain. Changing the active Swift afterwards (`swiftly use`, `mise use`, or a distro upgrade) invalidates the pairing, and Swift then reports the mismatch once per importing source file:

```
error: failed to build module 'UIKit'; this SDK is not supported by the compiler
(the SDK is built with 'Apple Swift version 6.3.2 …', while this compiler is
'Swift version 6.3.2 (swift-6.3.2-RELEASE)'). Please select a toolchain which
matches the SDK.
```

xcross records the toolchain each SDK was installed with and stops the build with this explanation before Swift gets there. Either select the Swift toolchain the SDK was installed with, or reinstall the SDK against the current one:

```sh
xcross sdk install ~/Downloads/Xcode.xip
```

Note that the two versions in Swift's own message can look identical: the mismatch is between compiler *builds* (an Apple/vendor build vs a swift.org release), not just version numbers.
</details>

---

## Under the hood

xcross does not wrap or patch `flutter build ios` - that command simply refuses to run off-macOS. Instead, it re-implements the parts of Flutter's toolchain that matter for a device build (debug JIT, profile and release AOT), using the same engine artifacts, the same compilers, and the same device protocols the official tooling uses.

```text
xcross flutter run / build
   ├─ FlutterPacker
   │    ├─ IosEngineCache        download engine artifacts pinned to the SDK's engine hash
   │    ├─ FlutterDebugBundler   frontend_server → app.dill → App.framework (JIT, debug)
   │    ├─ FlutterAotSnapshotter AOT app.dill → gen_snapshot → App.framework/App + dSYM (profile/release)
   │    │    └─ IosGenSnapshotResolver  Flutter's gen_snapshot on macOS, xcross-compilers / xcross_gen_snapshot elsewhere
   │    ├─ Native assets         Dart build hooks → arm64 frameworks + manifest
   │    ├─ SwiftPM plugins       swift build (Darwin SDK) → libFlutterPluginsGenerated.dylib
   │    ├─ RunnerShim            clang / ld64.lld → Runner Mach-O
   │    └─ assemble              Flutter.framework + Info.plist + flutter_assets → .app
   ├─ in-process codesign → install
   └─ CoreDeviceLauncher    RSD tunnel → launch suspended → gdb-remote attach
        └─ HotReloadController   DevFS + VM Service ⇄ frontend_server
```

### 1. Engine artifacts, straight from Flutter's CDN

`IosEngineCache` reads the engine revision from your Flutter SDK (the same hash `flutter` itself pins) and downloads exactly what Flutter's tool would cache: the prebuilt **`Flutter.xcframework`**, the debug **`vm_snapshot_data`** / **`isolate_snapshot_data`** JIT snapshots, the host **`frontend_server`**, and the Flutter **patched Dart SDK**. Your app therefore runs on the *identical* engine binary an Xcode build would embed - xcross never rebuilds or modifies the engine.

### 2. Kernel compilation with `frontend_server`

In debug mode Flutter apps are not compiled to machine code - the Dart VM runs **kernel bytecode** (JIT). `FlutterDebugBundler` drives the same `frontend_server` the Flutter tool uses (against the patched SDK, with your `--dart-define`s and flavor entrypoint) to produce `app.dill`, then lays out `App.framework` exactly like Flutter does:

- `flutter_assets/kernel_blob.bin` - the kernel program
- `flutter_assets/vm_snapshot_data`, `isolate_snapshot_data` - VM heap seeds
- `AssetManifest.bin/json`, `FontManifest.json`, fonts and assets - generated in Dart from your `pubspec.yaml`, replicating Flutter's asset bundling
- The `App.framework` *binary* in a debug build is only a stub - xcross compiles that stub with `clang` targeting `arm64-apple-ios` and writes the framework's `Info.plist` itself.

Because a debug app is pure JIT, no `gen_snapshot` is needed. Profile and release builds instead compile a whole-program AOT kernel and `FlutterAotSnapshotter` lets `gen_snapshot` write `App.framework/App` directly, then extracts its dSYM and strips it, as `flutter build ios` does. `IosGenSnapshotResolver` picks the compiler: the one in your Flutter SDK on macOS, and on Linux and Windows a verified download from the [xcross-compilers](https://github.com/Abdelrahman1atef/xcross-compilers) or [xcross_gen_snapshot](https://github.com/arxdeus/xcross_gen_snapshot) releases (see [Flutter versions and iOS compilers](#flutter-versions-and-ios-compilers)).

### 3. Native code without Xcode

- **Darwin SDK** - `darwin_sdk_kit` unpacks `Xcode.xip` with pure-Dart **xar**, **pbzx**, and **cpio** readers and assembles a Swift SDK bundle (iOS sysroot + frameworks) usable by upstream Swift/LLVM on Windows and Linux.
- **Runner** - the `Runner` executable (Flutter's `AppDelegate`/`main` shim) is compiled with `clang` and linked with `ld64.lld`, LLVM's Mach-O linker, against `Flutter.xcframework` from the SDK above.
- **Native assets** - Dart package build hooks run through Flutter's native-assets target with cross-platform Apple tool shims. Their output is thinned to arm64, embedded as frameworks, and recorded in `NativeAssetsManifest.json`.
- **Plugins** - SwiftPM iOS plugins are built with `swift build` against the same SDK into a single `libFlutterPluginsGenerated.dylib`, with a generated registrant mirroring Flutter's `GeneratedPluginRegistrant`. A Mach-O rewriter fixes install names and rpaths so the dylibs resolve inside the `.app` bundle.
- <!-- studio: 004 --> **Asset catalogs** - `Assets.xcassets` is compiled to `Assets.car` in pure Dart (a port of [AssetKit](https://github.com/xtool-org/AssetKit)): image sets, colour sets and the app icon, plus the loose icon PNGs SpringBoard falls back to. A `LaunchScreen.storyboard` with a colour and one image view is compiled by xcross itself into `LaunchScreen.storyboardc`, with the logo shipped as loose PNGs; a storyboard with more in it becomes a `UILaunchScreen` (its background colour and centred image), and the rest is reported as `build.launch_screen_approximated` (`XCROSS_LAUNCH_STORYBOARD=off` forces the `UILaunchScreen`). iOS caches launch screens: delete the app and reboot to see a changed one.

### 4. Signing and device install, natively

`apple_developer_kit` implements Apple's **GrandSlam** login (with ADI machine attestation via the Android libraries), Developer Services provisioning (certificates, device registration, provisioning profiles), and **in-process Mach-O code signing** - no `codesign`, no `ldid`. Installation goes over the standard device protocols via `pymobiledevice3`.

### 5. iOS 17+ CoreDevice launch

iOS 17 replaced the old debug-launch path with **CoreDevice** over an encrypted **RSD tunnel**. `xcross tunnel` mounts the Developer Disk Image and brings the tunnel up; `CoreDeviceLauncher` then launches the app **suspended**, attaches a minimal **gdb-remote** client (the same protocol `debugserver` speaks) to resume and supervise the process, and port-forwards the **Dart VM Service** from the phone to localhost.

### 6. Hot reload: a faithful DevFS reimplementation

Hot reload is pure Flutter-internals territory, reimplemented protocol-for-protocol:

1. A long-lived `frontend_server` session (from `frontend_server_kit`) holds incremental compile state; a file watcher tracks your `lib/`.
2. On `r`, changed files are recompiled to an **incremental dill**, which is gzip-uploaded to the device via the VM Service's HTTP **DevFS** endpoint (`_createDevFS` + `PUT` - the same `org-dartlang-devfs://` filesystem Flutter's tool uses).
3. xcross calls `reloadSources` on the root isolate, then triggers `ext.flutter.reassemble` so the widget tree rebuilds.
4. `R` (hot restart) resets the compiler, uploads a full dill, and re-runs the app in each `FlutterView` via `_flutter.listViews` / run-in-view - matching Flutter's hot restart semantics.
5. The `frontend_server` is also registered as the VM Service's **expression compiler**, so debugger watch/evaluate works on-device.

### 7. IDE debugging via DAP

`xcross_dap` implements a **Debug Adapter Protocol** server that routes launch/attach, breakpoints, stepping, and hot-reload requests to the same VM Service connection. VS Code reaches it through a shim that intercepts launch configs marked with `"env": { "XCROSS": "true" }` (everything else falls through to Flutter's own adapter); JetBrains IDEs reach it through an LSP4IJ DAP run configuration.

## Credits

This edition is built on [**arxdeus/xcross**](https://github.com/arxdeus/xcross) by Artemis Kushner, which created the engine: the build pipeline, signing, CoreDevice launch and hot reload described above. The upstream project's iOS compilers come from [xcross_gen_snapshot](https://github.com/arxdeus/xcross_gen_snapshot); this edition's are built by [xcross-compilers](https://github.com/Abdelrahman1atef/xcross-compilers) from the [Dart SDK](https://github.com/dart-lang/sdk) sources.

The upstream author thanks the maintainers of these repositories, from which a lot was taken and adapted:

- [xtool](https://github.com/xtool-org/xtool) - cross-platform Xcode replacement that pioneered building and deploying iOS apps with SwiftPM from Linux and Windows.
- [Provision](https://github.com/Dadoum/Provision) - reverse-engineered Apple ADI machine attestation and anisette provisioning; the foundation of xcross's Apple ID authentication approach.
- [anisette-v3-server](https://github.com/Dadoum/anisette-v3-server) - anisette data server powering Apple ID logins without Apple hardware.

## Support

xcross is free and open source. If it saves you a Mac, consider giving back:

- **Contribute** - pull requests are welcome, from typo fixes to new features.
- **Report** - found a bug in this edition or missing a feature? [Open an issue here](https://github.com/Abdelrahman1atef/xcross-studio/issues). For the upstream engine, see [arxdeus/xcross issues](https://github.com/arxdeus/xcross/issues).
- **Donate** - support ongoing development:
  - this edition and its iOS compiler builds: [Sociabuzz](https://sociabuzz.com/man_atef/tribe)
  - the original xcross author:

    [![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/E1E0I3G2D)

## License

[AGPL-3.0](LICENSE)

Copyright (C) 2026 Artemis Kushner
