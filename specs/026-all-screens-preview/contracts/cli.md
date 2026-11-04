# CLI contract: feature 026

## `xcross auth status [--json]`

Reads saved files only; asks Apple nothing. Exit 0, also when nothing is saved. Takes no other option.

```json
{
  "v": 1,
  "type": "auth_status",
  "deviceBuilds": "apple-id | api-key | null",
  "appStoreBuilds": "api-key | null",
  "appleId": {
    "email": "…",
    "teamId": "…",
    "anisetteUrl": "… | null",
    "expires": "2099-01-02T00:00:00.000Z",
    "expired": false
  },
  "apiKey": {
    "keyType": "team | individual",
    "issuerId": "… | null",
    "keyId": "…",
    "privateKeyPath": "…",
    "privateKeyFound": true
  }
}
```

`appleId` and `apiKey` are each `null` when nothing is saved, or `{"problem": "…"}` when what is saved cannot be read.
`--json` is only for `status`: `xcross auth --json` and `xcross auth clean --json` fail.

## `xcross splash generate`: new options

All are also read from and saved to `xcross_assets.json`, under `splash`.

| Option | Range | Default | Effect |
|--------|-------|---------|--------|
| `--ipad-logo-width` | 16–1024 points | none | Adds `LaunchImage-iPad@2x.png` with idiom `ipad` (and a dark one); iPhones keep the universal images |
| `--android-logo-width` | 16–1024 dp | `--logo-width` | Android 11 and older |
| `--android12-icon-width` | 16–1024 dp | `--logo-width`, kept inside the circle | Android 12 and newer, used as it is; the app's slider stops at 288, the canvas |
| `--android12-icon-background` | `#RRGGBB` | none | `windowSplashScreenIconBackgroundColor`; the icon becomes a 240 dp canvas through a 160 dp circle |
| `--dark-android12-icon-background` | `#RRGGBB` | light value | The same in `values-night-v31` |
| `--branding-width` | 16–1024 | 180 | Android and iOS |
| `--branding-bottom` | 0–500 dp | 32 | Android 11 and older only |

JSON adds `"removed": […]`: files of a leftover `LaunchBackground.imageset`, removed after a backup. The text report
says that iOS keeps showing the splash it saved.

## `xcross splash check`: new codes

- `splash.name_clash` (warning): an image set has the background colour set's name.
- `splash.branding_clipped` (warning): the launch image is taller than the shortest supported iPhone (568 points).

## `xcross splash generate`: changed meanings and new issues

- `--padding` makes the logo smaller inside its width. It used to add space around a centred image, which could not show.
- `--margin` moves the logo by half the difference between opposite sides, now also on Android 12.
- `splash.margin_no_effect` (warning): equal margins cancel out.
- `splash.android12_clipped` (warning) also covers a chosen `--android12-icon-width` that falls outside the circle.

## `xcross icons preview --serve`

A request may add `"variants": […]`, naming what to draw; without it, everything is drawn. New splash variants:

| Variant | When | What |
|---------|------|------|
| `androidLogo`, `darkAndroidLogo` | branding or an Android width | The logo without branding, 2 px per dp |
| `ipadLogo`, `darkIpadLogo` | an iPad width | iPad's launch image, 2 px per point |
| `darkBranding` | a dark branding image | As given |
