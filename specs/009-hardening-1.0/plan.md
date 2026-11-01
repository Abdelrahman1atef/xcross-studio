# Implementation Plan: Hardening for 1.0 (packaging + triage)

**Branch**: `009-hardening` | **Date**: 2026-11-01 | **Spec**: [spec.md](spec.md)

## Summary

The release packages are built by one Dart script, `apps/studio/tool/package.dart`, on the host OS.
- It builds the CLI bundle with upstream's `tool/build_xcross.dart` and the GUI with `flutter build`, then lays both
  out as `dist/xcross-studio-<os>-x64/`.
- On Windows, Inno Setup turns that folder into the installer.
- On Linux, `dpkg-deb` makes the `.deb`. `appimagetool` makes the AppImage when `APPIMAGETOOL` points at it; CI
  downloads a pinned, checksum-verified copy.
- No new Dart dependencies.

## Constitution Check

| Principle | Status | Note |
|---|---|---|
| I | ✅ | all files under `apps/studio` and the fork's own workflow; no upstream file touched |
| II | ✅ | packages contain no Apple software; NOTICE says so |
| V | ✅ | Windows and Linux packages from the same script; both built in CI |
| VI | ✅ | CI checks package contents and runs the packaged CLI; device rows deferred for Linux |
| VIII | ✅ | AGPL LICENSE and NOTICE in every package; downloaded build tools pinned by SHA-256 |

## AC → evidence

| AC | Evidence |
|---|---|
| AC-009-1 | CI Windows job: setup.exe + zip uploaded; local zip run (008 device-check) |
| AC-009-2 | CI Linux job: `dpkg-deb --info/--contents`; AppImage extract |
| AC-009-3 | CI: packaged CLI `--help`; GUI test `FR-001 a bundled xcross next to the GUI is found` |
| AC-009-4 | `studio-gui.yml` |
| AC-009-5 | `tool/package.dart` writes LICENSE + NOTICE.txt |
