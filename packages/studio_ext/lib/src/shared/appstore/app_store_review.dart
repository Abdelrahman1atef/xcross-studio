// studio: 021 — attach a build, find what blocks a submission, submit it,
// and follow its state (specs/021-app-store-submission, AC-021-7…AC-021-9).
import 'package:apple_developer_kit/shared/appstoreconnect/asc_api.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/appstore/app_store_metadata.dart';
import 'package:studio_ext/src/shared/appstore/app_store_versions.dart';

/// App Store Connect pages for what the public API leaves out (AC-021-10).
@internal
const apiGapPages =
    'App Privacy, Pricing and Availability, and Agreements, Tax, and Banking '
    'are not in the App Store Connect API: check them at '
    'https://appstoreconnect.apple.com/apps (the app) and '
    'https://appstoreconnect.apple.com/business before submitting.';

/// Review steps for one app.
@internal
final class AppStoreReview {
  AppStoreReview(this.api, {required this.appId});

  final AscApi api;
  final String appId;

  /// Attaches the build with build number [buildNumber] to [version].
  Future<AscResource> attach(AscResource version, String buildNumber) async {
    final build = await AppStoreVersions.buildByNumber(api, appId, buildNumber);
    if (build == null) {
      throw CliError(
        'App Store Connect has no build $buildNumber for this app yet. Upload '
        'it with `xcross publish`, and wait until it has processed.',
      );
    }
    final state = build.string('processingState');
    if (state != null && state != 'VALID') {
      throw CliError(
        'Build $buildNumber is $state; only a processed (VALID) build can be '
        'attached. Follow it with `xcross publish --wait`.',
      );
    }
    await api.patch('/v1/appStoreVersions/${version.id}/relationships/build', {
      'data': {'type': 'builds', 'id': build.id},
    });
    return build;
  }

  /// What App Store Connect would refuse in a submission of [version],
  /// as far as the API shows it; empty when nothing blocks it.
  Future<List<String>> blockers(AscResource version) async {
    final problems = <String>[];
    if (await AppStoreVersions.attachedBuild(api, version.id) == null) {
      problems.add(
        'No build is attached: `xcross appstore attach --build <number>`.',
      );
    }
    final localizations = await api.getAll(
      '/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations',
    );
    if (localizations.isEmpty) {
      problems.add(
        'The version has no localization: `xcross appstore metadata push`.',
      );
    }
    for (final localization in localizations) {
      final locale = localization.string('locale') ?? localization.id;
      final missing = [
        for (final (attribute, label) in const [
          ('description', 'description'),
          ('keywords', 'keywords'),
          ('supportUrl', 'support URL'),
        ])
          if ((localization.string(attribute) ?? '').trim().isEmpty) label,
      ];
      if (missing.isNotEmpty) {
        problems.add('$locale has no ${missing.join(', ')}.');
      }
      var screenshots = 0;
      for (final set in await api.getAll(
        '/v1/appStoreVersionLocalizations/${localization.id}/appScreenshotSets',
      )) {
        screenshots += (await api.getAll(
          '/v1/appScreenshotSets/${set.id}/appScreenshots',
        )).length;
      }
      if (screenshots == 0) {
        problems.add(
          '$locale has no screenshots: `xcross appstore screenshots push`.',
        );
      }
    }
    final info = await MetadataSync(
      api,
      appId: appId,
      version: version,
    ).appInfo();
    if (info != null) {
      for (final localization in await api.getAll(
        '/v1/appInfos/${info.id}/appInfoLocalizations',
      )) {
        if ((localization.string('name') ?? '').trim().isEmpty) {
          problems.add(
            '${localization.string('locale') ?? localization.id} has no app '
            'name.',
          );
        }
      }
    }
    return problems;
  }

  /// Submits [version] for review (reusing an unsubmitted submission) and
  /// returns the review submission.
  Future<AscResource> submit(AscResource version) async {
    final open = await api.getAll(
      '/v1/reviewSubmissions',
      query: {
        'filter[app]': appId,
        'filter[platform]': 'IOS',
        'filter[state]': 'READY_FOR_REVIEW',
      },
    );
    final submission =
        open.firstOrNull ??
        AscApi.data(
          await api.post('/v1/reviewSubmissions', {
            'data': {
              'type': 'reviewSubmissions',
              'attributes': {'platform': 'IOS'},
              'relationships': {
                'app': {
                  'data': {'type': 'apps', 'id': appId},
                },
              },
            },
          }),
        );
    await api.post('/v1/reviewSubmissionItems', {
      'data': {
        'type': 'reviewSubmissionItems',
        'relationships': {
          'reviewSubmission': {
            'data': {'type': 'reviewSubmissions', 'id': submission.id},
          },
          'appStoreVersion': {
            'data': {'type': 'appStoreVersions', 'id': version.id},
          },
        },
      },
    });
    return AscApi.data(
      await api.patch('/v1/reviewSubmissions/${submission.id}', {
        'data': {
          'type': 'reviewSubmissions',
          'id': submission.id,
          'attributes': {'submitted': true},
        },
      }),
    );
  }

  /// The editable (else newest) version's state and build, and the latest
  /// review submissions.
  Future<Map<String, Object?>> status() async {
    final versions = await AppStoreVersions.list(api, appId);
    final version =
        versions
            .where(
              (v) => AppStoreVersions.editableStates.contains(
                AppStoreVersions.stateOf(v),
              ),
            )
            .firstOrNull ??
        versions.firstOrNull;
    final build = version == null
        ? null
        : await AppStoreVersions.attachedBuild(api, version.id);
    final submissions = await api.getAll(
      '/v1/reviewSubmissions',
      query: {'filter[app]': appId, 'limit': '5'},
      maxPages: 1,
    );
    return {
      'v': 1,
      'type': 'appstore_status',
      'version': version?.string('versionString'),
      'state': version == null ? null : AppStoreVersions.stateOf(version),
      'build': build?.string('version'),
      'submissions': [
        for (final submission in submissions)
          {
            'id': submission.id,
            'state': submission.string('state'),
            'submittedDate': submission.string('submittedDate'),
          },
      ],
    };
  }
}
