# studio_ext

Fork-only features of XCross Studio, kept out of the upstream xcross packages so upstream releases merge cleanly
(constitution Principle I). The `xcross` CLI registers these commands at its composition root.

Features:

- `xcross inspect <ipa|app> [--json] [--normalize]` is a read-only report of what is inside an iOS app: Info.plist,
  entitlements per Mach-O, the provisioning profile summary, icons, the launch screen and frameworks. See
  `specs/001-inspect/` in the repository.

Licence: AGPL-3.0, like the rest of the repository.
