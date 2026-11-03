# Device check: Icon studio

| # | AC | Step | Expected | Result |
|---|----|------|----------|--------|
| 1 | AC-023-1…3 | app A: `xcross icons check` (rebuilt CLI) | 19 slots listed with roles; the App Store icon's alpha channel reported as `icons.alpha`; placement measured; exit 1 | ✅ 2026-11-03: all 19 slots `ok`; `icons.alpha` error on the App Store icon (the same problem `release check` found in 018); placement "logo 67% × 47% · centred · inside the corners" |
| 2 | AC-023-5, 6 | app A: `xcross icons generate <its App Store icon> --output <scratch>` | 15 PNGs and `Contents.json`, no alpha channel, project unchanged | ✅ 2026-11-03: written in 1.1 s; `git status` of the project's asset catalog clean; the scratch set passes `icons check` ("The icon set is ready."); the 180 px home-screen file is sharp and centred |
| 3 | AC-023-8…10 | XCross Studio: App icon page on app A | previews, slots, issues; "Make icon set…" preview | ⏳ after repackaging the desktop app (widget tests cover the page) |
| 4 | AC-023-11 | app A: "Write icon set" (or `icons generate` without `--output`), build, install | home screen, Settings and notification show the icon; `release check` has no `release.marketing_icon` error | ⏳ writes into the project: the user's call |
