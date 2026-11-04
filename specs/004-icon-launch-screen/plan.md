# Plan: App icon and launch screen without a Mac

**Branch**: `004-icon-launch-screen` | **Spec**: [spec.md](spec.md)

## Summary

A pure-Dart port of [xtool-org/AssetKit](https://github.com/xtool-org/AssetKit) (MIT; GitHub shows NOASSERTION only
because its LICENSE appends a BSD-3 notice for Apple's LZFSE) lives in `packages/studio_ext`:

- `lib/shared/assets/asset_catalog_compiler.dart` (public): `AssetCatalogCompiler.compile(catalogs, deploymentTarget,
  extraColors)` → `CompiledAssetCatalog` (`car`, icon Info.plist keys, loose PNGs, image/colour names, issues);
  `uniformImageColor` for single-colour background images.
- `lib/shared/assets/launch_storyboard.dart` (public): `LaunchStoryboard.parse` → `LaunchScreenSpec` (background colour
  or colour-set name, centred image, full-screen image, approximations). Uses `package:xml` (already in the lock).
- `lib/src/shared/assets/` (`@internal`): `asset_byte_writer`, `bom_writer` (BOM container + single-leaf trees),
  `rendition` (model, KEYFORMAT, rendition keys, CRC32 name ids), `csi_writer` (CSI header, TVL, MLEC, DWAR, COLR),
  `car_writer` (CARHEADER, FACETKEYS, APPEARANCEKEYS, KEYFORMAT, EXTENDED_METADATA, BITMAPKEYS), `catalog_loader`,
  `app_icon_plist`, `png_codec` (PNG decoder/encoder, JPEG size).

xcross seam: `X/shared/flutter/build/flutter_asset_catalogs.dart` (new) compiles the catalogs the resource stager
skips, writes `Assets.car` + loose icons, turns the launch storyboard into `UILaunchScreen`, maps issues to the new
`build.*` codes and merges the keys into Info.plist. `FlutterBundleAssembler` calls it between resource staging and
the skipped-resource report (`// studio: 004` hunks); handled resources are no longer reported as skipped.

## Deviations from AssetKit (documented in code)

| Area | AssetKit | This port | Why |
|---|---|---|---|
| Bitmap compression | LZFSE (`bvx2`, vendored C encoder) | LZFSE uncompressed blocks (`bvx-` … `bvx$`), still type 3 | no C port; `bvx-` is what Apple's encoder emits for incompressible data, every decoder reads it |
| TVL 1007 bytes per row | `width*4` rounded up to 16, rows unpadded | `width*4` | value and data agree for widths like 29, 58, 87, 167 |
| Duplicate rendition keys | all inserted | first kept; app icons sorted largest first | one key per (idiom, scale); the home-screen size wins |
| Named colour record | identifier only in the key, scale 100, body version 0 | as `actool` writes it, read byte for byte from real catalogs (2026-11-04): key element 85, part 217, scale 1; record scale 0, colour space 0 in the header, bitmap count 1, tag `RLOC`, body version 1 | iOS never found a colour written the other way, so the launch background was always the system default |
| `ios-marketing` icon | compiled | compiled (skipped until 2026-11-04) | not used on device, but App Store Connect reads it from the catalog and rejected the upload without it (error 91111) |
| iPad loose icons | `AppIcon76x76@2x.png` | `AppIcon76x76@2x~ipad.png` | actool naming; avoids iPhone/iPad name clashes |
| Single-size 1024 icon | rejected (no scale) | scaled to iPhone/iPad slots | Xcode 14+ catalogs |
| Errors | throw for the whole catalog | per-asset issue, asset skipped | a build must not fail on one bad asset |
| SVG | rasterised via `rsvg-convert` | skipped with `build.asset_unsupported` | no host tool dependency |
| Trees > ~500 entries | leaf overflows its page | page size doubled | keeps leaf ≤ declared page |

## Constitution Check

| Principle | Status |
|---|---|
| I | ✅ compiler in `studio_ext`; xcross gets one new file plus marked assembler/diagnostics hunks |
| II | ✅ no Apple binary used or shipped; actool reference bytes are not committed (opt-in parity test reads a local AssetKit checkout) |
| III | ✅ four new coded warnings; compiler failure falls back to the existing code |
| IV | ✅ no new output channel |
| V | ✅ pure Dart; tests run on Windows (seam test) and every CI OS |
| VI | ✅ AC ids in test names; device rows in `device-check.md` |
| VII | ⚠ a port, not a dependency (AssetKit is Swift); MIT notice in `packages/studio_ext/THIRD_PARTY_NOTICES.md` |
| VIII | ✅ AGPL-compatible MIT code, notice kept |

## Tests

| AC | Test |
|---|---|
| AC-004-1 | `SXT/shared/assets/car_format_test.dart` (BOM, keys, CSI, CAR blocks), `asset_catalog_compiler_test.dart` (Flutter catalog), `assetkit_reference_test.dart` (opt-in, JPEG CSI byte parity with actool), `XT/flutter/build/flutter_asset_catalogs_test.dart` (bundle + Info.plist + `xcross inspect`) |
| AC-004-2 | `launch_storyboard_test.dart`, `flutter_asset_catalogs_test.dart` |
| AC-004-3 | `asset_catalog_compiler_test.dart`, `png_codec_test.dart`, `flutter_asset_catalogs_test.dart` |
| AC-004-4 | `launch_storyboard_test.dart`, `flutter_asset_catalogs_test.dart` |
| AC-004-5 | `asset_catalog_compiler_test.dart` (single-size icon) |
| AC-004-7 | covered by the seam's `on Object` fallback (no fault injection test) |
| device | `device-check.md` |
