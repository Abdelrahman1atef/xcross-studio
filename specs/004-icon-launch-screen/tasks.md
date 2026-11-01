# Tasks: App icon and launch screen without a Mac

S = `packages/studio_ext/lib`, SXT = `packages/studio_ext/test`, X = `packages/xcross/lib/src`,
XT = `packages/xcross/test`. Upstream hunks are marked `// studio: 004`.

## Phase 1: Compiler (port of AssetKit)

- [X] T001 `S/src/shared/assets/asset_byte_writer.dart`, `bom_writer.dart`: BOM container (512-byte header area, block
  index, variables in insertion order) and single-leaf trees (value block before key block, leaf padded to the page).
- [X] T002 `S/src/shared/assets/rendition.dart`: idiom/scale/gamut, rendition bodies, KEYFORMAT ids (CoreUI 970),
  18-byte rendition keys, CRC32 name identifiers.
- [X] T003 `S/src/shared/assets/csi_writer.dart`: CSI header (184 bytes), TVL 1001/1003/1004/1006/1007, MLEC with
  `bvx-` stored LZFSE frames, JPEG DWAR passthrough, COLR colours.
- [X] T004 `S/src/shared/assets/car_writer.dart`: CARHEADER, RENDITIONS, FACETKEYS, APPEARANCEKEYS, KEYFORMAT,
  EXTENDED_METADATA, BITMAPKEYS in actool order.
- [X] T005 `S/src/shared/assets/png_codec.dart`: PNG decoder (types 0/2/3/4/6, depths 1–16, filters, Adam7), PNG
  encoder, box resize, JPEG size.
- [X] T006 `S/src/shared/assets/catalog_loader.dart`, `app_icon_plist.dart`: Contents.json loading (namespaces,
  appearances, gamut), icon plist keys and loose names.
- [X] T007 `S/shared/assets/asset_catalog_compiler.dart` (public API, issues, extra colours, single-size icons,
  `uniformImageColor`), `S/shared/assets/launch_storyboard.dart`; `xml` dependency;
  `packages/studio_ext/THIRD_PARTY_NOTICES.md`.

## Phase 2: Integration

- [X] T008 `X/shared/diagnostics/xcross_diagnostics.dart`: `build.asset_unsupported`, `build.asset_invalid`,
  `build.launch_screen_approximated`, `build.launch_screen_unreadable`; new hint for `build.asset_catalog_skipped`.
- [X] T009 `X/shared/flutter/build/flutter_asset_catalogs.dart` and the assembler hunks (compile after staging, skip
  handled resources in the report, silence the launch storyboard removal, merge keys into Info.plist).

## Phase 3: Tests

- [X] T010 SXT: `car_format_test`, `png_codec_test`, `asset_catalog_compiler_test`, `launch_storyboard_test`,
  `assetkit_reference_test` (opt-in), support `png_builder`, `car_reader`, `catalog_fixture`.
- [X] T011 XT: `flutter/build/flutter_asset_catalogs_test.dart` (bundle files, Info.plist, `xcross inspect`).

## Phase 4: Polish

- [X] T012 CHANGELOG, ROADMAP, README, 002 diagnostics contract rows, `device-check.md`.
- [X] T013 Analyze, test, commit, push.
