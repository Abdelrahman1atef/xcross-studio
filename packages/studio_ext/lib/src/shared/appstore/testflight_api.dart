// studio: 020 — TestFlight through the App Store Connect API
// (specs/020-testflight, research R1).
import 'package:apple_developer_kit/shared/appstoreconnect/asc_api.dart';
import 'package:apple_developer_kit/shared/appstoreconnect/asc_client.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:meta/meta.dart';

/// One build as `testflight status` reports it.
@internal
@immutable
final class TestFlightBuild {
  const TestFlightBuild({
    required this.id,
    required this.buildNumber,
    this.version,
    this.uploadedDate,
    this.processingState,
    this.expired = false,
    this.usesNonExemptEncryption,
    this.internalBuildState,
    this.externalBuildState,
    this.groups = const [],
    this.iconTemplateUrl,
    this.iconWidth,
    this.iconHeight,
  });

  final String id;

  /// `CFBundleVersion` (App Store Connect's build `version`).
  final String buildNumber;

  /// The marketing version (`preReleaseVersion.version`).
  final String? version;
  final String? uploadedDate;
  final String? processingState;
  final bool expired;
  final bool? usesNonExemptEncryption;
  final String? internalBuildState;
  final String? externalBuildState;

  /// Names of the beta groups the build is in.
  final List<String> groups;

  /// The icon App Store Connect took from the build (`iconAssetToken`), as the
  /// URL template (`…/{w}x{h}bb.{f}`) and the size it has; null when it found
  /// none.
  final String? iconTemplateUrl;
  final int? iconWidth;
  final int? iconHeight;

  /// The icon's URL at its own size as a PNG, or null without an icon.
  String? get iconUrl => iconTemplateUrl
      ?.replaceAll('{w}', '${iconWidth ?? 1024}')
      .replaceAll('{h}', '${iconHeight ?? 1024}')
      .replaceAll('{f}', 'png');

  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'buildNumber': buildNumber,
    'uploadedDate': uploadedDate,
    'processingState': processingState,
    'expired': expired,
    'usesNonExemptEncryption': usesNonExemptEncryption,
    'internalBuildState': internalBuildState,
    'externalBuildState': externalBuildState,
    'groups': groups,
    'icon': iconTemplateUrl == null
        ? null
        : {
            'templateUrl': iconTemplateUrl,
            'width': iconWidth,
            'height': iconHeight,
          },
  };
}

/// One beta group.
@internal
@immutable
final class TestFlightGroup {
  const TestFlightGroup({
    required this.id,
    required this.name,
    required this.internal,
    this.publicLinkEnabled = false,
    this.publicLink,
    this.publicLinkLimit,
  });

  factory TestFlightGroup.fromResource(AscResource resource) => TestFlightGroup(
    id: resource.id,
    name: resource.string('name') ?? resource.id,
    internal: resource.attributes['isInternalGroup'] == true,
    publicLinkEnabled: resource.attributes['publicLinkEnabled'] == true,
    publicLink: resource.string('publicLink'),
    publicLinkLimit: switch (resource.attributes['publicLinkLimit']) {
      final int value => value,
      _ => null,
    },
  );

  final String id;
  final String name;
  final bool internal;
  final bool publicLinkEnabled;
  final String? publicLink;
  final int? publicLinkLimit;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'internal': internal,
    'publicLinkEnabled': publicLinkEnabled,
    'publicLink': publicLink,
    'publicLinkLimit': publicLinkLimit,
  };
}

/// One beta tester.
@internal
@immutable
final class TestFlightTester {
  const TestFlightTester({
    required this.id,
    this.email,
    this.firstName,
    this.lastName,
    this.state,
  });

  factory TestFlightTester.fromResource(AscResource resource) =>
      TestFlightTester(
        id: resource.id,
        email: resource.string('email'),
        firstName: resource.string('firstName'),
        lastName: resource.string('lastName'),
        state: resource.string('state'),
      );

  final String id;
  final String? email;
  final String? firstName;
  final String? lastName;

  /// `INVITED`, `ACCEPTED`, `INSTALLED`, … when App Store Connect says.
  final String? state;

  Map<String, Object?> toJson() => {
    'id': id,
    'email': email,
    'firstName': firstName,
    'lastName': lastName,
    'state': state,
  };
}

/// The TestFlight operations of the App Store Connect API.
@internal
final class TestFlightApi {
  TestFlightApi(this.api);

  final AscApi api;

