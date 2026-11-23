# Compose Multiplatform

[← xcross README](../../README.md) · [All guides](README.md)

`xcross compose` builds Kotlin Multiplatform iOS targets on Windows x64 and Linux x64 using the same private Darwin SDK, Swift, LLVM, and `xcross auth` signing flow as Flutter. Linux arm64 can run the CLI, but Compose iOS builds are limited by missing upstream Kotlin/Native host artifacts.

```sh
xcross setup
xcross sdk install /path/to/Xcode.xip
xcross compose setup
cd examples/compose_app        # or examples/kmp_swift_app
xcross compose doctor
xcross compose build
xcross compose run -d <device>
```

Projects with a Kotlin `ComposeUIViewController` entry or a SwiftUI `@main` host produce an `.app`. Framework-only KMP modules still build the iOS framework, but `xcross compose run` and `--ipa` are unavailable until the project has a runnable app entry. Physical-device launch requires iOS 17 or later.

Compose launches use native attached debugging to supervise the process after install. There is no Kotlin source DAP yet.

Compose has no in-place hot reload, and cannot have one the way Flutter does: Kotlin/Native compiles the app ahead of time to a Mach-O binary, and JetBrains' own [Compose Hot Reload](https://kotlinlang.org/docs/multiplatform/compose-hot-reload.html) works only on a JVM target, through JetBrains Runtime class redefinition. What xcross offers instead is a fast restart loop:

```bash
xcross compose run --watch   # press r to rebuild + reinstall + relaunch, q to quit
```

`r` rebuilds only when a watched source (`.kt`, `.kts`, `.toml`, `.properties`) actually changed, then reinstalls and relaunches while keeping the device, RSD tunnel, and console session warm. An unchanged `r` leaves the running app alone.

Rebuilds are dominated by the Kotlin/Native compile (~133s of a ~147s cycle on the Compose sample, since it is a whole-program AOT compile). xcross fingerprints the framework's inputs and compiler flags, so a build whose inputs did not change skips `konanc` entirely: **~145s → ~12s** on the sample.
