# ZenLink code in xcross

`xcross-screen` (the iPhone screen helper, spec 048) reuses code from **ZenLink** by Zenvy Zenshiro:
https://github.com/zenvyzenshiro/zenlink, licensed **GPL-3.0-only** (`LICENSE-ZenLink-GPL-3.0`).
GPL-3.0 code may be combined with this AGPL-3.0 project (GPLv3 section 13). It is used only in the
engine, never in closed-source software.

| Folder | From ZenLink v2.5.17 (commit `b41ecb04bce27e784c180ca2ad725c948b9b8926`, 2026-11-20) | Changes |
|---|---|---|
| `zenlink-apple/` | `ZenshiroDev/crates/zenlink-apple/` | `Cargo.toml`: workspace keys written out. `examples/` left out. Source unchanged. |
| `zenlink-core/` | two functions of `ZenshiroDev/crates/zenlink-core/src/lib.rs` | Only `quick_ack` (unchanged) and `local_data_dir` (now `%LOCALAPPDATA%\xcross\screen`). |
| `zenlink-drivers/tools/usb_filter.ps1` | `ZenshiroDev/tooling/windows/tools/usb_filter.ps1` | unchanged (run elevated and hidden by `xcross-screen driver enable/restore`; it keeps its backups in `%ProgramData%\ZenLink\drivers\backups`) |
| `zenlink-drivers/drivers/libusb-win32/amd64/` | `ZenshiroDev/resources/windows/drivers/libusb-win32/amd64/` | unchanged signed binaries of libusb-win32 1.2.6.0 (driver GPL, library LGPL; source: https://sourceforge.net/projects/libusb-win32/). Folder layout matches what the script expects (`..\drivers\libusb-win32` from `tools`). |

ZenLink itself builds on: `idevice` (MIT, https://github.com/jkcoxson/idevice), quicktime_video_hack
(MIT, Daniel Paulus) as the QuickTime protocol reference, and the libwdi/Zadig driver-package approach
(LGPL/GPL, Pete Batard).

**Updating:** copy the same folders from a newer reviewed ZenLink release, keep this table and the
changes column current, and re-run the helper's tests and the iPhone device checks.
