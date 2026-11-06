# Implementation and Validation Guide

## Implementation baseline (2026-11-06, Windows)

- Branch: `codex/029-xcode-ide-workspace`. Existing changes in `apps/studio/analysis_options.yaml`, `pubspec.yaml`, `pubspec.lock`, `android/`, the design document and this feature spec were present before implementation and are preserved.
- Host tools: Flutter 3.47.0 stable, Dart 3.13.0, Windows 11. Repository CI pins Flutter 3.47.8.
- `flutter analyze` in `apps/studio`: passed, no issues (46.1 seconds).
- `flutter test` baseline: passed, 170 tests (1 minute 57 seconds). Linux baseline has not been run on this Windows host.
- Installed `xcross` on PATH is version 2.0.9. Its top-level help has no `devices`, `install`, `release`, `sign`, `logs` or `inspect` commands used by this GUI. It cannot serve as evidence for the planned workspace capabilities.

Implementation is authorized and has started. Only the dated evidence above or in test-plan.md records executed tests; the remaining commands are validation instructions.

## Resume

Use branch `codex/029-xcode-ide-workspace` and feature directory `specs/029-xcode-ide-workspace`. `.specify/feature.json` points here; Spec Kit may report the logical feature name without the Git prefix. Read spec, plan, tasks and contracts first. Check `git status --short` and preserve unrelated modifications.

```powershell
git branch --show-current
git status --short
python -X utf8 .specify/scripts/python/check_prerequisites.py --json --require-spec --require-tasks --include-tasks
```

Planning stage sequence: specify → clarify review → plan/research/design → tasks → requirements checklist → read-only analysis. Implementation resumed after the requirements review. No extension hooks are configured (`.specify/extensions.yml` absent).

## Prerequisites for Later Tests

Use project-compatible Flutter/Dart (repository CI currently Flutter3.47.8; Dart constraint>=3.13<4), native Windows/Linux desktop build prerequisites, temporary Flutter fixture projects and selected xcross binaries for capability cases. Devices/SDK/auth are unnecessary for fake-process widget tests. Real-device runs require user-provided Apple material, supported device setup and appropriately protected credentials.

From repository root, after implementation is authorized:

```powershell
Set-Location apps/studio
flutter --version
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

On native Linux use equivalent `cd apps/studio` and `flutter run -d linux`; run analyze/test there too. Dependency resolution can update locks: review those changes, especially existing user changes. Do not interpret an old suite passing as proof of the new ACs; add and run the named acceptance tests first per tasks.md.

## Manual Journey Order

1. Empty workspace/gallery → resize/collapse → restart; confirm safe persisted layout.
2. Open a real temporary project → tree/search/tabs/edit/save → external conflict → diagnostics/semantic actions.
3. Unsupported binary → capability explanations; supported binary → onboarding/doctor → target/configuration → Run → actual stages/attach → reload/restart → Stop.
4. Disconnect/fail readiness → repair action; auth UI → guarded secrets; release → verified artifact/inspect/reveal without publication claim.
5. Preview metadata/demo/supported screenshot labels → keyboard/palette/remapping → scale/reduced-motion/theme → process recovery.

Record results in test-plan.md/device-check.md. Preserve sanitized evidence only. Source acceptance is complete only with all12 criteria and applicable constitution gates evidenced on both hosts.

2026-11-06 resume checks: prerequisites script resolved this feature; requirements.md 12/12 and ux-security.md 12/12. Existing Dart/Flutter build/cache ignore patterns verified; no new dependency or generated-file class introduced. No extension hooks file exists. T002 research records the successful native Windows LSP capability spike and remaining editor validation gate.
