// studio: 021 — the App Store version a submission works on
// (specs/021-app-store-submission, AC-021-2, AC-021-7).
import 'package:apple_developer_kit/shared/appstoreconnect/asc_api.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:meta/meta.dart';

/// Finding, creating and reading iOS App Store versions and builds.
@internal
abstract final class AppStoreVersions {
  /// States in which a version's metadata and build can still change.
  static const editableStates = {
    'PREPARE_FOR_SUBMISSION',
    'DEVELOPER_REJECTED',
    'REJECTED',
    'METADATA_REJECTED',
    'INVALID_BINARY',
  };

  /// The version's state (`appVersionState`, else the older
  /// `appStoreState`).
  static String? stateOf(AscResource version) =>
      version.string('appVersionState') ?? version.string('appStoreState');

  /// The app's iOS versions, newest first.
  static Future<List<AscResource>> list(AscApi api, String appId) async {
    final versions = await api.getAll(
      '/v1/apps/$appId/appStoreVersions',
      query: {'filter[platform]': 'IOS', 'limit': '50'},
    );
    return versions..sort(
      (a, b) => (b.string('createdDate') ?? '').compareTo(
        a.string('createdDate') ?? '',
      ),
    );
  }

  /// The version named [version], else the newest editable one; null when
  /// there is none.
  static Future<AscResource?> find(
    AscApi api,
    String appId, {
    String? version,
  }) async {
    final versions = await list(api, appId);
    if (version != null) {
      return versions
          .where((v) => v.string('versionString') == version)
          .firstOrNull;
    }
    return versions
        .where((v) => editableStates.contains(stateOf(v)))
        .firstOrNull;
  }

  /// Like [find], but a missing version is a [CliError] that says how to
  /// create it.
  static Future<AscResource> require(
    AscApi api,
    String appId, {
    String? version,
  }) async {
    final found = await find(api, appId, version: version);
    if (found != null) return found;
    throw CliError(
      version == null
          ? 'The app has no App Store version that can be edited. Create one '
                'with `xcross appstore version <x.y.z> --create`.'
          : 'The app has no App Store version $version. Create it with '
                '`xcross appstore version $version --create`.',
    );
  }

  /// Creates the iOS version [version].
  static Future<AscResource> create(
    AscApi api,
    String appId,
    String version,
  ) async => AscApi.data(
    await api.post('/v1/appStoreVersions', {
      'data': {
        'type': 'appStoreVersions',
        'attributes': {'platform': 'IOS', 'versionString': version},
        'relationships': {
          'app': {
            'data': {'type': 'apps', 'id': appId},
          },
        },
      },
    }),
  );

  /// The app's build with build number [number] (`CFBundleVersion`).
  static Future<AscResource?> buildByNumber(
    AscApi api,
    String appId,
    String number,
  ) async {
    final builds = await api.getAll(
      '/v1/builds',
      query: {'filter[app]': appId, 'filter[version]': number, 'limit': '10'},
    );
    return builds.firstOrNull;
  }

  /// The build attached to [versionId], or null.
  static Future<AscResource?> attachedBuild(
    AscApi api,
    String versionId,
  ) async {
    final document = await api.get('/v1/appStoreVersions/$versionId/build');
    final Object? data = document['data'];
    return data is Map
        ? AscResource.fromJson(data.cast<String, dynamic>())
        : null;
  }
}
