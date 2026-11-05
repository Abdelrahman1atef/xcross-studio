// studio: 018 — `xcross release check --online` (AC-018-18).
import 'package:studio_ext/src/shared/release/release_checks.dart';
import 'package:studio_ext/src/shared/release/release_online.dart';
import 'package:test/test.dart';

import '../../support/fake_asc.dart';

ReleaseReport _offline({
  String bundleId = 'com.example.store',
  String version = '1.0.11',
  String build = '14',
  List<String> entitlements = const [],
}) => ReleaseReport(
  input: 'a.ipa',
  configuration: {
    'bundleId': bundleId,
    'version': version,
    'build': build,
    'entitlements': entitlements,
  },
  issues: const [],
);

FakeAsc _asc({
  bool app = true,
  List<Map<String, Object?>> builds = const [],
  List<Map<String, Object?>> versions = const [],
  List<String> capabilities = const [],
  bool bundleIdRegistered = true,
}) {
  final fake = FakeAsc()
    ..on(
      'GET',
      '/v1/apps',
      (_) => (
        status: 200,
        body: FakeAsc.doc([
          if (app)
            FakeAsc.resource('apps', 'A1', {'bundleId': 'com.example.store'}),
        ]),
      ),
    )
    ..on('GET', '/v1/builds', (_) => (status: 200, body: FakeAsc.doc(builds)))
    ..on(
      'GET',
      '/v1/apps/A1/appStoreVersions',
      (_) => (status: 200, body: FakeAsc.doc(versions)),
    )
    ..on(
      'GET',
      '/v1/bundleIds',
      (_) => (
        status: 200,
        body: FakeAsc.doc([
          if (bundleIdRegistered)
            FakeAsc.resource('bundleIds', 'B1', {
              'identifier': 'com.example.store',
            }),
        ]),
      ),
    )
    ..on(
      'GET',
      '/v1/bundleIds/B1/bundleIdCapabilities',
      (_) => (
        status: 200,
        body: FakeAsc.doc([
          for (final type in capabilities)
            FakeAsc.resource('bundleIdCapabilities', type, {
              'capabilityType': type,
            }),
        ]),
      ),
    );
  return fake;
}

Map<String, Object?> _build(String number, {String state = 'VALID'}) =>
    FakeAsc.resource('builds', 'b$number', {
      'version': number,
      'processingState': state,
    });

Map<String, Object?> _version(String name, String state) => FakeAsc.resource(
  'appStoreVersions',
  'v$name',
  {'versionString': name, 'appVersionState': state},
);

void main() {
  Future<List<String>> codes(FakeAsc fake, ReleaseReport offline) async => [
    for (final issue in await runOnlineReleaseChecks(fake.api(), offline))
      issue.code,
  ];

  test('an app that App Store Connect accepts has nothing to report', () async {
    final fake = _asc(
      builds: [_build('13')],
      versions: [_version('1.0.10', 'READY_FOR_SALE')],
      capabilities: ['PUSH_NOTIFICATIONS'],
    );
    expect(
      await codes(fake, _offline(entitlements: ['aps-environment'])),
      isEmpty,
    );
  });

  test('every request is a read', () async {
    final fake = _asc(capabilities: ['PUSH_NOTIFICATIONS']);
    await codes(fake, _offline(entitlements: ['aps-environment']));
    expect(fake.requests, isNotEmpty);
    expect(fake.requests.map((r) => r.method).toSet(), {'GET'});
  });

  test('no app record', () async {
    expect(await codes(_asc(app: false), _offline()), ['release.asc_no_app']);
  });

  test(
    'the build number is already there, or lower than one that is',
    () async {
      expect(
        await codes(
          _asc(builds: [_build('14', state: 'PROCESSING')]),
          _offline(),
        ),
        ['release.asc_build_exists'],
      );
      expect(await codes(_asc(builds: [_build('15')]), _offline()), [
        'release.asc_build_not_higher',
      ]);
    },
  );

  test('a version that has shipped takes no build', () async {
    final fake = _asc(versions: [_version('1.0.11', 'READY_FOR_SALE')]);
    expect(await codes(fake, _offline()), ['release.asc_version_closed']);
    // A higher version is fine, and a version still being prepared too.
    final higher = _asc(
      versions: [
        _version('1.0.10', 'READY_FOR_SALE'),
        _version('1.0.11', 'PREPARE_FOR_SUBMISSION'),
      ],
    );
    expect(await codes(higher, _offline()), isEmpty);
  });

  test('an entitlement whose capability the App ID lacks', () async {
    final fake = _asc(capabilities: ['PUSH_NOTIFICATIONS']);
    final issues = await runOnlineReleaseChecks(
      fake.api(),
      _offline(
        entitlements: [
          'aps-environment',
          'com.apple.developer.applesignin',
          'application-identifier',
        ],
      ),
    );
    expect(issues.map((i) => i.code), ['release.asc_capability_missing']);
    expect(issues.single.message, contains('APPLE_ID_AUTH'));
  });

  test('a refused key is one warning, not an error', () async {
    final fake = FakeAsc()
      ..on(
        'GET',
        '/v1/apps',
        (_) => (
          status: 403,
          body: {
            'errors': [
              {'status': '403', 'detail': 'forbidden'},
            ],
          },
        ),
      );
    final issues = await runOnlineReleaseChecks(fake.api(), _offline());
    expect(issues.single.code, 'release.asc_unavailable');
    expect(issues.single.severity, ReleaseSeverity.warning);
  });

  test('the report says whether App Store Connect was asked', () {
    final report = _offline().withOnline(const [], online: true);
    expect(report.configuration['online'], isTrue);
    expect(report.toJson()['configuration'], containsPair('online', true));
  });
}
