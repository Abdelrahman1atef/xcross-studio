# Implementation Plan: Icon and splash studio

**Branch**: `008-json-events-gui` | **Date**: 2026-11-04 | **Spec**: [spec.md](spec.md)

## Summary

One design makes every app icon and native splash a Flutter project needs. A pure-Dart compositor in `studio_ext`
draws the design at any size; target tables list each platform's files; `xcross icons generate` and a new `xcross
splash` write them. The App icon page drives both and previews through a long-lived `xcross icons preview --serve`
process, so what is shown is what the CLI draws.

## Technical Context

**Language**: Dart 3.13 (Flutter 3.47.0 for the desktop app). **Dependencies**: already present (`archive`, `xml`,
`file_selector`); none added. **Storage**: project files, `xcross_assets.json`. **Testing**: `dart test`, `flutter
test`, file-size and structure checks, and looking at the generated images. **Platforms**: Windows and Linux hosts.
**Performance**: preview under 0.5 s per change (SC-004). **Constraints**: no font engine in the CLI; no Apple
material; `HostFileSystemInterface` for files; `@internal` in `lib/src`.

## Constitution Check

| Principle | How it is met |
|---|---|
| I Minimal diff | New files in `studio_ext` and `apps/studio`; one registration line in the runner |
| II No Apple material | No Apple artwork; shapes are drawn; nothing downloaded |
| III Fail fast | Coded errors and warnings (`icons.*`, `splash.*`) with hints; usage errors before any work |
| IV CLI is the product | Composition and writing in the CLI; the page starts commands and shows their output |
| V Windows and Linux | Pure Dart; no OS branching |

## Design decisions (research)

- **Live preview**: starting a process per change costs too much (CLI start plus the environment read). `icons preview
  --serve` stays running, reads one JSON design per line on stdin, caches decoded sources, draws at 512 px and writes
  a temp PNG, printing its path. Rejected: re-implementing composition in Flutter (it would drift from the output).
- **Text, clipart and badge**: the desktop app renders them to transparent PNGs with Flutter's own text engine, and
  the CLI treats them as images. Clipart is a curated list of Material symbols shipped with Flutter.
- **Composition order**: background, texture, shadow, logo, badge. A canvas has a logo box (a centred square of the
  short side, shrunk to a viewport for adaptive and maskable icons); padding is relative to that box, so banners and
  safe zones reuse one code path.
- **Sizes**: squares are drawn once at the largest size and reduced; banners and adaptive layers at their own size.
- **iOS splash**: the same three files Flutter's template and `flutter_native_splash` use (`LaunchImage`,
  `LaunchBackground`, storyboard), which `LaunchStoryboard.parse` already turns into `UILaunchScreen`. Padding, margin
  and branding are baked into the image. The compiler already handles colour sets and dark image variants.
- **Android splash**: `launch_background.xml` (drawable, drawable-v21, and night) and new `values-v31` and
  `values-night-v31` styles. Existing `values/styles.xml` files are not rewritten; a project whose `LaunchTheme` does
  not use `launch_background` gets `splash.not_referenced`.
- **Backups**: every replaced file is copied under `.xcross/icon-backups/<stamp>/` with its project-relative path.
- **Determinism**: no timestamps in PNGs or zip entries.

## Project Structure

```text
packages/studio_ext/lib/src/shared/icons/
  icon_design.dart      design model, parsing, config file
  icon_composer.dart    trim, fit, tint, effects, background, texture, badge
  icon_textures.dart    the eleven drawn textures
  icon_targets.dart     file tables per target, Contents.json, adaptive XML, manifest
packages/studio_ext/lib/src/shared/splash/
  splash_design.dart, splash_files.dart, splash_check.dart
packages/studio_ext/lib/shared/icons/icons_command.dart   (options, preview --serve)
packages/studio_ext/lib/shared/splash/splash_command.dart
apps/studio/lib/features/icons/
  studio_panel.dart, splash_panel.dart, target_previews.dart, clipart_set.dart, source_render.dart
```

## Complexity Tracking

None: no new dependencies or projects.
