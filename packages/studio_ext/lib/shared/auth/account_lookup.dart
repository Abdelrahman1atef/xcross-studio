// studio: 031 — who an App Store Connect API key belongs to, for the account
// list in Studio. Only reads; never prints a token or key.
import 'package:apple_developer_kit/shared/appstoreconnect/asc_api.dart';
import 'package:apple_developer_kit/shared/appstoreconnect/asc_client.dart';
import 'package:meta/meta.dart';

/// What Apple says about the account behind a key. The company name is not
/// here: the API has no endpoint that returns it.
@immutable
final class AccountDetails {
  const AccountDetails({this.holderName, this.teamId, this.problem});

  /// The Account Holder's name, when the key may read the team's users.
  final String? holderName;

  /// The team ID prefix of the team's bundle IDs, when the key may read them.
  final String? teamId;

  /// Why the holder could not be read; null when it was.
  final String? problem;

  Map<String, Object?> toJson() => {
    'v': 1,
    'type': 'asc_account',
    'holderName': holderName,
    'teamId': teamId,
    'problem': problem,
  };
}

/// Reads the Account Holder and team ID with [api]. A key that Apple refuses
/// the read for (an individual key, or a role below Admin) is not an error:
/// the answer says so in [AccountDetails.problem].
Future<AccountDetails> lookupAccountDetails(AscApi api) async {
  String? holder;
  String? problem;
  try {
    final users = await api.getAll(
      '/v1/users',
      query: {'filter[roles]': 'ACCOUNT_HOLDER', 'limit': '5'},
      maxPages: 1,
    );
    holder = users
        .map(
          (user) => [
            user.string('firstName'),
            user.string('lastName'),
          ].whereType<String>().where((part) => part.isNotEmpty).join(' '),
        )
        .where((name) => name.isNotEmpty)
        .firstOrNull;
    if (holder == null) problem = 'Apple returned no Account Holder.';
  } on AppleApiError catch (error) {
    problem = switch (error.statusCode) {
      401 || 403 =>
        "This key may not read the team's users. Only a team key with the "
            'Admin role can.',
      _ => error.message,
    };
  }

  String? teamId;
  try {
    final bundleIds = await api.getAll(
      '/v1/bundleIds',
      query: {'limit': '1'},
      maxPages: 1,
    );
    teamId = bundleIds.map((bundleId) => bundleId.string('seedId')).firstOrNull;
  } on AppleApiError {
    // Not every key can read bundle IDs; the team ID stays unknown.
  }
  return AccountDetails(holderName: holder, teamId: teamId, problem: problem);
}
