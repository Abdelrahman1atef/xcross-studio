# Tasks: Compile the project's own Runner code

X = `packages/xcross/lib/src`, XT = `packages/xcross/test`.

- [X] T001 Research how the runner is built today (shim, Swift toolchain, plist) → `research.md`.
- [X] T002 `X/shared/flutter/build/project_runner_sources.dart`: `RunnerMode.fromEnvironment` (`XCROSS_RUNNER`) and
  `ProjectRunnerSources.discover`, covering:
  - the pbxproj application target (Sources phase plus synchronized folders), with an `ios/Runner` listing as
    fallback;
  - leaving out `GeneratedPluginRegistrant.m`;
  - the bridging header, module name, implicit-engine vs. launch registration, and a non-empty `SceneDelegate`.
- [X] T003 `X/shared/flutter/build/project_runner.dart`:
  - `ProjectRunner`: mode check, warnings, fallback with the compiler's first errors.
  - `ProjectRunnerBuilder`: clang objects, then a swiftc link (Swift) or an ld64.lld link (Objective-C only); the
    support source (registrant plus `XcrossSceneDelegate`); `withSceneDelegate`.
- [X] T004 Seams (`// studio: 007`): linker (project runner before the shim, plugin modules directory),
  `RunnerBinary.sceneDelegateClass`, assembler plist rewrite.
- [X] T005 Codes `build.runner_project_failed`, `build.runner_legacy_registration` and
  `build.runner_scene_delegate_replaced` in `xcross_diagnostics.dart` (and `all`), plus the 002 diagnostics contract.
- [X] T006 Tests: `XT/flutter/build/project_runner_test.dart` (AC-007-1…6) and
  `XT/flutter/build/project_runner_assembly_test.dart` (AC-007-4, Linux).
- [X] T007 Docs: spec, plan, research, tasks, device-check, CHANGELOG, ROADMAP, README; analyze; tests; commit;
  push.
- [ ] T008 (deferred) `--runner=project|shim` flags on `flutter build` and `flutter run` (regenerate the build_cli
  parsers).
