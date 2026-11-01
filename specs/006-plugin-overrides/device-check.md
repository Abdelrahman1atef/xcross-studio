# Device check: 006 (iPhone X, iOS 16.7.16, Windows host)

Prerequisites:

- `xcross auth` done.
- A Flutter project that uses a podspec-only plugin with a small native surface, ideally Objective-C or Swift
  sources in `ios/Classes` with no third-party pods. Record which plugin and version are used, but no client names.
- An override `xcross_overrides/<plugin>/Package.swift` in the project. Its target points at `Classes`, sets
  `publicHeadersPath` for Objective-C headers, and depends on `FlutterFramework`, like Flutter's own SPM plugin
  template.

| # | AC | Step | Expected | Result |
|---|---|---|---|---|
| 1 | AC-006-5 | build without the override | `warning: [build.podspec_only_plugin] …` with the new hint | ⏳ |
| 2 | AC-006-3 | add the override, `xcross flutter build --release` | `warning: [build.plugin_override_applied] Plugin "<plugin>" is built with the Package.swift from …`; build succeeds | ⏳ |
| 3 | AC-006-7 | `xcross flutter run --release`, use the plugin's feature | the method channel answers (no hang) | ⏳ |
| 4 | AC-006-2 | add `override.yaml` with `versions: "<2.0.0"` while the plugin is ≥ 2 | `warning: [build.plugin_override_invalid] … is for versions …`; plugin skipped as in row 1 | ⏳ |
| 5 | FR-002 | build twice without changes | the second plugin build is incremental (no full recompile of the plugin) | ⏳ |
| — | Linux | rows 1–3 on Ubuntu 24.04 | same | ⏳ deferred (Linux checks are on the todo list) |
