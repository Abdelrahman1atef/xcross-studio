// studio: 019 — `--build-number auto` (specs/019-upload-processing, AC-019-7).
import 'dart:math';

import 'package:apple_developer_kit/shared/appstoreconnect/asc_api.dart';

/// The highest numeric build number App Store Connect has for [appId], or
/// null when it has none.
Future<int?> latestBuildNumber(AscApi api, String appId) async {
  final builds = AscApi.dataList(
    await api.get(
      '/v1/builds',
      query: {
        'filter[app]': appId,
        'sort': '-uploadedDate',
        'limit': '50',
        'fields[builds]': 'version',
      },
    ),
  );
  int? highest;
  for (final build in builds) {
    final number = int.tryParse(build.string('version') ?? '');
    if (number != null && (highest == null || number > highest)) {
      highest = number;
    }
  }
  return highest;
}

/// The build number to use: never lower than [local], and one more than the
/// newest uploaded build.
int nextBuildNumber({required int local, required int? latest}) =>
    latest == null ? local : max(local, latest + 1);

/// The numeric build numbers App Store Connect has for [version] of [appId]
/// (one version only: other versions do not limit this one's numbers).
Future<List<int>> buildNumbersOfVersion(
  AscApi api,
  String appId,
  String version,
) async {
  final builds = AscApi.dataList(
    await api.get(
      '/v1/builds',
      query: {
        'filter[app]': appId,
        'filter[preReleaseVersion.version]': version,
        'sort': '-uploadedDate',
        'limit': '200',
        'fields[builds]': 'version',
      },
    ),
  );
  return [
    for (final build in builds)
      if (int.tryParse(build.string('version') ?? '') case final int number)
        number,
  ];
}

/// `--build-number keep`: the [chosen] number while App Store Connect takes
/// it for this version, else the next one it takes. It takes a number higher
/// than every build the version already has (see release.asc_build_exists
/// and release.asc_build_not_higher), so 2.0.0 (1) with build 1 uploaded
/// becomes 2.0.0 (2), and 2.0.1 (1) stays 1 whatever 2.0.0 has.
int keptBuildNumber({required int chosen, required List<int> existing}) {
  if (existing.isEmpty) return chosen;
  final newest = existing.reduce(max);
  return chosen > newest ? chosen : newest + 1;
}
