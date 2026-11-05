// studio: 018 — the part of the release check only App Store Connect can
// answer: does the app exist there, will it take this version and build, does
// the App ID have what the entitlements need. Read-only: GET requests only.
import 'package:apple_developer_kit/shared/appstoreconnect/asc_api.dart';
import 'package:apple_developer_kit/shared/appstoreconnect/asc_capabilities.dart';
import 'package:apple_developer_kit/shared/appstoreconnect/asc_client.dart';
import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/appstore/app_store_versions.dart';
import 'package:studio_ext/src/shared/release/release_checks.dart';

/// Versions in these states have shipped (or been taken down): App Store
/// Connect takes no new build for them, nor for a lower version number.
const _closedStates = {
  'READY_FOR_SALE',
  'REPLACED_WITH_NEW_VERSION',
  'REMOVED_FROM_SALE',
  'DEVELOPER_REMOVED_FROM_SALE',
};

/// Asks App Store Connect about the app in [offline]'s configuration and
/// returns what it would refuse. Never throws for a refused or failed
/// request: that is one warning, because the offline report still stands.
@internal
Future<List<ReleaseIssue>> runOnlineReleaseChecks(
  AscApi api,
  ReleaseReport offline,
) async {
  final configuration = offline.configuration;
  final bundleId = configuration['bundleId'];
  final version = configuration['version'];
  final build = configuration['build'];
  if (bundleId is! String || version is! String || build is! String) {
    return [
      const ReleaseIssue(
        'release.asc_unavailable',
        ReleaseSeverity.warning,
        'The IPA has no bundle ID, version or build number to look up on '
            'App Store Connect.',
      ),
    ];
  }
  final entitlements = [
    if (configuration['entitlements'] case final List<Object?> keys)
      ...keys.whereType<String>(),
  ];
  try {
    final app = await AscApps.findByBundleId(api, bundleId);
    if (app == null) {
      return [
        ReleaseIssue(
          'release.asc_no_app',
          ReleaseSeverity.error,
          'App Store Connect has no app with the bundle ID $bundleId; an '
              'upload for it is refused.',
          hint:
              'Create it under Apps → New App '
              '(https://appstoreconnect.apple.com/apps) with this bundle ID.',
        ),
      ];
    }
    return [
      ...await _builds(api, app.id, version, build),
      ...await _versions(api, app.id, version),
      ...await _capabilities(api, bundleId, entitlements),
    ];
  } on AppleApiError catch (error) {
    final why = switch (error.statusCode) {
      401 => 'the key was refused (run `xcross auth` again)',
      403 =>
        "the key's role may not read it (use an Admin, App Manager or "
            'Developer key)',
      _ => error.message,
    };
    return [_unavailable(why)];
  } on Object catch (error) {
    return [_unavailable('$error')];
  }
}

ReleaseIssue _unavailable(String why) => ReleaseIssue(
  'release.asc_unavailable',
  ReleaseSeverity.warning,
  'App Store Connect could not be asked: $why. The IPA checks above still '
      'apply.',
);

Future<List<ReleaseIssue>> _builds(
  AscApi api,
  String appId,
  String version,
  String build,
) async {
  final builds = AscApi.dataList(
    await api.get(
      '/v1/builds',
      query: {
        'filter[app]': appId,
        'filter[preReleaseVersion.version]': version,
        'sort': '-uploadedDate',
        'limit': '50',
        'fields[builds]': 'version,processingState',
      },
    ),
  );
  for (final existing in builds) {
    if (existing.string('version') == build) {
      return [
        ReleaseIssue(
          'release.asc_build_exists',
          ReleaseSeverity.error,
          'Build $build of $version is already on App Store Connect '
              '(${existing.string('processingState') ?? 'uploaded'}).',
          hint: 'Build again with `--build-number auto`.',
        ),
      ];
    }
  }
  final number = int.tryParse(build);
  final numbers = [
    for (final existing in builds)
      if (int.tryParse(existing.string('version') ?? '') case final int n) n,
  ];
  if (number != null && numbers.isNotEmpty) {
    final newest = numbers.reduce((a, b) => a > b ? a : b);
    if (number < newest) {
      return [
        ReleaseIssue(
          'release.asc_build_not_higher',
          ReleaseSeverity.error,
          'Build $build of $version is lower than build $newest, which App '
              'Store Connect already has for this version.',
          hint: 'Build again with `--build-number auto`.',
        ),
      ];
    }
  }
  return const [];
}

Future<List<ReleaseIssue>> _versions(
  AscApi api,
  String appId,
  String version,
) async {
  final mine = _parts(version);
  for (final other in await AppStoreVersions.list(api, appId)) {
    final state = AppStoreVersions.stateOf(other);
    final name = other.string('versionString');
    if (name == null || !_closedStates.contains(state)) continue;
    if (_compare(mine, _parts(name)) <= 0) {
      return [
        ReleaseIssue(
          'release.asc_version_closed',
          ReleaseSeverity.error,
          'Version $name is already on the App Store ($state), so App Store '
              'Connect takes no build for $version.',
          hint: 'Raise the version above $name in pubspec.yaml.',
        ),
      ];
    }
  }
  return const [];
}

Future<List<ReleaseIssue>> _capabilities(
  AscApi api,
  String bundleId,
  List<String> entitlements,
) async {
  final needed = AscCapabilities.forKeys(entitlements);
  if (needed.isEmpty) return const [];
  final ids = AscApi.dataList(
    await api.get(
      '/v1/bundleIds',
      query: {'filter[identifier]': bundleId, 'limit': '10'},
    ),
  );
  final id = ids.where((i) => i.string('identifier') == bundleId).firstOrNull;
  if (id == null) {
    return [
      ReleaseIssue(
        'release.asc_capability_missing',
        ReleaseSeverity.warning,
        'The App ID $bundleId is not registered, so its capabilities '
            '(${needed.join(', ')}) could not be checked.',
      ),
    ];
  }
  final enabled = {
    for (final capability in AscApi.dataList(
      await api.get('/v1/bundleIds/${id.id}/bundleIdCapabilities'),
    ))
      ?capability.string('capabilityType'),
  };
  return [
    for (final type in needed)
      if (!enabled.contains(type))
        ReleaseIssue(
          'release.asc_capability_missing',
          ReleaseSeverity.warning,
          'The IPA is signed with an entitlement that needs $type, but the '
              'App ID $bundleId does not have it switched on.',
          hint:
              'Enable $type for the App ID at '
              'developer.apple.com → Identifiers, then build again.',
        ),
  ];
}

List<int> _parts(String version) => [
  for (final part in version.split('.')) int.tryParse(part) ?? 0,
];

int _compare(List<int> a, List<int> b) {
  final length = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}
