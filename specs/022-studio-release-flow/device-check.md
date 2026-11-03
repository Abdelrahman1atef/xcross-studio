# Device check: 022 XCross Studio release flow (Windows host)

| # | AC | Step | Expected | Result |
|---|---|---|---|---|
| 1 | AC-022-5 | app A: `xcross release gate --skip-tests` (packaged CLI) | runs the project's `flutter analyze`, reports the result, exit 1 on findings | ✅ 2026-11-03: 7 analyzer findings in app A (unused imports, one lint) → "The quality gate failed: flutter analyze" |
| 2 | AC-022-6 | `xcross release --help` (packaged CLI) | `check`, `ci`, `gate` listed | ✅ 2026-11-03 |
| 3 | AC-022-8 | packaged desktop app (`dist/xcross-studio-windows-x64`, rebuilt with the new CLI) | Release and Archives in the sidebar; steps run their commands | ✅ built 2026-11-03; ⏳ click-through by the user |
| 4 | AC-022-2…3 | Release steps 5, 7–9 with a team key | App Store build, upload, TestFlight, submission from the app | ⏳ needs a team key |
