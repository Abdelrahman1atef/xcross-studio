# Device check: 003 (to run on the iPhone X, iOS 16.7.16)

Prerequisites: `xcross auth` done; a Flutter project whose `ios/Runner/Runner.entitlements` declares
`aps-environment` (push needs a **paid** Apple Developer team; a free team gets Apple's capability error).

| # | AC | Command | Expected | Result |
|---|---|---|---|---|
| 1 | AC-003-1 | `xcross flutter build ipa` then `xcross inspect build/xcross-ios/<name>.ipa --json` | `bundle.xcrossPrivateKeys.XCrossEntitlements: true` | ⏳ |
| 2 | AC-003-4 | `xcross flutter run --release`, then `xcross app info <bundle-id>` | `✔ push entitlement` (`aps-environment`) | ⏳ |
| 3 | AC-003-4 | same with `associated-domains` declared | `✔ associated domains` | ⏳ |
| 4 | AC-003-3 | break the XML in `Runner.entitlements`, build | `warning: [build.entitlements_unreadable] …`; build continues | ⏳ |
| 5 | push e2e | `xcross logs --app <exe> --preset push`, send a test push | diagnosis says registered / delivered | ⏳ |
