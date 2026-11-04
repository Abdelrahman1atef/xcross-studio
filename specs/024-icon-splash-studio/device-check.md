# Device check: Icon and splash studio

On a new test project (`flutter create`), not a client project.

| # | AC | Step | Expected | Result |
|---|----|------|----------|--------|
| 1 | AC-024-17…19 | The studio's code with the real CLI: image, gradient, badge, text, clipart, each target strip entry, splash tab | previews drawn by `icons preview --serve`, no layout faults | ✅ 2026-11-04, from rendered screenshots |
| 2 | AC-024-15, 16, 20 | "Write to project" and "Write splash to project" | default targets are the project's folders; every platform's files written; `xcross_assets.json` with relative paths; copies in `.xcross/assets/` | ✅ 2026-11-04 |
| 3 | AC-024-20 | `xcross icons generate --config`, `xcross splash generate --config`, `xcross splash check` | same files from the saved settings, no errors | ✅ 2026-11-04, exit 0, "No problems found." |
| 4 | AC-024-21 | Build the test project for the simulator, which needs no signing | the app has the icon set, and the storyboard read into `UILaunchScreen` | ✅ 2026-11-04: `Info.plist` has `UILaunchScreen` with `LaunchImage` and `LaunchBackground`; `AppIcon*.png` and `Assets.car` in the app |
| 5 | AC-024-21 | Install on an iPhone; open it | home screen icon and the splash look like the previews | ⏳ needs the user's eyes on the phone |
