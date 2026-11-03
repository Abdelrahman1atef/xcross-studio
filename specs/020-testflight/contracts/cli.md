# CLI contract: `xcross testflight`

Common options: `--app-id <Apple ID of the app>` (default: the record for the project's bundle ID). Build-scoped
commands take `--build <build number>` (default: the newest upload).

| Command | Effect |
|---|---|
| `status [--build <n>] [--version <x.y.z>] [--limit <n>] [--json]` | builds with processing and beta states |
| `groups [--json]` | beta groups |
| `group create <name> [--external] [--public-link] [--public-link-limit <n>]` | new group |
| `add --group <name> [--build <n>]` | build joins the group |
| `what-to-test "<text>" [--build <n>] [--locale en-US]` | build's What to Test |
| `testers add <email>… --group <name> [--first-name] [--last-name]` | invite into the group |
| `testers list --group <name> [--json]` | group's testers |
| `compliance --no-encryption\|--uses-encryption [--build <n>]` | export compliance answer |
| `app-info [--description] [--feedback-email] [--marketing-url] [--privacy-url] [--locale en-US]` | beta app information |
| `review-info [--contact-first-name] [--contact-last-name] [--contact-email] [--contact-phone] [--demo-user] [--demo-password] [--notes]` | beta review details |
| `submit [--build <n>]` | TestFlight App Review submission |
| `public-link --group <name> [--enable\|--disable] [--limit <n>]` | public link on/off, printed |

`status --json`:
```json
{"v":1,"type":"testflight_status","appId":"123","bundleId":"com.example.app","builds":[
 {"id":"b1","version":"1.2.0","buildNumber":"7","uploadedDate":"2026-11-03T10:00:00Z","processingState":"VALID",
  "expired":false,"usesNonExemptEncryption":false,"internalBuildState":"READY_FOR_BETA_TESTING",
  "externalBuildState":"READY_FOR_BETA_SUBMISSION","groups":["QA"]}]}
```
`groups --json`: `{"v":1,"type":"testflight_groups","groups":[{"id","name","internal","publicLinkEnabled","publicLink"}]}`.
`testers list --json`: `{"v":1,"type":"testflight_testers","group":"QA","testers":[{"id","email","firstName","lastName","state"}]}`.
