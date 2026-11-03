# Device and store check: 018 App Store build and release check (Windows host)

No App Store Connect **team** key is configured on this PC (only an Apple ID session and an individual key, which
cannot create distribution certificates), so the signed export waits for one.

| # | AC | Step | Expected | Result |
|---|---|---|---|---|
| 1 | AC-018-6 | app A: `xcross flutter build --release --ipa` with the new CLI | Info.plist has DTXcode (from the SDK), DTSDKBuild, DTPlatformBuild, DTCompiler; DTXcodeBuild missing for an SDK installed before 018 | ✅ 2026-11-03 (`release check`: only DTXcodeBuild reported) |
| 2 | AC-018-12 | same, `release check` | plugin privacy manifests present | ✅ 2026-11-03 after the fix below (first run: 9 plugins "missing" a manifest, 2 required-reason categories undeclared) |
| 3 | — | IPA contents | SwiftPM resource bundles at the app root | ✅ 2026-11-03: **found missing** on the first run (no `*.bundle` in the app; Google Maps and Firebase resources and 40 privacy manifests absent). Fixed: the assembler now embeds every `<Package>_<Target>.bundle`; app A's IPA has 43 bundles, 41 manifests |
| 4 | AC-018-9…13 | app A: `xcross release check` | configuration block; errors first; exit 1 | ✅ 2026-11-03: errors `release.marketing_icon` (the 1024 icon has an alpha channel: a real ITMS-90717 risk in the project) and `release.not_signed`; warnings DTXcodeBuild, encryption unset, no app privacy manifest |
| 5 | AC-018-7 | `xcross flutter doctor` | Darwin SDK ✓ (iOS 27.1 ≥ 26) | ✅ 2026-11-03 |
| 6 | AC-018-1…5 | app A with a team key: `--export-method app-store` | signed IPA + archive with dSYMs; `release check` without signing errors | ⏳ needs a team key (Admin or App Manager) |
| 7 | AC-018-6 | `xcross sdk install <Xcode 26+ .xip>` again | `xcross-xcode-version.plist` recorded; DTXcodeBuild written | ⏳ optional reinstall |
