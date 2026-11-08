# Feature Specification: Account details on the Accounts card

**Feature Branch**: `031-account-details` (work lands on `codex/029-xcode-ide-workspace`) | **Created**: 2026-11-08 | **Status**: Implemented, not yet seen with two real keys

**Input**: The Accounts card (feature 030) named each row by its Key ID. The developer wants each row to show the
account itself (who holds it, which company, the team number), not anything about one app. Apple's API does not return the
company name for a key, so the company is typed once. The Account Holder and the team ID are asked of Apple with the
account's own key.

## Scope

- `xcross auth account --key-id <id> --private-key <file> [--issuer-id <id>] [--json]` asks Apple with that key and prints
  one `asc_account` line. It never saves anything and never touches the saved sign-in, so Studio can ask about every
  account without switching keys.
- The Account Holder comes from `GET /v1/users?filter[roles]=ACCOUNT_HOLDER`. Apple allows this for a team key with the
  Admin role only; for any other key the answer says so and the holder stays unknown.
- The team ID is the `seedId` of the team's bundle IDs, when the key may read bundle IDs.
- The company name is never fetched: it is typed in the Edit dialog.

## Acceptance Scenarios

1. **AC-031-1** The Account Holder (first and last name) and the team ID are read with the key.
2. **AC-031-2** A key that may not read users or bundle IDs is not an error: the answer has no holder and says an Admin team
   key is needed.
3. **AC-031-3** An empty answer says that Apple returned no Account Holder.
4. **AC-031-4** The JSON line holds only `v`, `type`, `holderName`, `teamId` and `problem`.
5. **AC-031-5** `xcross auth account` needs `--key-id` and `--private-key`, fails when the file is missing, and `--json` stays
   refused for the other `auth` forms.
6. **AC-031-6** Each Accounts row shows "Account Holder: …" and "Team ID: …". Apple is asked once per account per start,
   with that account's own key, and never with a command that switches the saved sign-in. An account whose key file is
   gone is not asked.
7. **AC-031-7** When Apple refuses, the row shows the reason instead of a holder and offers to ask again.
8. **AC-031-8** The Edit dialog sets name, Account Holder, Company, Team ID and note; the row shows them.
9. **AC-031-9** What Apple reports fills empty fields only; a value the user typed is never replaced. A refusal is a note for
   this session. The details are kept in `signing-accounts.json` (text only).
10. **AC-031-10** The details stay when the same key is used again.

## Tests

`packages/studio_ext/test/shared/auth/account_lookup_test.dart` (AC-031-1 to 4),
`packages/xcross/test/cli/auth_status_test.dart` (AC-031-5),
`apps/studio/test/state/signing_accounts_test.dart` (AC-031-9, 10) and
`apps/studio/test/ui/signing_accounts_test.dart` (AC-031-6 to 8).

## Not checked

Apple's real answers were not seen: the tests use a scripted Apple. Run `xcross auth account` once with each real key on
Windows and record here whether the holder came back (it needs an Admin team key) and whether the team ID matched.
