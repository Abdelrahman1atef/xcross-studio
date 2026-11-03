# Quickstart: verify 016

1. `cd <app A>`; `xcross project bundle-id` → saved `prefixed`. `xcross flutter doctor` → "Push App ID ✗".
2. `xcross project bundle-id original` → saved; doctor → "Push App ID ✓", "Push entitlement ⚠ inferred".
3. `xcross flutter build --release --ipa` → warning `build.push_entitlement_inferred`; log line
   "Google Maps key: from AppDelegate.swift"; `xcross inspect build/xcross-ios/*.ipa` shows `aps-environment`.
4. `xcross flutter run --release` on the iPhone X → map opens; `xcross app info <bundle id>` → `push: development`.
5. `xcross logs --app <bundle id> --preset push` while the backend sends "order paid" → notification shown, FCM
   token logged non-null, no `[FirebaseInstallations]` bundle errors.
6. App B: `xcross flutter build --release --ipa` completes; run → map opens.
