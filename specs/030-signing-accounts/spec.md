# Feature Specification: Switch between App Store Connect accounts

**Feature Branch**: `030-signing-accounts` (work lands on `codex/029-xcode-ide-workspace`) | **Created**: 2026-11-08 | **Status**: Implemented, not yet used on a second real account in the GUI

**Input**: A developer who works for more than one team (one App Store Connect API key per team) had to run
`xcross auth --issuer-id … --key-id … --private-key …` by hand each time, and the saved key is a single slot: signing in
for team B forgets team A. A build for team A then failed with "no app with this bundle ID" until the key was typed in
again. Chosen: the Studio remembers every API key that Apple accepted and switches with one click, through the CLI.

## Scope

- API-key accounts only. An Apple ID account needs the password again to sign in, which Studio never stores, so it
  is not listed.
- Signing and key storage stay with the CLI. "Use" runs `xcross auth --issuer-id … --key-id … --private-key <path>`;
  the CLI validates with Apple and leaves the saved key unchanged when it refuses.
- Kept per account: name, Key ID, Issuer ID (none for an individual key), the path of the `.p8`, a note and the last
  use. Never the key contents, never a password.

## Acceptance Scenarios

1. **AC-030-1** A key Apple accepted is added under its Key ID. Seen again, the entry keeps its name and note and follows the
   `.p8` file when it moved. An individual key is kept without an Issuer ID.
2. **AC-030-2** A key `auth status` could not read, or one without a Key ID or file path, is not remembered.
3. **AC-030-3** The account in use is the one whose Key ID `auth status` reports as saved; the list shows the latest used first.
4. **AC-030-4** Removing an account forgets the entry only: the `.p8` file and Apple's key are not touched.
5. **AC-030-5** `signing-accounts.json` in the Studio config folder holds name, Key ID, Issuer ID, file path, note and last
   use, nothing else.
6. **AC-030-6** The first run imports the profiles of the `xcross-key` script (`%APPDATA%\xcross\key-profiles.json`) when Studio
   has no file yet; later runs do not read it again.
7. **AC-030-7** An unreadable accounts file starts the list empty and never stops the app.
8. **AC-030-8** The Signing page shows an Accounts card: each account with its Key ID, key type, last use and note, and
   "In use" on the saved one, which has no Use button.
9. **AC-030-9** Use runs `xcross auth` with that account's Issuer ID, Key ID and file path, then asks what is saved again;
   a switch that worked stamps the account as used. A failed one says the saved sign-in is unchanged and shows the
   diagnostics.
10. **AC-030-10** An account whose `.p8` file is gone cannot be switched to; the row says where the file was.
11. **AC-030-11** Remove asks first and leaves the key file alone.
12. **AC-030-12** Rename changes the name and note.
13. **AC-030-13** With no accounts the card is not shown.
14. **AC-030-14** Every API key the app finds saved and accepted by Apple joins the list on its own, whether it was saved in
    Studio or with the CLI.

## Tests

`apps/studio/test/state/signing_accounts_test.dart` (AC-030-1 to 7) and `apps/studio/test/ui/signing_accounts_test.dart`
(AC-030-8 to 14).

## Not checked

Switching between two real accounts in the running GUI was not done: the tests use a scripted CLI. Run it once on Windows
with two keys and record the result here.
