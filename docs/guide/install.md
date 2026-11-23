# Installation and updates

[← xcross README](../../README.md) · [All guides](README.md)

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

   This runs the setup script for your package manager, which is built into the xcross you installed (nothing is downloaded to get it): [`winget.ps1`](../../setup/winget.ps1), [`scoop.ps1`](../../setup/scoop.ps1), or [`choco.ps1`](../../setup/choco.ps1). If several are installed, xcross asks which one to use. If none is, it runs [`direct.ps1`](../../setup/direct.ps1), which downloads the vendor installers itself. Pick one explicitly with `xcross setup --manager winget|scoop|choco|direct`. xcross first prints the script's name, source, and SHA-256 and waits for `y`. The script then asks before each package: Visual Studio Build Tools (MSVC + Windows SDK, which Swift links against), Swift, LLVM (its `bin` goes on your `PATH`), and Python 3. Then it installs `pymobiledevice3`. Installers that need elevation raise their own UAC prompt. `xcross setup --yes` accepts every prompt, and `xcross setup --only llvm,python` (any of `vs`, `swift`, `llvm`, `python`, `pymobiledevice3`) installs just those.

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

   Prefer a script you can read first? [`setup/apt.sh`](../../setup/apt.sh), [`setup/dnf.sh`](../../setup/dnf.sh), and [`setup/pacman.sh`](../../setup/pacman.sh) install the same packages, plus Swift through swiftly if it is missing. Run one directly (`sh setup/apt.sh`) or point `setup:` in your config at it (see [Configuration](configuration.md#configuration)). Before any third-party installer (apt.llvm.org's `llvm.sh`, swiftly) runs, they print its name and URL and wait for `y`.

### Verifying a release

Every release archive is built by [`release.yml`](../../.github/workflows/release.yml) and signed with a [SLSA build provenance attestation](https://docs.github.com/actions/security-for-github-actions/using-artifact-attestations) that binds the archive's digest to the commit it was built from. The release job refuses to publish an artifact whose provenance does not match, so a bundle produced outside this repository can never reach the release page.

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
