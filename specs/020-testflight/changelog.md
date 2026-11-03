- `xcross testflight` takes an uploaded build through TestFlight from Windows or Linux with an App Store Connect team
  key (Admin or App Manager): `status [--json]` (processing state, internal/external beta states, export compliance,
  groups), `groups`, `group create [--external] [--public-link]`, `add --group`, `what-to-test`, `testers add|list`,
  `compliance --no-encryption|--uses-encryption`, and for external testing `app-info`, `review-info` (the demo
  password is never printed), `submit` and `public-link`. The app is `--app-id` or the App Store Connect record of
  the project's bundle ID; the build is `--build <number>` or the newest upload. Apple's refusals name the role
  needed. ([specs/020-testflight](specs/020-testflight/spec.md))
