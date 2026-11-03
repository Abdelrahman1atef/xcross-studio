# Store check: 020 TestFlight (Windows host)

No App Store Connect **team** key with the Admin or App Manager role is configured on this PC (only an Apple ID
session and an individual key), so every store row waits for one.

| # | AC | Step | Expected | Result |
|---|---|---|---|---|
| 1 | AC-020-1 | `xcross testflight status` in app A after `xcross publish` | the uploaded build, `VALID` once processed, beta states | ⏳ needs a team key and an upload (019) |
| 2 | AC-020-7 | `xcross testflight compliance --no-encryption` | `MISSING_EXPORT_COMPLIANCE` cleared | ⏳ |
| 3 | AC-020-3, 4, 5 | `group create QA`, `add --group QA`, `what-to-test "…"` | build in the internal group with notes | ⏳ |
| 4 | AC-020-6, 10 | `testers add <email> --group QA`; install from TestFlight on the iPhone X | invitation arrives; app installs and opens | ⏳ |
| 5 | AC-020-8, 9, 10 | `app-info`, `review-info`, `submit`, `public-link --group Public` | beta review submission accepted; public link printed | ⏳ |