  /// The app's builds, newest upload first; [buildNumber] and [version]
  /// filter them.
  Future<List<TestFlightBuild>> builds(
    String appId, {
    String? buildNumber,
    String? version,
    int limit = 10,
  }) async {
    final document = await api.get(
      '/v1/builds',
      query: {
        'filter[app]': appId,
        'filter[version]': ?buildNumber,
        'filter[preReleaseVersion.version]': ?version,
        'sort': '-uploadedDate',
        'limit': '$limit',
        'include': 'preReleaseVersion,buildBetaDetail,betaGroups',
      },
    );
    final included = {
      for (final resource in AscApi.included(document))
        '${resource.type}/${resource.id}': resource,
    };
    AscResource? related(AscResource build, String name, String type) =>
        switch (build.relatedId(name)) {
          final String id => included['$type/$id'],
          null => null,
        };
    return [
      for (final build in AscApi.dataList(document))
        TestFlightBuild(
          id: build.id,
          buildNumber: build.string('version') ?? '',
          version: related(
            build,
            'preReleaseVersion',
            'preReleaseVersions',
          )?.string('version'),
          uploadedDate: build.string('uploadedDate'),
          processingState: build.string('processingState'),
          expired: build.attributes['expired'] == true,
          usesNonExemptEncryption:
              switch (build.attributes['usesNonExemptEncryption']) {
                final bool value => value,
                _ => null,
              },
          internalBuildState: related(
            build,
            'buildBetaDetail',
            'buildBetaDetails',
          )?.string('internalBuildState'),
          externalBuildState: related(
            build,
            'buildBetaDetail',
            'buildBetaDetails',
          )?.string('externalBuildState'),
          groups: [
            for (final id in relatedIds(build, 'betaGroups'))
              included['betaGroups/$id']?.string('name') ?? id,
          ],
          iconTemplateUrl: _icon(build, 'templateUrl'),
          iconWidth: int.tryParse('${_icon(build, 'width')}'),
          iconHeight: int.tryParse('${_icon(build, 'height')}'),
        ),
    ];
  }

  static String? _icon(AscResource build, String field) {
    final token = build.attributes['iconAssetToken'];
    if (token is! Map) return null;
    final value = token[field];
    return value == null ? null : '$value';
  }

  /// The build numbered [buildNumber], or the newest upload.
  Future<TestFlightBuild> build(String appId, {String? buildNumber}) async {
    final found = await builds(appId, buildNumber: buildNumber, limit: 1);
    if (found.isNotEmpty) return found.first;
    throw CliError(
      buildNumber == null
          ? 'The app has no build in App Store Connect yet. Upload one with '
                '`xcross publish`.'
          : 'App Store Connect has no build $buildNumber for this app.',
    );
  }

  /// The ids of a to-many relationship's `data`.
  @visibleForTesting
  static List<String> relatedIds(AscResource resource, String name) {
    final Object? relationship = resource.relationships[name];
    return [
      if (relationship case {'data': final List<Object?> data})
        for (final entry in data)
          if (entry case {'id': final String id}) id,
    ];
  }

  /// The app's beta groups.
  Future<List<TestFlightGroup>> groups(String appId) async => [
    for (final resource in await api.getAll(
      '/v1/betaGroups',
      query: {'filter[app]': appId, 'limit': '200'},
    ))
      TestFlightGroup.fromResource(resource),
  ];

  /// The group named [name] (case-insensitive).
  Future<TestFlightGroup> group(String appId, String name) async {
    final all = await groups(appId);
    for (final group in all) {
      if (group.name.toLowerCase() == name.toLowerCase()) return group;
    }
    throw CliError(
      'No beta group named "$name"'
      '${all.isEmpty ? '' : ' (groups: ${all.map((g) => g.name).join(', ')})'}. '
      'Create it with `xcross testflight group create "$name"`.',
    );
  }

  Future<TestFlightGroup> createGroup(
    String appId, {
    required String name,
    required bool external,
    bool publicLink = false,
    int? publicLinkLimit,
  }) async => TestFlightGroup.fromResource(
    AscApi.data(
      await api.post('/v1/betaGroups', {
        'data': {
          'type': 'betaGroups',
          'attributes': {
            'name': name,
            'isInternalGroup': !external,
            if (external) 'publicLinkEnabled': publicLink,
            if (external && publicLinkLimit != null) ...{
              'publicLinkLimitEnabled': true,
              'publicLinkLimit': publicLinkLimit,
            },
          },
          'relationships': {
            'app': {
              'data': {'type': 'apps', 'id': appId},
            },
          },
        },
      }),
    ),
  );

  Future<void> addBuildToGroup(String groupId, String buildId) =>
      api.post('/v1/betaGroups/$groupId/relationships/builds', {
        'data': [
          {'type': 'builds', 'id': buildId},
        ],
      });

