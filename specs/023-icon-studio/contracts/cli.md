# CLI contract: `xcross icons`

## `xcross icons check [--json] [--project <dir>]`

Text: the set, one line per slot (`✓`/`✗`/`!`, role, size, file, status), the placement line, then issues (errors
first) with hints. Exit 1 when `errors > 0` (`[icons.check_failed]`).

```json
{"v":1,"type":"icons_check",
 "set":"AppIcon","path":"<project>/ios/Runner/Assets.xcassets/AppIcon.appiconset",
 "style":"all-sizes",               // or "single-size", or null without a set
 "source":"Icon-App-1024x1024@1x.png", // the image placement is measured on
 "slots":[{"role":"notification","label":"Notification","idiom":"iphone","points":20,"scale":2,
           "pixels":40,"file":"Icon-App-20x20@2x.png","status":"ok","actual":null,"required":false}],
 "placement":{"background":"#FFFFFF","box":[0.18,0.2,0.64,0.6],"offset":[0.0,0.0],
              "outsideMask":0.0,"prerounded":false,"transparent":false,"fullBleed":false},
 "issues":[{"code":"icons.alpha","severity":"error","message":"…","hint":"…","file":"…"}],
 "errors":1,"warnings":0}
```

`status`: `ok`, `missing`, `wrong_size` (`actual`: `"100x100"`), `unreadable`. `box`/`offset` are fractions of the
side (left, top, width, height; dx, dy: positive = right, down). `placement` is null when no image could be read.

Codes: `icons.no_set`, `icons.contents_invalid`, `icons.missing`, `icons.wrong_size`, `icons.unreadable`,
`icons.alpha`, `icons.prerounded`, `icons.clipped`, `icons.off_center`, `icons.logo_small`, `icons.variants`
(info), `icons.check_failed`.

## `xcross icons generate <image.png> [--background auto|#RRGGBB] [--padding <0–30>] [--output <dir>] [--json] [--project <dir>]`

Writes the 15 PNG files and `Contents.json` of the Flutter template set (19 entries; files shared by iPhone and iPad
entries of the same pixel size). Without `--output`: into the project's set (created as `AppIcon.appiconset` when
none exists), after copying the old one to `.xcross/icon-backups/<yyyyMMdd-HHmmss>/`.

```json
{"v":1,"type":"icons_generate","path":"…/AppIcon.appiconset","written":["Icon-App-20x20@1x.png","…"],
 "backup":"…/.xcross/icon-backups/20261103-104500/AppIcon.appiconset","background":"#0A84FF","padding":12,
 "upscaled":false,"check":{…icons_check…}}
```

Errors: `icons.source_unreadable` (not a PNG, unreadable), `--padding` outside 0–30 and a malformed `--background`
are usage errors. Warnings: `icons.upscaled`.
