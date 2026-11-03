// studio: 022 — the GitHub Actions workflow `xcross release ci` writes; the
// same text is docs/ci/github-testflight.yml (specs/022-studio-release-flow).
import 'package:meta/meta.dart';

/// The ubuntu-latest release workflow (AC-022-6).
@internal
abstract final class CiTemplate {
  /// Default output path, relative to the project.
  static const defaultPath = '.github/workflows/xcross-testflight.yml';

  static const githubTestflight = r'''
# XCross Studio: build, sign and upload a Flutter iOS app to App Store Connect (TestFlight) on ubuntu-latest,
# without a Mac. Written by `xcross release ci` (specs/022-studio-release-flow); the same steps as the reference
# macOS + Codemagic workflow (docs/release/reference-macos-workflow.yml).
#
# Required repository secrets:
#   APP_STORE_CONNECT_ISSUER_ID       Issuer ID (Users and Access > Integrations)
#   APP_STORE_CONNECT_KEY_IDENTIFIER  Key ID of a Team API key with the Admin or App Manager role
#   APP_STORE_CONNECT_PRIVATE_KEY     Full contents of AuthKey_<KEY_ID>.p8
#   CERTIFICATE_PRIVATE_KEY           RSA private key (PEM) of the Apple Distribution certificate (reused every run)
#   XCODE_XIP_URL                     A private download URL of YOUR OWN Xcode 26+ .xip (Apple's SDK licence: xcross
#                                     never downloads Apple material from anywhere else)
# Optional:
#   FIREBASE_OPTIONS_DART (secret)    Contents of lib/firebase_options.dart when it is gitignored
#   APP_STORE_APP_ID (variable)       Apple ID of the app, for --build-number auto without a bundle ID lookup
#   XCROSS_STUDIO_REF (variable)      Branch or tag of XCross Studio to build the CLI from (default: main)

name: iOS App Store Release (xcross)

on:
  workflow_dispatch:

concurrency:
  group: ios-app-store-release
  cancel-in-progress: false

jobs:
  release:
    name: Build and upload to App Store Connect
    runs-on: ubuntu-latest
    timeout-minutes: 120
    env:
      APP_STORE_APP_ID: ${{ vars.APP_STORE_APP_ID }}
      XCROSS_CERTIFICATE_PRIVATE_KEY: ${{ secrets.CERTIFICATE_PRIVATE_KEY }}
      HAS_FIREBASE_OPTIONS: ${{ secrets.FIREBASE_OPTIONS_DART != '' }}

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Write Firebase config
        if: env.HAS_FIREBASE_OPTIONS == 'true'
        env:
          FIREBASE_OPTIONS_DART: ${{ secrets.FIREBASE_OPTIONS_DART }}
        run: printf '%s\n' "$FIREBASE_OPTIONS_DART" > lib/firebase_options.dart

      - name: Setup Flutter SDK
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.47.0
          cache: true

      - name: Install the XCross Studio CLI
        run: |
          set -euo pipefail
          git clone --depth 1 --branch "${{ vars.XCROSS_STUDIO_REF || 'main' }}" \
            https://github.com/Abdelrahman1atef/xcross-studio.git "$RUNNER_TEMP/xcross-studio"
          (cd "$RUNNER_TEMP/xcross-studio" && ./install.sh --local)
          echo "$HOME/.local/bin" >> "$GITHUB_PATH"

      - name: Install Swift and LLVM
        run: xcross setup --yes

      - name: Restore the Darwin SDK
        id: sdk
        uses: actions/cache@v4
        with:
          path: ~/.config/xcross/swift-sdks
          # Put your Xcode version in .xcross-sdk-version to refresh the cache.
          key: darwin-sdk-${{ hashFiles('.xcross-sdk-version') }}

      - name: Install the Darwin SDK from your Xcode .xip
        if: steps.sdk.outputs.cache-hit != 'true'
        env:
          XCODE_XIP_URL: ${{ secrets.XCODE_XIP_URL }}
        run: |
          set -euo pipefail
          curl -fsSL "$XCODE_XIP_URL" -o "$RUNNER_TEMP/Xcode.xip"
          xcross sdk install "$RUNNER_TEMP/Xcode.xip"
          rm -f "$RUNNER_TEMP/Xcode.xip"

      - name: Sign in to App Store Connect
        env:
          ISSUER_ID: ${{ secrets.APP_STORE_CONNECT_ISSUER_ID }}
          KEY_ID: ${{ secrets.APP_STORE_CONNECT_KEY_IDENTIFIER }}
          PRIVATE_KEY: ${{ secrets.APP_STORE_CONNECT_PRIVATE_KEY }}
        run: |
          set -euo pipefail
          umask 077
          printf '%s\n' "$PRIVATE_KEY" > "$RUNNER_TEMP/AuthKey_$KEY_ID.p8"
          xcross auth --issuer-id "$ISSUER_ID" --key-id "$KEY_ID" --private-key "$RUNNER_TEMP/AuthKey_$KEY_ID.p8"

      - name: Check the toolchain
        run: xcross flutter doctor

      - name: Get dependencies
        run: flutter pub get

      - name: Quality gate (flutter analyze, flutter test)
        run: xcross release gate

      - name: Build, sign and archive for the App Store
        run: xcross flutter build --release --ipa --export-method app-store --build-number auto

      - name: Release check
        run: xcross release check

      - name: Keep the IPA, archive and release record
        uses: actions/upload-artifact@v4
        with:
          name: app-ios-${{ github.run_number }}
          path: |
            build/xcross-ios/ipa/*.ipa
            build/xcross-ios/archive/
            build/xcross-ios/release.json
          retention-days: 14

      - name: Upload to App Store Connect and wait for processing
        run: xcross publish --wait --timeout 60

      - name: Show TestFlight status
        if: always()
        run: xcross testflight status --limit 3
''';
}
