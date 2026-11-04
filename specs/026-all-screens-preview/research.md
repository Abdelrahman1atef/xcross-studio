# Research: a full-screen iOS splash (User Story 4)

**Status**: open. No push or CI run has happened, and nothing is promised until the device result (AC-026-24).

## Question

Can xcross give iOS a full-screen picture or gradient as its launch screen, without a Mac at the user's end?

## What is known

Today xcross cannot compile a storyboard, so it turns `LaunchScreen.storyboard` into a `UILaunchScreen` dictionary:
one colour plus one centred image.

| Finding | Source | Confidence |
|---------|--------|------------|
| Large images under `UILaunchScreen` scale "without any recognisable logic" | [Apple forum 763571](https://developer.apple.com/forums/thread/763571) | Two developers' reports |
| A 300×300 image appeared centred on first install, then stretched to fill the screen on later launches | [Apple forum 671370](https://developer.apple.com/forums/thread/671370) | Reports, no confirmed cause |
| Apple support told one developer to use a storyboard instead | Forum 763571 | Second-hand |
| A 2200×3300 PNG went black in a launch storyboard, while a small one worked; a commenter put the limit near 5.6 to 6.4 megapixels | [Apple forum 675488](https://developer.apple.com/forums/thread/675488), [760108](https://developer.apple.com/forums/thread/760108) | Reports; the limit is unverified |
| xcross already copies a prebuilt `LaunchScreen.storyboardc` found next to the storyboard, and keeps `UILaunchStoryboardName` | `ios_bundle_resources.dart:75-118`, `plist_storyboard_policy.dart` | Read in the code; not run with a real one |
| Flutter's engine loads the storyboard named in the plist as its own splash until the first frame | `SplashScreenManager.swift:56-59` | Read in the engine source; a real storyboard could also close the black gap before the first frame |

## What a real iPhone showed (2026-11-04, iPhone X, iOS 16.7.16)

Read from the app's own container, `Library/SplashBoard/Snapshots/`: iOS writes these launch images when an install ends.
They are `AAPL` textures: LZFSE-compressed ASTC 4×4, where a flat block holds its colour directly.

| Installed | What iOS drew | What that shows |
|-----------|---------------|-----------------|
| Fresh install (container new at 22:37:53), catalog with a flattened 371×392 pt image | The removed May image: 768 px, transparent, over a black square, matching it 96.84% against 61% or less for every later image. Background the system default, black in dark mode, though the dark colour is white | iOS drew a file this build does not hold |
| The same with both assets renamed by content | Nothing: plain system background, no logo | The new names are not in what iOS reads |
| After a restart, the flattened image, colour record with no element or part | Light: the current logo on white, no square. Dark: a white square on black | The restart let iOS read the new catalog. iOS still found no colour |
| Colour key corrected, body version 0, no restart | The same as the row above | iOS still read the older catalog |
| After a restart, colour key corrected, body version 0 | No launch images written at install: 0 in three installs, against 4 for every other row | iOS read this record and produced nothing. Why is not known |
| After a restart, colour record equal to `actool`'s | Four launch images at install: the logo on white, no square, in every one | iOS found the colour |

A long-lived iOS process keeps the older catalog for an app until the phone restarts: three restarts each brought in the
catalog that installs before them had not, and a fresh install after deleting the app did not. So a restart is what refreshes
a splash; whether a delete is also needed is not known. The older catalog here had the May image and no `LaunchBackground`.

The colour record was checked against real `actool` output, the `Assets.car` of two public Mac apps built with Xcode. Only
three fields differed once the key was right: body version, colour space in the header, and bitmap count.

Not all of `Snapshots/` is the launch screen. `<bundle> - {DEFAULT GROUP}` holds launch images. `sceneID:<bundle>-default`
holds what the app last showed, written when it leaves the screen and gone after a force-quit. Those can be solid black.

The test design has the same colour in light and dark, so a dark colour that differs from the light one has not been seen
on a device: device-check row 3.

Testing from the home screen needs a release build: a Flutter debug build crashes there without a debugger.

Renaming was rejected: while iOS holds an older catalog, a new name comes out blank, which on a user's phone after an update
is worse than an older logo.

## Decisions so far

### 1. Not an oversized image under `UILaunchScreen`

Rejected on the reports above: its scaling cannot be relied on.

### 2. Try one prebuilt storyboard, compiled once

A compiled storyboard refers to images and colours by name, so one compiled file can serve every app, with the app's
`Assets.car` holding the actual images:

```text
view: background colour "LaunchBackground"
  image view: "LaunchFullScreen", aspect fill, pinned to all edges
  image view: "LaunchImage", centred at its own size
```

It has to be compiled by `ibtool` on a Mac once, on a `macos-15` GitHub runner, as `integration.yml` already uses.

### 3. Constitution II: to settle before anything is committed

Principle II forbids shipping "any Apple SDK, Xcode archive, DeveloperDiskImage, or other Apple-licensed binary". A nib
compiled from this project's own storyboard should hold only this project's layout and references to UIKit class names.
It is output, not an Apple library, the same as any app's nib. But it is produced by Apple's tool, so:

1. Inspect the compiled files before committing them, to confirm they hold nothing of Apple's beyond class names.
2. Record that here.
3. Prefer a small Dart writer for the nib format if inspection leaves any doubt: the format is simple and undocumented,
   and a writer would remove the Mac from the process entirely.

The Constitution's required legal review before 1.0 should see this item.

## Steps

1. **Ask the user first**: compiling needs a push and a CI run.
2. Compile the template on the runner; inspect the output (Decision 3).
3. Put it in a test project as `ios/Runner/Base.lproj/LaunchScreen.storyboardc`: no xcross change is needed for this.
4. On the iPhone: picture, gradient, transparent logo over it, light and dark, and several cold starts.
5. Record the result in `device-check.md` and here, then do AC-026-25 or AC-026-26.

If it works, a real storyboard could replace the plist path everywhere, which may also remove the need to flatten the
launch image. That is decided from the results.
