# Device check: all-screens preview, full splash control, signing status

Before each iPhone row: restart the phone, then install a release build. iOS keeps showing the splash it saved, and a debug
build crashes when opened from the home screen.

| # | AC | Step | Expected | Result |
|---|----|------|----------|--------|
| 1 | fix | Build a project whose asset has a space in its name, install, open the screen that uses it | The asset loads, such as a Lottie animation on a loading screen | ⏳ needs the iPhone |
| 2 | fix | Transparent logo; splash in light mode | Logo on the chosen colour, no black square | ✅ iPhone X, iOS 16.7.16, 2026-11-04, read from the launch images iOS saved; ⏳ the user's own look |
| 3 | fix | The same in dark mode | Logo on the dark colour, no black square | ✅ the same images, where the dark colour equals the light one. ⏳ a dark colour that differs |
| 4 | fix | Cold start 3 times | Same size each time, no stretching | ⏳ needs the iPhone |
| 5 | AC-026-5, 6 | Signing page, with the real saved sign-in | Status shows the method and details; the form starts on that method; no password | ✅ CLI on this machine 2026-11-04: `deviceBuilds` and `appStoreBuilds` are the saved team key, key file found. ⏳ page in a live window |
| 6 | AC-026-8…13, 16 | Real CLI, real project: App icon page and `All screens`, as a scratch render | Every family, true proportions, the logo and icon in each frame, dark and guides | ✅ a real project, 2026-11-04, as saved images, not a live window |
| 7 | AC-026-14, 15 | In the app: `Write icon and splash to project`, on a test project | Both written; each result shown | ⏳ |
| 8 | AC-026-15 | In the app: `Export icon and splash…` | A folder with both | ⏳ a folder dialog cannot run in a test |
| 9 | AC-026-18 | In the app: `Export zip…` on the Splash tab | One archive | ⏳ a save dialog cannot run in a test |
| 10 | SC-005 | Compare the frames with the installed app, on the phone at hand | They match | ⏳ needs the iPhone |
| 11 | AC-026-19 | An iPad width, on an iPad if one is at hand | iPad uses its size, iPhone is unchanged | ⏳ needs an iPad |
| 12 | AC-026-20, 21 | Android 12+ and an older Android, if at hand | Icon background and branding as previewed | ⏳ needs Android devices |
| 13 | AC-026-24 | Prebuilt storyboard on the iPhone: see research.md | Full-screen picture, transparent logo over it, same on repeated cold starts | ⏳ needs the user's agreement to run CI |
| 14 | AC-026-25, 26, 27 | Follows row 13 | The option appears only if row 13 works | ⏳ |
