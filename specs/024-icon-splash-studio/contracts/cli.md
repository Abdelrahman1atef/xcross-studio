# CLI contract: `xcross icons generate` (extended), `icons preview`, `xcross splash`

## `xcross icons generate <image.png>`

Existing: `--background auto|#RRGGBB`, `--padding`, `--output`, `--json`, `--project`.

| Option | Values |
|---|---|
| `--padding` | `n` or `top,right,bottom,left`, each 0–45 (% of the side) |
| `--trim` | remove transparent or one-colour borders first |
| `--foreground` | `#RRGGBB` (recolour, keeping transparency) |
| `--effect` | `none`, `drop-shadow`, `cast-shadow`, `score` |
| `--background-type` | `color`, `gradient`, `mesh`, `image` |
| `--background2`, `--background3`, `--background4` | further colours |
| `--gradient-angle` | degrees, default 135 |
| `--background-image` | PNG |
| `--texture` | `none`, `argyle`, `concentric`, `contour`, `coral`, `fabric`, `halftone`, `maze`, `mosaic`, `polka`, `stipple`, `waves` |
| `--badge-image` | PNG, drawn across the bottom |
| `--targets` | comma list: `ios`, `android`, `notification`, `web`, `macos`, `watchos`, `tvos`, `android-tv`, `play-banner`, or `all` |
| `--name` | Android and notification file name, default `ic_launcher` |
| `--shape` | `square`, `squircle`, `circle` (Android) |
| `--themed` | add the Android monochrome layer |
| `--zip` | write one archive; nothing in the project changes |
| `--config` | read defaults from `xcross_assets.json`; the image may then be left out |
| `--save-config` | store these settings in the assets file |

Default `--targets`: `ios`, as in feature 023. `all` means the project's folders (`ios`, `android`, `web`, `macos`).

JSON: `{"v":1,"type":"icons_generate","path":…,"written":[…],"backup":…,"background":…,"padding":…,
"targets":{"ios":{"path":…,"files":n},…},"issues":[…],"check":…}`. Feature 023's fields keep their meaning.

Codes: `icons.source_unreadable`, `icons.no_project`, `icons.target_missing`, `icons.notification_no_shape`,
`icons.tint_opaque`, `icons.upscaled`.

## `xcross icons preview --serve`

`--output <dir>` is required. Reads one JSON design per line on stdin; prints `{"v":1,"type":"icons_preview","seq":n,
"paths":{"full":…,"adaptive":…,"maskable":…,"silhouette":…,"banner":…}}` or `{"v":1,"type":"icons_preview","seq":n,
"error":…}`. Ends when stdin closes. Design keys are the option names above, plus `seq`, `source` and, for a splash,
`kind: "splash"`.

## `xcross splash generate <logo.png>`

Options as in AC-024-6, plus `--config`, `--save-config`, `--zip`. JSON: `{"v":1,"type":"splash_generate","written":[…],
"backup":…,"platforms":[…],"issues":[…],"check":…}`.

## `xcross splash check [--json] [--project <dir>]`

JSON: `{"v":1,"type":"splash_check","ios":{"background":…,"darkBackground":…,"logo":…,"logoSize":[w,h],"dark":bool},
"android":{"background":…,"darkBackground":…,"logo":…,"android12":bool},"issues":[…],"errors":n,"warnings":n}`. Exit 1
with errors.

Codes: `splash.missing`, `splash.logo_missing`, `splash.logo_too_large`, `splash.android12_missing`,
`splash.android12_clipped`, `splash.low_contrast`, `splash.not_referenced`, `splash.other_tool`.

## `xcross_assets.json`

`{"version":1,"icons":{…generate options…},"splash":{…generate options…}}`, paths relative to the project.
