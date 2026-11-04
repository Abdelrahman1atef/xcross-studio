# CLI contract: 025

## `xcross plugin check [--project <dir>]`

One line per iOS plugin. Exit 0, or 1 with `[plugin.unknown_pods]` when a build would leave one out. Writes nothing.

```text
✔ modern 1.0.0  (swiftpm)
✔ mine 2.0.0  (override)
✔ dart_only 1.0.0  (no iOS code)
✔ draftable 1.0.0  (podspec only: the next build drafts it)
✖ vendored 1.0.0  (podspec only, no Swift package for: SomeVendorSDK)
```

## Build warnings

| Code | Subject | When |
|------|---------|------|
| `build.plugin_drafted` | plugin | A build wrote `xcross_overrides/<plugin>/<version>/Package.swift` |
| `build.plugin_unknown_pods` | plugin | A pod has no known Swift package, so its native code is left out |

Removed: `build.runner_legacy_registration`. A pre-UIScene app delegate no longer needs a warning (AC-025-7).

## Environment

| Variable | Value | Effect |
|----------|-------|--------|
| `XCROSS_PLUGIN_DRAFTS` | `off` | Builds do not draft; podspec-only plugins are left out with `build.podspec_only_plugin` |
| `XCROSS_PLUGIN_BUILD` | `distribution` | Plugins build without `DEBUG` and with optimization, as for `--export-method app-store` |
