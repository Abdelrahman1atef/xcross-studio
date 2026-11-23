# FAQ

[← xcross README](../../README.md) · [All guides](README.md)

<details>
<summary><b>How does it build release/AOT?</b></summary>

Flutter publishes its iOS AOT compiler (`gen_snapshot`) for macOS only. On macOS xcross uses that compiler. On Linux and Windows it downloads a build of the same compiler, made from the Dart revision the Flutter release pins: first from [xcross-compilers](https://github.com/Abdelrahman1atef/xcross-compilers), then from [xcross_gen_snapshot](https://github.com/arxdeus/xcross_gen_snapshot), and for a patch release without one, the compiler of its line built from the same Dart revision ([details](flutter-versions.md#flutter-versions-and-ios-compilers)). Each published compiler produced output byte-identical to Flutter's own on a real `flutter build ios` before it was released. xcross checks the engine revision and both digests before it uses a download. To use a compiler of your own, set `ios_gen_snapshot` in the xcross config. Simulators stay debug-only, because Flutter's simulator engines are JIT-only.

A downloaded compiler is cached per engine revision. Once a day a build checks the release again (a few seconds at most, and never failing offline), so a compiler republished for the same Flutter version replaces the cached one. `xcross flutter doctor` reports for profile and release whether a compiler is shipped, cached, pinned, published, or missing. `xcross flutter precache` fetches it ahead of time. `xcross cache prune` removes engine artifacts and compilers left behind by Flutter versions you no longer use; Kotlin/Native in `~/.konan` is shared with Gradle and never pruned. A release manifest written for a newer xcross asks you to run `xcross update`.

On Windows, output byte-identical to a macOS build needs an LF checkout of the Flutter SDK (`git config --global core.autocrlf false` before cloning). A CRLF checkout still produces working snapshots, but not byte-identical ones, because the source offsets they record shift.
</details>

<details>
<summary><b>What does <code>xcross tunnel</code> do, and why does it need elevation?</b></summary>

It mounts the Developer Disk Image and starts the `pymobiledevice3` RSD tunnel - the encrypted QUIC/TUN tunnel iOS 17+ requires for developer services. Creating the TUN interface needs an Administrator PowerShell on Windows or root on Linux. Run it once per device reconnect.
</details>

<details>
<summary><b>How does <code>--wifi</code> (wireless run) work?</b></summary>

Wireless devices are discovered and reached through `pymobiledevice3 remote tunneld`, which finds the phone over mDNS (RemotePairing) and builds the RSD tunnel - usbmuxd is not involved, since the open-source usbmuxd on Linux and Windows never sees network devices. Requirements: iOS 17+, Developer Mode enabled, a one-time pairing with the host, and the phone unlocked on the same subnet (mDNS/UDP 5353 does not cross NAT - use bridged networking in a VM). `xcross tunnel --wifi` does the whole wireless setup with no cable: it advertises this host for device-initiated pairing (iOS 27+; the phone lists it as `xcross-<hostname>` under Settings > Privacy and Security > Developer Mode > Paired Devices > Other Devices and the 6-digit code prints in the terminal), builds the tunnel, and mounts the DDI through it. `xcross flutter run --wifi` also sets pairing up itself when needed (over the cable when USB is attached, via the same advertisement when not) and starts tunneld on demand; the tunnel needs root/Administrator for the TUN interface.
</details>

<details>
<summary><b>Does it support Compose Multiplatform?</b></summary>

Yes. Use `xcross compose setup`, then `xcross compose build` or `xcross compose run -d <device>` from a KMP project. Windows x64 and Linux x64 are supported; Linux arm64 is blocked by upstream Kotlin/Native host artifacts.
</details>

<details>
<summary><b>Is my Apple password stored anywhere?</b></summary>

No. `xcross auth` performs the login handshake locally and persists only the resulting Developer Services session token.
</details>

<details>
<summary><b>Why does an App Store Connect API key have fewer capabilities than an Apple ID?</b></summary>

Only for App Groups, and the cause is Apple's. The public App Store Connect API has no App Groups resource at all: its OpenAPI specification declares 966 paths and none of them mentions one, so a key cannot create a group or attach it to an App ID. The older protocol Xcode itself speaks does expose them, and that is what an Apple ID session uses.

So the documented, officially supported credential is the less capable one here, and the undocumented path is the complete one, with the stability caveat that implies.

It only matters if your app ships a share or action extension. A key still issues profiles that carry a group attached by other means, so attach one once in Xcode or at developer.apple.com and pass `XCROSS_APP_GROUP=group.your.id`. Everything else works identically. See [docs/app-extensions.md](../app-extensions.md).
</details>

<details>
<summary><b>Builds fail with "this SDK is not supported by the compiler"</b></summary>

`xcross sdk install` patches the Darwin SDK against the Swift toolchain that was selected at the time, and the SDK's Swift module interfaces can only be compiled by that toolchain. Changing the active Swift afterwards (`swiftly use`, `mise use`, or a distro upgrade) invalidates the pairing, and Swift then reports the mismatch once per importing source file:

```
error: failed to build module 'UIKit'; this SDK is not supported by the compiler
(the SDK is built with 'Apple Swift version 6.3.2 …', while this compiler is
'Swift version 6.3.2 (swift-6.3.2-RELEASE)'). Please select a toolchain which
matches the SDK.
```

xcross records the toolchain each SDK was installed with and stops the build with this explanation before Swift gets there. Either select the Swift toolchain the SDK was installed with, or reinstall the SDK against the current one:

```sh
xcross sdk install ~/Downloads/Xcode.xip
```

Note that the two versions in Swift's own message can look identical: the mismatch is between compiler *builds* (an Apple/vendor build vs a swift.org release), not just version numbers.
</details>
