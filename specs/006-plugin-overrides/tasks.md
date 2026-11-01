# Tasks: Plugin overrides

X = `packages/xcross/lib/src`, XT = `packages/xcross/test`. Every edited upstream hunk is marked `// studio: 006`.

- [X] T001 `X/shared/flutter/build/plugin_overrides.dart`: `PluginOverrideLocator` (search order, version folders,
  `override.yaml` `versions:`), `PluginOverrides` (`apply`, `materialize`, content-compared sync), and
  `OverrideVersion` / `OverrideVersionConstraint`.
- [X] T002 `xcross_diagnostics.dart`: `build.plugin_override_applied` and `build.plugin_override_invalid` (in
  `all`); the `build.podspec_only_plugin` hint names `xcross_overrides/<plugin>/Package.swift`.
- [X] T003 `flutter_artifact_compiler.dart` `_buildPlugins`: build the workspace first, then apply overrides to the
  discovered plugins with the staging root `<workspace>/overrides`.
- [X] T004 `ios_deployment_target_resolver.dart` + `flutter_build_runtime.dart`: the override manifest's iOS floor
  counts (`environment` for `~/.xcross`).
- [X] T005 Tests `XT/flutter/build/plugin_overrides_test.dart` (AC-006-1…6).
- [X] T006 Docs: README "Plugin overrides", CHANGELOG, ROADMAP, the 002 diagnostics contract hint, `device-check.md`.
- [X] T007 Analyze, run the tests, commit, push.
- [ ] T008 Follow-up: `xcross plugin shim <plugin>` (a draft Package.swift from the podspec), remote binary targets
  and resource bundles, Google Maps / Pusher shims.
