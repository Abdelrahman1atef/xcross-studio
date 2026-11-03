# CLI contract: `xcross appstore`

All subcommands accept `--app-id <Apple ID>` (else the project's bundle ID decides the app).

| Command | Effect | Output |
|---|---|---|
| `appstore app [--json]` | find the app record | text; JSON `{"v":1,"type":"appstore_app","found":true,"id","name","bundleId","sku","primaryLocale"}` or `{"found":false,"bundleId","name","sku","newAppUrl"}`; exit 1 when missing |
| `appstore version [<x.y.z>] [--create] [--json]` | editable version (create) | text; JSON `{"v":1,"type":"appstore_version","id","version","state","created"}` |
| `appstore metadata pull [--dir appstore/metadata] [--version x.y.z]` | folder ← App Store Connect | one line per file written |
| `appstore metadata push [--dir …] [--version x.y.z]` | App Store Connect ← folder | one line per change, or `Nothing to change.` |
| `appstore screenshots push [--dir appstore/screenshots] [--replace] [--version x.y.z]` | upload PNGs | one line per upload/skip; size errors before any upload |
| `appstore attach --build <n> [--version x.y.z]` | attach the build | `Attached build n to x.y.z` |
| `appstore submit [--version x.y.z] [--dry-run]` | review submission | blockers, then `Submitted x.y.z for review` / `Ready to submit` |
| `appstore status [--json]` | states | text; JSON `{"v":1,"type":"appstore_status","version","state","build","submissions":[{"id","state","submittedDate"}]}` |

Folder (R3): `metadata/<locale>/{name,subtitle,privacy_url,description,keywords,promotional_text,release_notes,
support_url,marketing_url}.txt`, `metadata/{copyright,primary_category,secondary_category}.txt`,
`metadata/age_rating.json`; `screenshots/<locale>/<display type>/*.png`.
