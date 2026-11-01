# Implementation Plan: XCross Studio design system

**Branch**: `013-gui-design-system` | **Date**: 2026-11-01 | **Spec**: [spec.md](spec.md)

## Summary

`apps/studio` is rebuilt on the doc's design system without changing the CLI or state layers (`lib/src/cli`,
`lib/src/state`):

- `lib/design_system/`
  - `tokens/`: colours, typography, spacing, radii, motion
  - `theme/x_theme.dart`: `ThemeData` from the tokens, plus an `XTheme` extension carrying them
  - `components/`: §8 inventory
  - `layouts/`: `XAppShell`, `XConsoleDock`, `WorkspaceLayout`
- `lib/app/`: `StudioApp`, `StudioServices` + `Services`, `AppController` (destination, console job), the shell
  (top bar, sidebar, dock, status bar, shortcuts) and the quick-command palette.
- `lib/features/<area>/`: the screens.
  - Overview, Build & Run, Devices, Signing, Logs & Debug, Plugins, Settings
  - the onboarding wizard
  - shared adapters in `features/common/`: Job → console lines, steps and diagnostics; doctor checklist; app info
- New state: `ReadinessController` (doctor `check` events → areas; `xcross --version`) and `DeviceController`
  (shared `devices --json`). `Settings` gains wizard dismissal, theme, console open/height and the Xcode.xip path.
- New command builders: `setup --yes`, `sdk install <xip>`, `--version`, `update --check`, `ide vscode|idea`,
  `tunnel`, and `auth --anisette-url=`.

## Fonts

Bundled under `apps/studio/assets/fonts/` with their SIL OFL 1.1 licences (`Inter-OFL.txt`,
`JetBrainsMono-OFL.txt`). Downloaded from the official GitHub releases only:

| Font | Release asset | SHA-256 of the archive |
|---|---|---|
| Inter 4.1 | https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip | `9883fdd4a49d4fb66bd8177ba6625ef9a64aa45899767dde3d36aa425756b11e` |
| JetBrains Mono 2.304 | https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip | `6f6376c6ed2960ea8a963cd7387ec9d76e3f629125bc33d1fdcd7eb7012f7bbf` |

Files used (from `extras/ttf/` and `fonts/ttf/`), with their SHA-256:

| File | SHA-256 |
|---|---|
| Inter-Regular.ttf | `40d692fce188e4471e2b3cba937be967878f631ad3ebbbdcd587687c7ebe0c82` |
| Inter-Medium.ttf | `97ad806f526e41546d46365bb3a393145f75b7b1568913db74549ad8b8dba872` |
| Inter-SemiBold.ttf | `78a843fade9d4612a5567302fb595b56976eb5fcebf4fea5a5912d638bafcde3` |
| JetBrainsMono-Regular.ttf | `a0bf60ef0f83c5ed4d7a75d45838548b1f6873372dfac88f71804491898d138f` |
| JetBrainsMono-Medium.ttf | `31c92d01a8a08528b718a43addf0ad3df0af2ca4b7b3290a452f70f358e14d3d` |

System fonts are fallbacks (`Segoe UI`, `Ubuntu`, `Cascadia Mono`, `DejaVu Sans Mono`, …).

## Decisions

- **Dark theme**: the doc's exact tokens. The **light theme** uses derived tokens, which are not in the doc; they
  were chosen to pass the same 4.5:1 contrast test.
- **Readiness** areas are matched from check names (`swift`, `SDKROOT` → Swift; `clang`, `llvm`, `linker` → LLVM;
  `Darwin SDK`; `Authentication`; `Device…`; `Flutter SDK`). Unknown checks don't change a card.
- **Wizard auto-open**: once per launch, after the first doctor run, only when an area failed and the wizard was
  never dismissed.
- **Honesty**: no invented codes (diagnostic cards read the CLI's `[code]` and `hint:` lines); determinate
  progress only from `progress.fraction`; Cancel/Stop only for running jobs (`Job.cancel` kills the tree).

## Constitution Check

| Principle | Status | Note |
|---|---|---|
| I | ✅ | only `apps/studio` and docs change; no upstream file touched |
| II | ✅ | wizard uses the user's own `Xcode.xip`; nothing from Apple is shipped |
| III | ✅ | diagnostic cards show the CLI's codes and hints |
| IV | ✅ | GUI stays a thin shell; every action is an `xcross` command, previewed |
| V | ✅ | no OS-specific UI code beyond the existing `HostPlatform` |
| VI | ✅ | AC → tests below; device-check rows |
| VIII | ✅ | password masked in previews and copies; fonts under OFL with licence files |

## AC → tests

| AC | Test |
|---|---|
| AC-013-1, AC-008-9 | `test/ui/app_test.dart` `AC-008-9 AC-013-1 …` |
| AC-013-2 | `app_test.dart` `AC-013-2 …` |
| AC-013-3 | `app_test.dart` `AC-013-3 …` |
| AC-013-4 | `app_test.dart` `AC-013-4 …`; `test/design_system/components_test.dart` `AC-013-4 …` |
| AC-013-5 | `app_test.dart` `AC-013-5 …` (both) |
| AC-013-6…9 | `app_test.dart` |
| AC-013-10 | `app_test.dart` `AC-013-10 …` |
| AC-013-11…17 | `components_test.dart` |
| AC-008-1/7/8, FR-001 | `app_test.dart` |
| AC-012-6…8 | `test/state/build_events_test.dart` |
| visual review | `test/ui/screenshot_test.dart` (opt-in, `STUDIO_SCREENSHOTS=1`) |
