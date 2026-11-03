// studio: 019–021 — what the App Store Connect commands share
// (specs/019-upload-processing, 020-testflight, 021-app-store-submission).
import 'package:apple_developer_kit/shared/appstoreconnect/asc_api.dart';
import 'package:apple_developer_kit/shared/appstoreconnect/asc_client.dart';
import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:meta/meta.dart';

/// Opens an App Store Connect API session (the composition root signs it
/// with the saved key).
@internal
typedef OpenAscApi = Future<AscApi> Function();

/// Writes text or NDJSON to stdout.
@internal
typedef WriteOut = void Function(String text);

/// The app a command acts on: `--app-id`, else the record whose bundle ID
/// matches [bundleId].
@internal
Future<AscResource> resolveAscApp(
  AscApi api, {
  String? appId,
  String? bundleId,
}) async {
  if (appId != null && appId.trim().isNotEmpty) {
    return AscApi.data(await api.get('/v1/apps/${appId.trim()}'));
  }
  if (bundleId == null || bundleId.isEmpty) {
    throw UsageException(
      'Pass --app-id <Apple ID of the app>, or run in the project folder.',
      '',
    );
  }
  final app = await AscApps.findByBundleId(api, bundleId);
  if (app == null) {
    throw CliError(
      'App Store Connect has no app with the bundle ID $bundleId. Create it '
      'under Apps → New App (https://appstoreconnect.apple.com/apps), or pass '
      '--app-id.',
    );
  }
  return app;
}

/// Turns an App Store Connect refusal into a message that names the role
/// usually needed.
@internal
CliError ascFailure(AppleApiError error, {required String action}) {
  final hint = switch (error.statusCode) {
    401 =>
      'The App Store Connect key was refused: run `xcross auth` again with a '
          'valid key.',
    403 =>
      'The role of this key may not do this: use a team key with the Admin or '
          'App Manager role (Developer keys can only upload builds).',
    404 => 'Check the app ID, build number or name you passed.',
    409 => 'App Store Connect refused the change in its current state.',
    _ => null,
  };
  return CliError(
    'Could not $action: ${error.message}${hint == null ? '' : '\nhint: $hint'}',
  );
}
