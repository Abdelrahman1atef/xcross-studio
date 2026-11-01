# Feature Specification: Hardening for 1.0 (packaging + upstream issue triage)

**Feature Branch**: `009-hardening` | **Created**: 2026-11-01 | **Status**: Packaging implemented; triage recorded

**Input**: ROADMAP 009: "One sub-spec per unfixed issue: #90, #75, #55, #21 (documented out of scope); close
#145–#149; installers (Inno Setup, AppImage, .deb)".

## User Story 1 - Install XCross Studio like any desktop app (P1)

A Flutter developer downloads one file for their OS, installs it and starts XCross Studio. The bundled `xcross` CLI
is found automatically.

**Acceptance Scenarios**:

1. **AC-009-1**: Windows: `dist/xcross-studio-windows-x64-setup.exe` (Inno Setup) installs per user without admin
   rights, adds a Start menu entry (desktop icon optional) and an uninstaller. The portable
   `xcross-studio-windows-x64.zip` works unzipped.
2. **AC-009-2**: Linux: `xcross-studio_<version>_amd64.deb` installs the app under `/opt/xcross-studio`, a
   `xcross-studio` launcher in `/usr/bin`, the desktop entry and icon, and depends on GTK 3 and `usbmuxd`.
   `xcross-studio-x86_64.AppImage` runs without installation. The portable `.tar.gz` works unpacked.
3. **AC-009-3**: In every package, the GUI finds `xcross/bin/xcross[.exe]` next to itself, and the packaged CLI runs
   (`--help` lists the XCross Studio commands).
4. **AC-009-4**: CI builds every package on each push (Studio GUI workflow). Downloaded tools are pinned by version
   and SHA-256 (appimagetool 1.9.1).
5. **AC-009-5**: The packages carry `LICENSE` (AGPL-3.0) and `NOTICE.txt` (not affiliated with Apple, no Apple
   software included, pymobiledevice3 installed separately).

6. **AC-009-6**: Tool lookup (`which`) finds Windows app execution aliases. `winget.exe` in
   `%LOCALAPPDATA%\Microsoft\WindowsApps` is a reparse point that Dart sees as a link it can't follow, so
   `xcross setup` used to say "winget is not installed on this host" on Windows 11. Only links directly in a
   `WindowsApps` folder count, and the `python`/`python3` Store redirect stubs are skipped. Found on the dev PC on
   2026-11-01; upstream candidate.

## Upstream issue triage

| Issue | State upstream | Fork status |
|---|---|---|
| #21 React Native support | open (idea) | out of scope for 1.0 (Flutter + Compose only) |
| #55 Nix flake | open | out of scope for 1.0; the portable `.tar.gz` is a starting point for a flake |
| #75 Xcode 27 `ld64` discussion | closed | no action; the doctor/PATH guard (002) covers the toolchain checks |
| #90 Building native assets | closed | fixed upstream; 002's PATH guard adds the `toolchain.path_linker_unusable` warning |
| #145 podspec-only plugins skipped silently | closed | 002 warns (`build.podspec_only_plugin`); 006 adds `xcross_overrides/` |
| #146 unsigned IPA, no sign/install command | open | 005 `xcross install`; 011 `xcross sign` (in progress) |
| #147 iOS 16 support, fail fast | open | 002 fail fast; 005 iOS 15/16 install + launch |
| #148 native assets on WSL2 | closed | 002 PATH guard |
| #149 icon, launch screen, entitlements | open | 003 entitlements; 004 icon + launch screen |

The open upstream issues can be closed with links to the fork's PRs once the device checks pass (see
`DEVICE-TEST-RUNBOOK.md`).

## Out of scope (later)

Code-signing the Windows installer (SignPath Foundation application needed), auto-update for the GUI, ARM64
packages, Flatpak (its sandbox blocks USB and subprocess tools), and a lawyer review of the legal checklist before 1.0
(PLAN).
