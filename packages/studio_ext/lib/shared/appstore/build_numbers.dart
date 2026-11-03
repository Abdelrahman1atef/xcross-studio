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
