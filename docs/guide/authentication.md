# Signing in to Apple

[← xcross README](../../README.md) · [All guides](README.md)

xcross talks to Apple's Developer Services directly. Two options:

|  | Apple ID | App Store Connect API key |
| --- | --- | --- |
| Apple account needed | free account works | paid Developer Program |
| Interactive login | password + 2FA once | none, good for CI |
| Protocol | the one Xcode speaks, undocumented | official and documented |
| Build, sign, install, run | yes | yes |
| **App Groups** (share extensions) | **created and attached automatically** | cannot be created; use one you attached yourself, see [app extensions](../app-extensions.md#app-store-connect-api-keys) |

The App Groups row is the only functional difference, and it is Apple's doing
rather than xcross's: the public App Store Connect API has no App Groups
resource at all, while the older protocol Xcode itself uses does. It only
matters if your app ships a share or action extension that hands data back to
the app.

## Apple ID (free account works)

```sh
xcross auth --apple-id you@example.com
```

The command prompts for your password and 2FA code, then stores **only** the resulting Developer Services session - never your password.

> [!WARNING]
> Do not use your primary Apple ID. xcross signs in through a non-standard path for non-macOS systems, and Apple may treat that as unusual activity: an account used with xcross can end up locked, and an appeal may not reinstate it. Creating a throwaway Apple ID takes a minute and a free account is all you need, which keeps that a minor inconvenience rather than losing your purchases, iCloud data, and devices.

Apple's GrandSlam login expects **Mac**-matching machine attestation (anisette).
By default `xcross auth` uses a remote [Omnisette](https://github.com/SideStore/omnisette-server)
**v3** server (`https://mac-ani.jkcoxson.com`) that synthesizes those headers:

```sh
xcross auth --apple-id you@example.com
# override the default server:
xcross auth --apple-id you@example.com --anisette-url https://example.test
# or:
XCROSS_ANISETTE_URL=https://example.test xcross auth --apple-id you@example.com
```

Pick any Mac Omnisette server from the
[public list](https://xcross.sh/docs/authentication/#remote-anisette), or
[self-host](https://github.com/SideStore/omnisette-server). The URL is stored
with the session so later signing keeps using it; set `XCROSS_ANISETTE_URL`
again to point at a different server.

`--adi-library-dir` is a legacy opt-in to local Android ADI libraries
(`libCoreADI.so`, `libstoreservicescore.so`). Apple currently rejects that
identity (`-80046`); prefer the Omnisette default.

> [!WARNING]
> A public Omnisette server is a third party: the operator sees your IP and
> login/signing traffic and holds the device identity your account is attested
> against. Prefer a self-hosted server, and use a secondary Apple ID.

## App Store Connect API key

```sh
xcross auth --issuer-id <uuid> --key-id <id> --private-key /path/to/AuthKey.p8
```

Non-interactive, so this is the one to use on CI. It provisions everything
except App Groups, which Apple's public API cannot manage at all. If your app
has a share extension, attach the group to your App IDs once (in Xcode or at
developer.apple.com) and point xcross at it:

```sh
XCROSS_APP_GROUP=group.com.example.Shared xcross flutter run
```

See [iOS app extensions](../app-extensions.md) for the details.

App Store Connect has two kinds of key. A **Team key** (Users and Access →
Integrations → Team Keys, role Admin or App Manager) is the one that signs and
installs. An **Individual key** (Integrations → Individual Keys) has no Issuer
ID: leave out `--issuer-id`, or pass one anyway and xcross notices Apple only
accepts the key as individual and saves it that way.

```sh
xcross auth --key-id <id> --private-key /path/to/ApiKey_<id>.p8
```

Apple lets individual keys read App Store Connect but not manage devices,
certificates, bundle IDs or profiles, so `xcross auth` and `xcross flutter
doctor` warn that installing on an iPhone needs a Team key or your Apple ID.

## Working offline

Apple is only needed to provision: the first run of an app on a device, or
when something about it changes. After that, `xcross flutter run` keeps working
without a network. When Apple cannot be reached (or the saved Apple ID session
has expired), xcross signs with the certificate and provisioning profile the
last online run cached, prints a warning, and installs as usual.

```sh
XCROSS_OFFLINE=1 xcross flutter run   # skip Apple entirely, even when online
```

Offline signing still needs, for that app and device:

- one earlier online run, so a profile is cached;
- a profile that lists the device and has not expired (free accounts: 7 days);
- no new extension, capability, or App Group since then.

If any of those is missing, xcross says which and asks you to reconnect once.

## Sign out

```sh
xcross auth clean
```

Deletes the saved App Store Connect key, the Apple ID session and its machine attestation state, and every certificate, private key, and provisioning profile xcross minted. The downloaded ADI libraries stay - they are architecture-specific binaries that identify no account.