  /// Sets the build's "What to Test" for [locale]; returns whether an
  /// existing localization was updated.
  Future<bool> setWhatToTest(
    String buildId, {
    required String text,
    required String locale,
  }) async {
    final existing = await api.getAll(
      '/v1/builds/$buildId/betaBuildLocalizations',
    );
    for (final localization in existing) {
      if (localization.string('locale') == locale) {
        await api.patch('/v1/betaBuildLocalizations/${localization.id}', {
          'data': {
            'type': 'betaBuildLocalizations',
            'id': localization.id,
            'attributes': {'whatsNew': text},
          },
        });
        return true;
      }
    }
    await api.post('/v1/betaBuildLocalizations', {
      'data': {
        'type': 'betaBuildLocalizations',
        'attributes': {'locale': locale, 'whatsNew': text},
        'relationships': {
          'build': {
            'data': {'type': 'builds', 'id': buildId},
          },
        },
      },
    });
    return false;
  }

  /// Invites [email] into the group; a tester App Store Connect already has
  /// (409) is added to the group instead. Returns whether it was new.
  Future<bool> addTester(
    String groupId, {
    required String email,
    String? firstName,
    String? lastName,
  }) async {
    try {
      await api.post('/v1/betaTesters', {
        'data': {
          'type': 'betaTesters',
          'attributes': {
            'email': email,
            'firstName': ?firstName,
            'lastName': ?lastName,
          },
          'relationships': {
            'betaGroups': {
              'data': [
                {'type': 'betaGroups', 'id': groupId},
              ],
            },
          },
        },
      });
      return true;
    } on AppleApiError catch (error) {
      if (error.statusCode != 409) rethrow;
    }
    final found = AscApi.dataList(
      await api.get('/v1/betaTesters', query: {'filter[email]': email}),
    );
    if (found.isEmpty) {
      throw CliError('App Store Connect refused to invite $email.');
    }
    await api.post('/v1/betaGroups/$groupId/relationships/betaTesters', {
      'data': [
        {'type': 'betaTesters', 'id': found.first.id},
      ],
    });
    return false;
  }

  Future<List<TestFlightTester>> testers(String groupId) async => [
    for (final resource in await api.getAll(
      '/v1/betaGroups/$groupId/betaTesters',
      query: {'limit': '200'},
    ))
      TestFlightTester.fromResource(resource),
  ];

  Future<void> setUsesEncryption(String buildId, {required bool uses}) =>
      api.patch('/v1/builds/$buildId', {
        'data': {
          'type': 'builds',
          'id': buildId,
          'attributes': {'usesNonExemptEncryption': uses},
        },
      });

  /// Updates (or creates) the beta app localization for [locale] with the
  /// non-null [attributes]; returns whether it existed.
  Future<bool> setBetaAppInfo(
    String appId, {
    required String locale,
    required Map<String, String> attributes,
  }) async {
    final existing = await api.getAll(
      '/v1/betaAppLocalizations',
      query: {'filter[app]': appId},
    );
    for (final localization in existing) {
      if (localization.string('locale') == locale) {
        await api.patch('/v1/betaAppLocalizations/${localization.id}', {
          'data': {
            'type': 'betaAppLocalizations',
            'id': localization.id,
            'attributes': attributes,
          },
        });
        return true;
      }
    }
    await api.post('/v1/betaAppLocalizations', {
      'data': {
        'type': 'betaAppLocalizations',
        'attributes': {'locale': locale, ...attributes},
        'relationships': {
          'app': {
            'data': {'type': 'apps', 'id': appId},
          },
        },
      },
    });
    return false;
  }

  /// Updates the app's beta review details (their id is the app's).
  Future<void> setBetaReviewDetails(
    String appId,
    Map<String, Object> attributes,
  ) async {
    final detail = AscApi.data(
      await api.get('/v1/apps/$appId/betaAppReviewDetail'),
    );
    await api.patch('/v1/betaAppReviewDetails/${detail.id}', {
      'data': {
        'type': 'betaAppReviewDetails',
        'id': detail.id,
        'attributes': attributes,
      },
    });
  }

  /// Submits the build to TestFlight App Review; returns the review state.
  Future<String?> submitForReview(String buildId) async => AscApi.data(
    await api.post('/v1/betaAppReviewSubmissions', {
      'data': {
        'type': 'betaAppReviewSubmissions',
        'relationships': {
          'build': {
            'data': {'type': 'builds', 'id': buildId},
          },
        },
      },
    }),
  ).string('betaReviewState');

  /// Turns the group's public link on or off (with an optional tester limit).
  Future<TestFlightGroup> setPublicLink(
    String groupId, {
    required bool enabled,
    int? limit,
  }) async => TestFlightGroup.fromResource(
    AscApi.data(
      await api.patch('/v1/betaGroups/$groupId', {
        'data': {
          'type': 'betaGroups',
          'id': groupId,
          'attributes': {
            'publicLinkEnabled': enabled,
            if (limit != null) ...{
              'publicLinkLimitEnabled': true,
              'publicLinkLimit': limit,
            },
          },
        },
      }),
    ),
  );
}
