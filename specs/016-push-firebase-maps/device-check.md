# Device check: 016 Firebase, push and Maps (Windows host, iPhone X iOS 16.7.16)

Apps: app A (Firebase, FCM, Google Maps, Pusher; had `bundle_id: prefixed`, no entitlements file) and app B (Maps,
Firebase, Pusher, audioplayers; `Runner.entitlements` with push and associated domains). Bundle IDs, the team and the
device are not recorded here. No developer disk image on this PC, so iOS 16 apps are opened from their icon.

| # | AC | Step | Expected | Result |
|---|---|---|---|---|
| 1 | AC-016-2 | app A: `xcross project bundle-id` | saved `prefixed`, next build prefixed | ✅ 2026-11-03 |
| 2 | AC-016-6 | app A: `xcross flutter doctor` | "Push notifications": entitlement ⚠ inferred, App ID ✗ with the fix, Firebase config ✓ | ✅ 2026-11-03 |
| 3 | AC-016-2 | app A: `xcross project bundle-id original` | saved, pubspec otherwise unchanged | ✅ 2026-11-03 |
| 4 | AC-016-4, 9, 10 | app A: `xcross flutter build --release --ipa` | `build.push_entitlement_inferred`; "AppDelegate has its own code; compiling the project sources"; no `build.runner_project_failed` (`import GoogleMaps` compiles) | ✅ 2026-11-03 |
| 5 | AC-016-1 | app A: `xcross install <ipa>` in the project | signed under the real ID (the saved choice applies to `install` too) | ✅ 2026-11-03 (first run used the old prefixed ID: fixed, install now reads the project's settings) |
| 6 | AC-016-5 | same | no false "Enabled"; a refused capability named with Apple's reason | ✅ 2026-11-03: the prefixed ID showed `[sign.capability_not_enabled] … still off`; the real ID showed Apple's 409 "relationship 'capabilities' is required" (research R6), then "Enabled the PUSH_NOTIFICATIONS capability" after the fix |
| 7 | AC-016-11 | app A: `xcross app info <id>` | `push: development` | ✅ 2026-11-03 (before the fix: `push: null`) |
| 8 | AC-016-11 | app A: open from the icon; map screen | map renders, no crash | ⏳ needs a tap on the iPhone |
| 9 | AC-016-11 | app A: `xcross logs --app <id> --preset push` while opening | FCM token logged non-null; no Firebase bundle-ID errors | ⏳ needs a tap on the iPhone |
| 10 | AC-016-11 | backend sends "order paid" | notification shown | ⏳ needs a backend order |
| 11 | AC-016-11 | app B: `xcross flutter build --release --ipa` | completes (GoogleMaps links) | ✅ 2026-11-03: project runner compiled (2 Swift), IPA written |
| 12 | AC-016-11 | app B: install; `app info` | "Enabled the ASSOCIATED_DOMAINS/PUSH_NOTIFICATIONS capability"; `push: development` | ✅ 2026-11-03 |
| 12b | AC-016-11 | app B: open from the icon, map screen | map renders | ⏳ needs a tap on the iPhone |
| 13 | AC-016-3, 7 | XCross Studio: Signing → App ID; Overview | real/prefixed badge and switch; "Push notifications" card | ⏳ after repackaging the desktop app |
