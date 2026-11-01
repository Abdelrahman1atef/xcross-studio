# Device check: 008 GUI (Windows host, iPhone X iOS 16.7.16)

Start with `cd apps/studio && flutter run -d windows`, or run the release build
`apps/studio/build/windows/x64/runner/Release/xcross_studio.exe`. In Setup, choose **Run from source** and pick this
repository folder: the installed upstream `xcross` does not have the XCross Studio commands.

| # | AC | Step | Expected | Result |
|---|---|---|---|---|
| 1 | AC-008-9 | open each page | all five pages render | ⏳ |
| 2 | — | Setup → Run doctor | doctor output with ✔/✖ (no `?` characters) | ⏳ |
| 3 | AC-008-1 | Device page, phone connected | "iPhone X · iOS 16.7.16 · release/profile only" | ⏳ |
| 4 | AC-008-1 | unplug, Refresh | "No iPhone is connected by USB" + hint | ⏳ |
| 5 | — | Project → pick a Flutter project → Build (release, .ipa) | live build output; Open output folder works | ⏳ |
| 6 | — | Device → Build & run (release) | signed + installed; tap-the-icon guidance | ⏳ |
| 7 | — | Device → Sign & install an .ipa | installed | ⏳ |
| 8 | AC-008-2, 6 | Device logs → load apps → pick app → Flutter preset → Start | live lines; filters, pause and save work | ⏳ |
| 9 | AC-008-7 | Device logs → App info | ✔/✖ push + associated domains, entitlements list | ⏳ |
| 10 | AC-008-6 | Push preset with the app | push checklist fills in; verdict shown | ⏳ |
| 11 | AC-008-7 | Crashes → list → save | report saved, folder opens | ⏳ |
| 12 | AC-008-5 | Stop a running log or build | process tree ends (no stray `python`/`xcross` in Task Manager) | ⏳ |
| 13 | AC-008-5 | Setup → Sign in with Apple ID; type the 2FA code in the input box | signed in | ⏳ |
| — | Linux build | CI `Studio GUI` on ubuntu-24.04 (run 41334807521) | analyze clean, 20 tests pass, `flutter build linux` + CLI bundle packaged, packaged CLI runs | ✅ 2026-11-01 (CI, no device) |
| — | Windows build | same run on windows-2022 | as above + Inno Setup per-user installer built | ✅ 2026-11-01 (CI) |
| — | Windows package | local `dart run tool/package.dart`, start `xcross_studio.exe` | GUI starts and runs the bundled `xcross\bin\xcross.exe devices --json` | ✅ 2026-11-01 (no phone connected) |
| — | Linux | same steps on Ubuntu 24.04 with the iPhone | | ⏳ deferred (Linux device checks are on the todo list) |
