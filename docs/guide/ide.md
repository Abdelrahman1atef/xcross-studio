# IDE integration

[← xcross README](../../README.md) · [All guides](README.md)

## VS Code

```sh
xcross ide vscode
```

Writes the DAP shim and upserts two xcross launch entries + DAP settings into `.vscode/`: **xcross: iPhone · debug (iOS 17+)** (hot reload) and **xcross: iPhone · release (iOS 15/16)** (`--release`; iOS 15/16 cannot run debug builds). Pick one in the Run and Debug dropdown and press **F5** to build, sign, install, and launch. Flutter's own device picker never lists an iPhone on Windows/Linux; these entries are where it shows up. Hot Reload / Restart buttons drive the same `r`/`R` commands as the CLI, and DevTools attaches to the same VM Service connection.

- Works in VS Code forks with the Dart-Code extension installed.
- The xcross launch config sets `"env": { "XCROSS": "true" }`; other Flutter launch configs in the workspace keep working - sessions without that marker are handed to Flutter's own debug adapter.
- For multiple iPhones, set `"args": ["--udid", "<UDID>"]` on the xcross entry; re-running the command preserves those args.
- Existing `launch.json` / `settings.json` are merged in place (xcross keys upserted, everything else kept). A second run is a no-op when already current.
- Run the *installed* `xcross`; the generated DAP shim records that binary's path.

## JetBrains IDEA / Android Studio

```sh
xcross ide idea
```

Writes `.run/xcross_ios_device.run.xml` (debug, iOS 17+) and `.run/xcross_ios_release.run.xml` (release, iOS 15/16) - shared [LSP4IJ](https://plugins.jetbrains.com/plugin/23257-lsp4ij) Debug Adapter Protocol run configurations that start `xcross flutter dap` over stdio. They appear in the run-configuration dropdown next to the device picker.

- Install the LSP4IJ plugin, then pick **xcross: iPhone · debug (iOS 17+)** or **xcross: iPhone · release (iOS 15/16)** and press Debug (don't use Flutter's Run button - it still calls `flutter run`).
- Breakpoints and stepping use the DAP/VM Service path; Restart maps to hot restart. Console `r`/`R` still work.
- Re-running updates the files xcross wrote (for example after moving xcross; the old version is kept as `.bak`). A run configuration you wrote yourself is never overwritten; it is printed for you to merge.
