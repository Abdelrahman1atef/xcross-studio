# Device check: 013 design system (Windows host, iPhone X iOS 16.7.16)

Start the app (`cd apps/studio && flutter run -d windows`, or the packaged `xcross_studio.exe`).

| # | AC | Step | Expected | Result |
|---|---|---|---|---|
| 1 | AC-013-1 | open every sidebar destination | all seven render; dark theme, Inter text, JetBrains Mono logs | ⏳ |
| 2 | AC-013-5 | first launch on a PC where the doctor fails | the setup wizard opens; Close keeps it closed on the next launch | ⏳ |
| 3 | AC-013-4 | after the toolchain setup, Overview → Run checks | readiness cards and status bar turn ✓ | ⏳ |
| 4 | AC-013-2 | Ctrl+K → "devices"; Ctrl+, ; Ctrl+L ; Ctrl+J | palette navigates; shortcuts work | ⏳ |
| 5 | AC-013-3 | shrink the window below 1100 px | icon rail, compact bars, no clipped text | ⏳ |
| 6 | AC-013-9 | start a build, drag the console edge, collapse it, restart the app | console size and state remembered; Stop ends the build | ⏳ |
| 7 | AC-013-8 | Signing → Apple ID | risk notes and the anisette URL are visible; sign-in with 2FA works | ⏳ |
| 8 | — | Devices with the iPhone connected | card lists USB, iOS 16.7.16 "release and profile only"; Sign & install works | ⏳ |
| 9 | — | Build & Run (release) | command preview matches what runs; steps appear; finish card shows the artifact | ⏳ |
| 10 | — | Settings → Light theme | whole app switches; readable | ⏳ |
