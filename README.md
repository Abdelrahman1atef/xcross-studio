<div align="center">

# xcross

### Build, run, hot-reload and ship Flutter iOS apps from Windows or Linux

**No Mac · No Xcode · No WSL**

[![Latest release](https://img.shields.io/github/v/release/Abdelrahman1atef/xcross-studio?style=flat-square&label=release&color=2ea44f)](https://github.com/Abdelrahman1atef/xcross-studio/releases)
[![Unit Tests](https://img.shields.io/github/actions/workflow/status/Abdelrahman1atef/xcross-studio/unit-tests.yml?branch=main&style=flat-square&label=tests)](https://github.com/Abdelrahman1atef/xcross-studio/actions/workflows/unit-tests.yml)
[![iOS compilers](https://img.shields.io/github/v/release/Abdelrahman1atef/xcross-compilers?sort=semver&style=flat-square&label=newest%20iOS%20compiler&color=0a84ff)](https://github.com/Abdelrahman1atef/xcross-compilers/releases)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-3C873A?style=flat-square)
[![License: AGPL v3](https://img.shields.io/badge/license-AGPL--3.0-blue?style=flat-square)](LICENSE)

[**Quick start**](#quick-start) · [**Flutter versions**](#flutter-versions) · [**Commands**](#commands) · [**Guides**](docs/guide/README.md) · [**FAQ**](docs/guide/faq.md) · [**Changelog**](CHANGELOG.md)

</div>

<br>

> [!NOTE]
> This is the **XCross Studio edition** of [arxdeus/xcross](https://github.com/arxdeus/xcross): the same engine, with [these additions](#what-this-edition-adds). The XCross Studio desktop app drives it, and the command line works on its own.

## Highlights

<table>
<tr>
<td width="50%" valign="top">

**🖥️ Native on Windows and Linux**<br>
Official Swift and LLVM toolchains on your own machine. No VM, no WSL, no macOS anywhere.

</td>
<td width="50%" valign="top">

**🔥 Hot reload on a real iPhone**<br>
`r` and `R` on an iPhone over USB or Wi-Fi, with the iOS 17+ CoreDevice tunnel.

</td>
</tr>
<tr>
<td valign="top">

**📦 Release builds for every Flutter version**<br>
iOS compilers for Windows and Linux, checked byte for byte against Flutter's own. [More](#flutter-versions)

</td>
<td valign="top">

**🧩 Plugins without CocoaPods**<br>
Swift packages, CocoaPods pods converted to Swift packages, and podspec-only plugins drafted for you. [More](docs/guide/plugins.md)

</td>
</tr>
<tr>
<td valign="top">

**🚀 App Store from your PC**<br>
Preflight checks, signed IPA, upload, TestFlight, store listing, icons and splash screens. [More](docs/guide/app-store.md)

</td>
<td valign="top">

**🔐 Signing and debugging built in**<br>
Apple ID (a free one works) or App Store Connect key, signed in-process. VS Code and JetBrains debugging. [More](docs/guide/authentication.md)

</td>
</tr>
</table>

## Quick start

**1. Install xcross**

```powershell
# Windows (PowerShell)
irm https://raw.githubusercontent.com/Abdelrahman1atef/xcross-studio/main/install.ps1 | iex
```

```sh
# Linux (install Swift first, for example with swiftly)
curl -fsSL https://raw.githubusercontent.com/Abdelrahman1atef/xcross-studio/main/install.sh | sh
```

**2. Set up once, then run your app**

```sh
xcross setup                                # Swift, LLVM, Python + pymobiledevice3 (Windows: also VS Build Tools)
xcross sdk install ~/Downloads/Xcode.xip    # once: builds a private iOS SDK from Apple's Xcode archive
xcross auth --apple-id you@example.com      # or an App Store Connect API key

cd my_flutter_app
xcross flutter doctor                       # read-only check of everything above
xcross tunnel                               # once per device reconnect (Administrator / root)
xcross flutter run                          # build → sign → install → launch → hot reload
```

| Key | While the app runs |
|:---:|---|
| `r` | Hot reload |
| `R` | Hot restart |
| `q` | Quit |

> [!WARNING]
> Sign in with a **secondary Apple ID**, not your main one: Apple may lock an account used from a non-Apple system. A free account is enough. [Why](docs/guide/authentication.md)

More: [installation and updates](docs/guide/install.md) · [Wi-Fi](docs/guide/wifi.md) · [App Store builds](docs/guide/app-store.md) · [IDE debugging](docs/guide/ide.md)

## Requirements

| You need | For |
|---|---|
| [Flutter](https://flutter.dev) | Your app; xcross uses its engine artifacts |
| [Swift](https://www.swift.org/install/) 6.4+ | Plugins and native code (`xcross setup` installs it on Windows) |
| [LLVM](https://releases.llvm.org/) with `ld64.lld` | Compiling and linking iOS binaries |
| Python 3 + [pymobiledevice3](https://github.com/doronz88/pymobiledevice3) | Talking to the iPhone |
| An `Xcode.xip` from [xcodereleases.com](https://xcodereleases.com/) | Read once into a private iOS SDK; Xcode never runs |
| An iPhone with **iOS 17+** | Running and debugging (`xcross install` also covers iOS 15 and 16) |

## Flutter versions

| Build | Works with |
|---|---|
| **Debug** (`flutter run`, hot reload) | Any Flutter version |
| **Profile / release** (`--profile`, `--release`, App Store) | Every Flutter version with an iOS compiler for your machine |

Flutter ships its iOS compiler for macOS only, so xcross downloads a Windows or Linux build of it, in this order:

1. [**xcross-compilers**](https://github.com/Abdelrahman1atef/xcross-compilers/releases): every Flutter stable release, built from the Dart sources and published only when its output is byte-identical to Flutter's own compiler.
2. [**xcross_gen_snapshot**](https://github.com/arxdeus/xcross_gen_snapshot/releases): the upstream project's compilers.
3. **Same Dart revision**: a patch release without its own compiler uses its line's compiler built from the same Dart.

```sh
xcross flutter sdk list   # does my Flutter have a compiler?
xcross flutter sdk auto   # no: use the nearest Flutter that has one, for iOS builds only
```

**Which versions have a compiler today:** Flutter 3.44.0 to 3.47.9, with 3.50 and the rest of the 3.x releases (back to 3.0) being added, newest first. Every new Flutter stable release is built within hours. The live list is the [xcross-compilers releases](https://github.com/Abdelrahman1atef/xcross-compilers/releases) plus [xcross_gen_snapshot](https://github.com/arxdeus/xcross_gen_snapshot/releases); `xcross flutter sdk list` prints it for your machine, and the XCross Studio app shows it under Setup › Flutter for iOS builds.

Details: [Flutter versions and iOS compilers](docs/guide/flutter-versions.md)

## What this edition adds

On top of [arxdeus/xcross](https://github.com/arxdeus/xcross); the [changelog](CHANGELOG.md) has each change.

| | |
|---|---|
| **iOS compilers for every Flutter release** | Built and verified in [xcross-compilers](https://github.com/Abdelrahman1atef/xcross-compilers); same-Dart reuse for patch releases |
| **Flutter SDKs for iOS builds** | `xcross flutter sdk` installs a Flutter that has a compiler, without touching yours; clear errors and retries on download |
| **CocoaPods without CocoaPods** | Pods converted to Swift packages: binary, Objective-C, Swift and mixed, with lock files ([plugins](docs/guide/plugins.md)) |
| **Podspec-only plugins** | Drafted `Package.swift` overrides; vendors' Swift packages known for many pods (Google Maps, Firebase, OneSignal, RevenueCat…) |
| **App Store pipeline** | `release preflight` before compiling, `release check`, `publish`, `testflight`, `appstore metadata`, `privacy init` ([App Store](docs/guide/app-store.md)) |
| **Icons and splash screens** | Every size for iOS, Android, web and macOS from one image |
| **Like Xcode** | Compiled launch storyboards, capabilities and entitlements, permission prompts that really ask |
| **Device tools** | `logs`, `crashes`, `app info`, `inspect`, `sign` and `install` any `.ipa` |
| **Built for apps** | JSON events (`XCROSS_EVENTS=ndjson`) with stable diagnostic codes ([GUI](docs/guide/gui.md)) |

## Commands

| Area | Commands |
|---|---|
| **Set up** | `setup` · `sdk install` · `config` · `update` · `doctor` |
| **Sign in** | `auth` · `auth status` · `auth clean` |
| **Devices** | `tunnel [--wifi]` · `devices` · `logs` · `crashes` · `app info` · `app list` |
| **Build and run** | `flutter run` · `flutter build --release / --profile [--ipa]` · `flutter doctor` · `flutter sdk` · `flutter clean` |
| **Plugins** | `plugin list / check / status / shim` · `pods report` · `ios prepare` |
| **App Store** | `release preflight / check / gate` · `publish` · `testflight` · `appstore metadata` · `privacy init` · `project version` · `icons` · `splash` |
| **Any app** | `sign` · `install` · `inspect` |
| **IDE** | `ide vscode` · `ide idea` · `flutter dap` |
| **Compose** | `compose setup / doctor / build / run` |

Every command and option: [command reference](docs/guide/commands.md)

## Guides

| | | |
|---|---|---|
| [Installation and updates](docs/guide/install.md) | [Signing in to Apple](docs/guide/authentication.md) | [Run over Wi-Fi](docs/guide/wifi.md) |
| [Flutter versions and compilers](docs/guide/flutter-versions.md) | [Flutter plugins](docs/guide/plugins.md) | [Your iOS project](docs/guide/ios-project.md) |
| [App Store, icons, splash](docs/guide/app-store.md) | [IDE integration](docs/guide/ide.md) | [Configuration](docs/guide/configuration.md) |
| [Compose Multiplatform](docs/guide/compose.md) | [Using xcross from a GUI](docs/guide/gui.md) | [Command reference](docs/guide/commands.md) |
| [FAQ](docs/guide/faq.md) | [Under the hood](docs/guide/under-the-hood.md) | [App extensions](docs/app-extensions.md) |

## Credits

Built on [**arxdeus/xcross**](https://github.com/arxdeus/xcross) by Artemis Kushner, who created the engine: the build pipeline, signing, CoreDevice launch and hot reload. iOS compilers come from [xcross-compilers](https://github.com/Abdelrahman1atef/xcross-compilers) (built from the [Dart SDK](https://github.com/dart-lang/sdk)) and [xcross_gen_snapshot](https://github.com/arxdeus/xcross_gen_snapshot).

The upstream project also thanks [xtool](https://github.com/xtool-org/xtool), [Provision](https://github.com/Dadoum/Provision) and [anisette-v3-server](https://github.com/Dadoum/anisette-v3-server), from which a lot was taken and adapted.

## Support

- 🐛 **Report** a bug or missing feature: [issues](https://github.com/Abdelrahman1atef/xcross-studio/issues) (upstream engine: [arxdeus/xcross](https://github.com/arxdeus/xcross/issues))
- 🛠️ **Contribute**: pull requests are welcome
- ❤️ **Donate**: this edition and its compiler builds on [Sociabuzz](https://sociabuzz.com/man_atef/tribe) · the original author on [ko-fi](https://ko-fi.com/E1E0I3G2D)

## License

[AGPL-3.0](LICENSE)

Copyright (C) 2026 Artemis Kushner
