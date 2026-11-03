# Store check: 021 App Store submission (Windows host)

No App Store Connect **team** key is configured on this PC (an Apple ID session and an individual key only), so every
row that writes to App Store Connect waits for one. Client app names and IDs are not recorded here.

| # | AC | Step | Expected | Result |
|---|---|---|---|---|
| 1 | AC-021-1 | app A folder: `xcross appstore app` | record found (name, Apple ID, SKU) or the New App instructions | ✅ 2026-11-03 (individual key): no record visible → New App instructions, exit 1 |
| 1b | AC-021-1 | app B folder: `xcross appstore app` | record found | ✅ 2026-11-03: name, Apple ID, bundle ID, SKU, primary locale |
| 2 | AC-021-2 | `xcross appstore version 1.0.0 --create` | editable version shown or created | ⏳ team key |
| 3 | AC-021-3 | `xcross appstore metadata pull` | `appstore/metadata` written | ⏳ |
| 4 | AC-021-4 | edit `en-US/description.txt`; `metadata push` | one change line; App Store Connect shows the text | ⏳ team key |
| 5 | AC-021-5, 6 | `screenshots push` with one 1290×2796 PNG and one wrong-size PNG | size error before any upload; after fixing, the screenshot appears in the 6.7" set | ⏳ team key |
| 6 | AC-021-7 | `appstore attach --build <n>` (after 019) | build attached | ⏳ team key |
| 7 | AC-021-8 | `appstore submit --dry-run` | only real blockers listed | ⏳ team key |
| 8 | AC-021-9 | `appstore status` | version state, build, submissions | ✅ 2026-11-03 (app B, individual key): next version `PREPARE_FOR_SUBMISSION`, no build attached, past review submissions `COMPLETE` |
