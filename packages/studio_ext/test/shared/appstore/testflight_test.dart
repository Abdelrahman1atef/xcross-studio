// studio: 020 — `xcross testflight` (specs/020-testflight).
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_kit/composition/native_host.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/appstore/testflight_command.dart';
import 'package:test/test.dart';

import '../../support/fake_asc.dart';

void main() {
  late Directory project;
  late FakeAsc asc;
  late StringBuffer out;

  setUp(() {
    project = Directory.systemTemp.createTempSync('testflight-');
    final xcodeproj = Directory(p.join(project.path, 'ios', 'Runner.xcodeproj'))
      ..createSync(recursive: true);
    File(p.join(xcodeproj.path, 'project.pbxproj')).writeAsStringSync(
      '{\n  PRODUCT_BUNDLE_IDENTIFIER = com.example.app;\n'
      '  PRODUCT_BUNDLE_IDENTIFIER = com.example.app.RunnerTests;\n}\n',
    );
    asc = FakeAsc()
      ..on(
        'GET',
        '/v1/apps',
        (request) => (
          status: 200,
          body: FakeAsc.doc([
            if (request.url.queryParameters['filter[bundleId]'] ==
                'com.example.app')
              FakeAsc.resource('apps', 'app1', {'bundleId': 'com.example.app'}),
          ]),
        ),
      )
      ..on(
        'GET',
        '/v1/apps/app9',
        (_) => (
          status: 200,
          body: FakeAsc.doc(
            FakeAsc.resource('apps', 'app9', {'bundleId': 'com.other.app'}),
          ),
        ),
      )
      ..on(
        'GET',
        '/v1/builds',
        (request) => (
          status: 200,
          body: FakeAsc.doc(
            [
              if (request.url.queryParameters['filter[version]']
                  case null || '7')
                FakeAsc.resource(
                  'builds',
                  'b7',
                  {
                    'version': '7',
                    'uploadedDate': '2026-11-03T10:00:00Z',
                    'processingState': 'VALID',
                    'expired': false,
                    'usesNonExemptEncryption': false,
                    'iconAssetToken': {
                      'templateUrl':
                          'https://example.test/AppIcon60x60@2x.png/{w}x{h}bb.{f}',
                      'width': 120,
                      'height': 120,
                    },
                  },
                  {
                    'preReleaseVersion': {
                      'data': {'type': 'preReleaseVersions', 'id': 'v1'},
                    },
                    'buildBetaDetail': {
                      'data': {'type': 'buildBetaDetails', 'id': 'd7'},
                    },
                    'betaGroups': {
                      'data': [
                        {'type': 'betaGroups', 'id': 'g1'},
                      ],
                    },
                  },
                ),
            ],
            included: [
              FakeAsc.resource('preReleaseVersions', 'v1', {
                'version': '1.2.0',
              }),
              FakeAsc.resource('buildBetaDetails', 'd7', {
                'internalBuildState': 'READY_FOR_BETA_TESTING',
                'externalBuildState': 'READY_FOR_BETA_SUBMISSION',
              }),
              FakeAsc.resource('betaGroups', 'g1', {'name': 'QA'}),
            ],
          ),
        ),
      )
      ..on(
        'GET',
        '/v1/betaGroups',
        (_) => (
          status: 200,
          body: FakeAsc.doc([
            FakeAsc.resource('betaGroups', 'g1', {
              'name': 'QA',
              'isInternalGroup': true,
            }),
            FakeAsc.resource('betaGroups', 'g2', {
              'name': 'Public',
              'isInternalGroup': false,
              'publicLinkEnabled': true,
              'publicLink': 'https://testflight.apple.com/join/abc',
            }),
          ]),
        ),
      );
    out = StringBuffer();
  });
  tearDown(() => project.deleteSync(recursive: true));

  Future<void> run(List<String> args) =>
      (CommandRunner<void>('xcross', 'test')..addCommand(
            TestFlightCommand(
              TestFlightContext(
                openApi: () async => asc.api(),
                fileSystem: detectPlatformHost().fileSystem,
                paths: p.context,
                currentDirectory: () => project.path,
                write: out.write,
              ),
            ),
          ))
          .run(['testflight', ...args]);

  Map<String, Object?> json() =>
      (jsonDecode(out.toString().trim()) as Map).cast<String, Object?>();

  group('AC-020-1 status', () {
    test('lists builds with processing, beta states and groups', () async {
      await run(['status']);
      final text = out.toString();
      expect(text, contains('1.2.0 (7)  VALID'));
      expect(text, contains('internal: READY_FOR_BETA_TESTING'));
      expect(text, contains('external: READY_FOR_BETA_SUBMISSION'));
      expect(text, contains('no non-exempt encryption'));
      expect(text, contains('groups: QA'));
      expect(
        text,
        contains(
          'icon: 120x120  '
          'https://example.test/AppIcon60x60@2x.png/120x120bb.png',
        ),
      );
      final request = asc.requests.firstWhere(
        (r) => r.url.path == '/v1/builds',
      );
      expect(request.url.queryParameters['filter[app]'], 'app1');
      expect(request.url.queryParameters['sort'], '-uploadedDate');
      expect(
        request.url.queryParameters['include'],
        'preReleaseVersion,buildBetaDetail,betaGroups',
      );
    });

    test('--json prints one testflight_status object', () async {
      await run(['status', '--build', '7', '--json']);
      final status = json();
      expect(status['type'], 'testflight_status');
      expect(status['appId'], 'app1');
      final build = (status['builds']! as List).single as Map;
      expect(build['buildNumber'], '7');
      expect(build['version'], '1.2.0');
      expect(build['processingState'], 'VALID');
      expect(build['groups'], ['QA']);
      expect(build['icon'], {
        'templateUrl': 'https://example.test/AppIcon60x60@2x.png/{w}x{h}bb.{f}',
        'width': 120,
        'height': 120,
      });
    });

    test('a build Apple found no icon in says so', () async {
      asc.on(
        'GET',
        '/v1/builds',
        (_) => (
          status: 200,
          body: FakeAsc.doc([
            FakeAsc.resource('builds', 'b8', {
              'version': '8',
              'processingState': 'VALID',
            }),
          ]),
        ),
      );
      await run(['status']);
      expect(out.toString(), contains('icon: none'));
    });
  });

  group('AC-020-2 app and build resolution', () {
    test('--app-id wins over the project', () async {
      await run(['status', '--app-id', 'app9', '--json']);
      expect(json()['appId'], 'app9');
    });

    test('no app record for the bundle ID explains what to do', () {
      File(
        p.join(project.path, 'ios', 'Runner.xcodeproj', 'project.pbxproj'),
      ).writeAsStringSync(
        '{\n  PRODUCT_BUNDLE_IDENTIFIER = com.none.app;\n}\n',
      );
      expect(
        run(['status']),
        throwsA(
          isA<CliError>().having(
            (e) => e.message,
            'message',
            contains('New App'),
          ),
        ),
      );
    });

    test('an unknown build number is an error', () {
      expect(
        run(['add', '--group', 'QA', '--build', '99']),
        throwsA(
          isA<CliError>().having((e) => e.message, 'message', contains('99')),
        ),
      );
    });

    test('a 403 carries the role hint', () {
      asc.on(
        'POST',
        '/v1/betaGroups/*',
        (_) => (
          status: 403,
          body: {
            'errors': [
              {'detail': 'not allowed'},
            ],
          },
        ),
      );
      expect(
        run(['add', '--group', 'QA']),
        throwsA(
          isA<CliError>().having(
            (e) => e.message,
            'message',
            contains('Admin or App Manager'),
          ),
        ),
      );
    });
  });

  group('AC-020-3 groups', () {
    test('lists internal and external groups', () async {
      await run(['groups', '--json']);
      final groups = json()['groups']! as List;
      expect(groups.map((g) => (g as Map)['name']), ['QA', 'Public']);
      expect(
        (groups[1] as Map)['publicLink'],
        contains('testflight.apple.com'),
      );
    });

    test('creates an external group with a public link', () async {
      asc.on(
        'POST',
        '/v1/betaGroups',
        (request) => (
          status: 201,
          body: FakeAsc.doc(
            FakeAsc.resource('betaGroups', 'g3', {
              'name': 'Beta',
              'isInternalGroup': false,
              'publicLinkEnabled': true,
              'publicLink': 'https://testflight.apple.com/join/xyz',
            }),
          ),
        ),
      );
      await run([
        'group',
        'create',
        'Beta',
        '--external',
        '--public-link',
        '--public-link-limit',
        '50',
      ]);
      final body = asc.bodies('POST', '/v1/betaGroups').single;
      final data = body['data']! as Map;
      expect(data['attributes'], {
        'name': 'Beta',
        'isInternalGroup': false,
        'publicLinkEnabled': true,
        'publicLinkLimitEnabled': true,
        'publicLinkLimit': 50,
      });
      expect(((data['relationships']! as Map)['app'] as Map)['data'], {
        'type': 'apps',
        'id': 'app1',
      });
      expect(out.toString(), contains('join/xyz'));
    });

    test('a public link on an internal group is refused', () {
      expect(
        run(['group', 'create', 'QA2', '--public-link']),
        throwsA(isA<UsageException>()),
      );
    });
  });

  test('AC-020-4 add puts the newest build in the group', () async {
    asc.on(
      'POST',
      '/v1/betaGroups/g1/relationships/builds',
      (_) => (status: 204, body: null),
    );
    await run(['add', '--group', 'qa']);
    expect(
      asc.bodies('POST', '/v1/betaGroups/g1/relationships/builds').single,
      {
        'data': [
          {'type': 'builds', 'id': 'b7'},
        ],
      },
    );
    expect(out.toString(), contains('Added 1.2.0 (7) to "QA"'));
  });

  group('AC-020-5 what to test', () {
    test('creates the localization when there is none', () async {
      asc
        ..on(
          'GET',
          '/v1/builds/b7/betaBuildLocalizations',
          (_) => (status: 200, body: FakeAsc.doc([])),
        )
        ..on(
          'POST',
          '/v1/betaBuildLocalizations',
          (_) => (
            status: 201,
            body: FakeAsc.doc(FakeAsc.resource('betaBuildLocalizations', 'l1')),
          ),
        );
      await run(['what-to-test', 'Check', 'the', 'map']);
      final data =
          asc.bodies('POST', '/v1/betaBuildLocalizations').single['data']!
              as Map;
      expect(data['attributes'], {
        'locale': 'en-US',
        'whatsNew': 'Check the map',
      });
    });

    test('updates the existing one', () async {
      asc
        ..on(
          'GET',
          '/v1/builds/b7/betaBuildLocalizations',
          (_) => (
            status: 200,
            body: FakeAsc.doc([
              FakeAsc.resource('betaBuildLocalizations', 'l1', {
                'locale': 'ar',
              }),
            ]),
          ),
        )
        ..on(
          'PATCH',
          '/v1/betaBuildLocalizations/l1',
          (_) => (
            status: 200,
            body: FakeAsc.doc(FakeAsc.resource('betaBuildLocalizations', 'l1')),
          ),
        );
      await run(['what-to-test', 'Push', '--locale', 'ar']);
      expect(
        (asc.bodies('PATCH', '/v1/betaBuildLocalizations/l1').single['data']!
            as Map)['attributes'],
        {'whatsNew': 'Push'},
      );
      expect(out.toString(), contains('Updated'));
    });
  });

  group('AC-020-6 testers', () {
    test('invites new testers and adds existing ones to the group', () async {
      asc
        ..on('POST', '/v1/betaTesters', (request) {
          final email =
              (((jsonDecode(request.body) as Map)['data'] as Map)['attributes']
                  as Map)['email'];
          return email == 'old@example.com'
              ? (
                  status: 409,
                  body: {
                    'errors': [
                      {'detail': 'exists'},
                    ],
                  },
                )
              : (
                  status: 201,
                  body: FakeAsc.doc(FakeAsc.resource('betaTesters', 't-new')),
                );
        })
        ..on(
          'GET',
          '/v1/betaTesters',
          (_) => (
            status: 200,
            body: FakeAsc.doc([FakeAsc.resource('betaTesters', 't-old')]),
          ),
        )
        ..on(
          'POST',
          '/v1/betaGroups/g1/relationships/betaTesters',
          (_) => (status: 204, body: null),
        );
      await run([
        'testers',
        'add',
        'new@example.com',
        'old@example.com',
        '--group',
        'QA',
      ]);
      final created = asc.bodies('POST', '/v1/betaTesters');
      expect(
        ((created.first['data']! as Map)['relationships'] as Map)['betaGroups'],
        {
          'data': [
            {'type': 'betaGroups', 'id': 'g1'},
          ],
        },
      );
      expect(
        asc
            .bodies('POST', '/v1/betaGroups/g1/relationships/betaTesters')
            .single,
        {
          'data': [
            {'type': 'betaTesters', 'id': 't-old'},
          ],
        },
      );
      expect(out.toString(), contains('Invited new@example.com'));
      expect(out.toString(), contains('existing tester old@example.com'));
    });

    test('lists a group’s testers', () async {
      asc.on(
        'GET',
        '/v1/betaGroups/g1/betaTesters',
        (_) => (
          status: 200,
          body: FakeAsc.doc([
            FakeAsc.resource('betaTesters', 't1', {
              'email': 'qa@example.com',
              'firstName': 'Q',
              'state': 'INSTALLED',
            }),
          ]),
        ),
      );
      await run(['testers', 'list', '--group', 'QA', '--json']);
      final tester = (json()['testers']! as List).single as Map;
      expect(tester['email'], 'qa@example.com');
      expect(tester['state'], 'INSTALLED');
    });

    test('rejects something that is not an email', () {
      expect(
        run(['testers', 'add', 'nobody', '--group', 'QA']),
        throwsA(isA<UsageException>()),
      );
    });
  });

  group('AC-020-7 compliance', () {
    test('answers no non-exempt encryption', () async {
      asc.on(
        'PATCH',
        '/v1/builds/b7',
        (_) =>
            (status: 200, body: FakeAsc.doc(FakeAsc.resource('builds', 'b7'))),
      );
      await run(['compliance', '--no-encryption']);
      expect(asc.bodies('PATCH', '/v1/builds/b7').single, {
        'data': {
          'type': 'builds',
          'id': 'b7',
          'attributes': {'usesNonExemptEncryption': false},
        },
      });
    });

    test('needs exactly one answer', () {
      expect(run(['compliance']), throwsA(isA<UsageException>()));
    });
  });

  group('AC-020-8 external testing information', () {
    test('creates the beta app localization', () async {
      asc
        ..on(
          'GET',
          '/v1/betaAppLocalizations',
          (_) => (status: 200, body: FakeAsc.doc([])),
        )
        ..on(
          'POST',
          '/v1/betaAppLocalizations',
          (_) => (
            status: 201,
            body: FakeAsc.doc(FakeAsc.resource('betaAppLocalizations', 'a1')),
          ),
        );
      await run([
        'app-info',
        '--description',
        'Sweets',
        '--feedback-email',
        'qa@example.com',
      ]);
      final data =
          asc.bodies('POST', '/v1/betaAppLocalizations').single['data']! as Map;
      expect(data['attributes'], {
        'locale': 'en-US',
        'description': 'Sweets',
        'feedbackEmail': 'qa@example.com',
      });
    });

    test('review details never echo the demo password', () async {
      asc
        ..on(
          'GET',
          '/v1/apps/app1/betaAppReviewDetail',
          (_) => (
            status: 200,
            body: FakeAsc.doc(FakeAsc.resource('betaAppReviewDetails', 'app1')),
          ),
        )
        ..on(
          'PATCH',
          '/v1/betaAppReviewDetails/app1',
          (_) => (
            status: 200,
            body: FakeAsc.doc(FakeAsc.resource('betaAppReviewDetails', 'app1')),
          ),
        );
      await run([
        'review-info',
        '--contact-email',
        'lead@example.com',
        '--demo-user',
        'demo',
        '--demo-password',
        'super-secret',
      ]);
      final attributes =
          (asc.bodies('PATCH', '/v1/betaAppReviewDetails/app1').single['data']!
                  as Map)['attributes']
              as Map;
      expect(attributes['demoAccountPassword'], 'super-secret');
      expect(attributes['demoAccountRequired'], true);
      expect(out.toString(), isNot(contains('super-secret')));
    });
  });

  group('AC-020-9 review submission and public link', () {
    test('submits the newest build', () async {
      asc.on(
        'POST',
        '/v1/betaAppReviewSubmissions',
        (_) => (
          status: 201,
          body: FakeAsc.doc(
            FakeAsc.resource('betaAppReviewSubmissions', 's1', {
              'betaReviewState': 'WAITING_FOR_REVIEW',
            }),
          ),
        ),
      );
      await run(['submit']);
      expect(
        ((asc.bodies('POST', '/v1/betaAppReviewSubmissions').single['data']!
                as Map)['relationships']
            as Map)['build'],
        {
          'data': {'type': 'builds', 'id': 'b7'},
        },
      );
      expect(out.toString(), contains('WAITING_FOR_REVIEW'));
    });

    test('turns the public link on and prints it', () async {
      asc.on(
        'PATCH',
        '/v1/betaGroups/g2',
        (_) => (
          status: 200,
          body: FakeAsc.doc(
            FakeAsc.resource('betaGroups', 'g2', {
              'name': 'Public',
              'isInternalGroup': false,
              'publicLinkEnabled': true,
              'publicLink': 'https://testflight.apple.com/join/abc',
            }),
          ),
        ),
      );
      await run(['public-link', '--group', 'Public', '--limit', '100']);
      expect(
        (asc.bodies('PATCH', '/v1/betaGroups/g2').single['data']!
            as Map)['attributes'],
        {
          'publicLinkEnabled': true,
          'publicLinkLimitEnabled': true,
          'publicLinkLimit': 100,
        },
      );
      expect(out.toString(), contains('join/abc'));
    });

    test('an internal group has no public link', () {
      expect(
        run(['public-link', '--group', 'QA']),
        throwsA(isA<UsageException>()),
      );
    });
  });
}
