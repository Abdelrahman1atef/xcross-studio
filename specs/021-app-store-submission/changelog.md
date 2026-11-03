- App Store submission from the command line with the App Store Connect API (`xcross appstore …`):
  - `app [--json]` finds the project's app record, or explains that Apple's API cannot create apps and prints the
    New App page with the bundle ID, name and SKU to enter (exit 1).
  - `version [<x.y.z>] [--create]` shows or creates the editable iOS version.
  - `metadata pull|push` syncs a fastlane-style `appstore/metadata` folder (names, subtitles, privacy URL,
    description, keywords, promotional text, release notes, support and marketing URLs, copyright, categories, age
    rating), creating missing localizations and sending only changed fields.
  - `screenshots push [--replace]` checks every PNG's size against Apple's sizes for its display type before
    anything is sent, then reserves, uploads to Apple's upload operations (without the API token) and commits each
    image with its MD5.
  - `attach --build <n>`, `submit [--dry-run]` (blockers it can see: no build, missing texts or screenshots) and
    `status [--json]`. App Privacy, pricing and agreements are not in the API; the commands point to those pages.

  ([specs/021-app-store-submission](specs/021-app-store-submission/spec.md))
