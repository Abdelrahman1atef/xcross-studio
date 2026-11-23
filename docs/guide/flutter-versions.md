# Flutter versions and iOS compilers

[← xcross README](../../README.md) · [All guides](README.md)

| Build | Flutter versions |
|---|---|
| **Debug** (`xcross flutter run`, hot reload) | Any Flutter version xcross supports: debug builds need no extra compiler |
| **Profile and release** (`--profile`, `--release`, App Store) | Every Flutter version with an iOS compiler for your host (below) |

Flutter publishes its iOS AOT compiler (`gen_snapshot`) for macOS only, and each compiler fits exactly one Flutter version. On Windows and Linux, xcross looks for the compiler of your Flutter version in this order:

1. **[xcross-compilers](https://github.com/Abdelrahman1atef/xcross-compilers/releases)**: built for every Flutter stable release, newest first, for `windows-x64`, `windows-arm64`, `linux-x64` and `linux-arm64`, release and profile. A compiler is published only after it compiled a real `flutter build ios` app to an `App` and `app.o` byte-identical to what Flutter's official compiler wrote on a Mac. New Flutter releases are picked up automatically.
2. **[xcross_gen_snapshot](https://github.com/arxdeus/xcross_gen_snapshot/releases)**, the upstream project's compilers.
3. **The same Dart revision.** A patch release with no compiler of its own (for example 3.47.7) uses the one of its line built from the same Dart revision: the compiler depends only on the Dart revision, so they are byte-identical. It is checked like any download, and its `--version` must name your SDK's Dart version.

Every download is checked against its release's SHA-256 digests (archive and executable) before it runs, and cached per engine revision.

```sh
xcross flutter doctor        # says, for profile and release, where the compiler comes from (or that none exists)
xcross flutter sdk list      # the Flutter used for iOS builds, and whether it has a compiler
xcross flutter sdk auto      # no compiler for yours? install the nearest Flutter that has one, for iOS builds only
xcross flutter sdk install 3.47.8 && xcross flutter sdk use 3.47.8   # or pick one yourself
xcross flutter sdk reset     # back to your own Flutter
```

Your own Flutter installation is never changed: iOS builds use the one xcross installed under `<config>/xcross/flutter-sdks/`. A compiler of your own can be pinned with `ios_gen_snapshot` in the [configuration](configuration.md#configuration).
