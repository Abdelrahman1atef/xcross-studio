// studio: 021 — `xcross appstore …` (specs/021-app-store-submission).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:cli_kit/composition/native_host.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/appstore/appstore_command.dart';
import 'package:test/test.dart';

import '../../support/fake_asc.dart';

/// A PNG header with an `IHDR` of [width]×[height] (enough for the size
/// check; the bytes are not a drawable image).
@internal
Uint8List png(int width, int height) {
  final data = ByteData(33)
    ..setUint32(8, 13)
    ..setUint32(16, width)
    ..setUint32(20, height);
  final bytes = data.buffer.asUint8List()
    ..setAll(0, const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    ..setAll(12, 'IHDR'.codeUnits);
  return bytes;
}

void main() {
  late Directory root;
  late FakeAsc asc;
  late StringBuffer out;

  setUp(() {
    root = Directory.systemTemp.createTempSync('appstore-021-');
    asc = FakeAsc();
    out = StringBuffer();
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: demo\n');
    Directory(
      p.join(root.path, 'ios', 'Runner.xcodeproj'),
    ).createSync(recursive: true);
    File(
      p.join(root.path, 'ios', 'Runner.xcodeproj', 'project.pbxproj'),
    ).writeAsStringSync(
      '{\n  PRODUCT_BUNDLE_IDENTIFIER = com.example.demo;\n'
      '  PRODUCT_BUNDLE_IDENTIFIER = com.example.demo.RunnerTests;\n}\n',
    );
    asc.on('GET', '/v1/apps', (request) {
      final bundle = request.url.queryParameters['filter[bundleId]'];
      return (
        status: 200,
        body: FakeAsc.doc([
          if (bundle == 'com.example.demo')
            FakeAsc.resource('apps', 'app1', {
              'name': 'Demo',
              'bundleId': 'com.example.demo',
              'sku': 'DEMO',
              'primaryLocale': 'en-US',
            }),
        ]),
      );
    });
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<void> run(List<String> args) =>
      (CommandRunner<void>('xcross', 'test')..addCommand(
            AppStoreCommand(
              openApi: () async => asc.api(),
              fileSystem: detectPlatformHost().fileSystem,
              paths: p.context,
              currentDirectory: () => root.path,
              write: out.write,
            ),
          ))
          .run(['appstore', ...args]);

  void editableVersion({String state = 'PREPARE_FOR_SUBMISSION'}) {
    asc.on(
      'GET',
      '/v1/apps/app1/appStoreVersions',
      (_) => (
        status: 200,
        body: FakeAsc.doc([
          FakeAsc.resource('appStoreVersions', 'v1', {
            'versionString': '1.0.0',
            'appStoreState': state,
            'copyright': '2026 Example',
            'createdDate': '2026-11-01T00:00:00Z',
          }),
        ]),
      ),
    );
  }

  group('AC-021-1 the app record', () {
    test('found by the project bundle ID', () async {
      await run(['app']);
      expect(out.toString(), contains('Apple ID        app1'));
      expect(out.toString(), contains('Bundle ID       com.example.demo'));
      expect(
        asc.requests.single.url.queryParameters['filter[bundleId]'],
        'com.example.demo',
      );
    });

    test('missing: the New App instructions, JSON, exit 1', () async {
      File(
        p.join(root.path, 'ios', 'Runner.xcodeproj', 'project.pbxproj'),
      ).writeAsStringSync(
        '{\n  PRODUCT_BUNDLE_IDENTIFIER = com.example.new;\n}\n',
      );
      await expectLater(run(['app', '--json']), throwsA(isA<CliError>()));
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(json['found'], isFalse);
      expect(json['bundleId'], 'com.example.new');
      expect(json['name'], 'demo');
      expect(json['sku'], 'NEW');
      expect(json['newAppUrl'], 'https://appstoreconnect.apple.com/apps');
    });

    test('--app-id reads that record', () async {
      asc.on(
        'GET',
        '/v1/apps/123',
        (_) => (
          status: 200,
          body: FakeAsc.doc(FakeAsc.resource('apps', '123', {'name': 'X'})),
        ),
      );
      await run(['app', '--app-id', '123']);
      expect(out.toString(), contains('Apple ID        123'));
    });
  });

  group('AC-021-2 the version', () {
    test('shows the editable version', () async {
      editableVersion();
      await run(['version']);
      expect(out.toString(), 'Version 1.0.0 (PREPARE_FOR_SUBMISSION)\n');
    });

    test('--create posts an iOS version for the app', () async {
      asc
        ..on(
          'GET',
          '/v1/apps/app1/appStoreVersions',
          (_) => (status: 200, body: FakeAsc.doc(<Object?>[])),
        )
        ..on(
          'POST',
          '/v1/appStoreVersions',
          (_) => (
            status: 201,
            body: FakeAsc.doc(
              FakeAsc.resource('appStoreVersions', 'v2', {
                'versionString': '1.1.0',
                'appStoreState': 'PREPARE_FOR_SUBMISSION',
              }),
            ),
          ),
        );
      await run(['version', '1.1.0', '--create', '--json']);
      final body = asc.bodies('POST', '/v1/appStoreVersions').single;
      expect(body, {
        'data': {
          'type': 'appStoreVersions',
          'attributes': {'platform': 'IOS', 'versionString': '1.1.0'},
          'relationships': {
            'app': {
              'data': {'type': 'apps', 'id': 'app1'},
            },
          },
        },
      });
      expect(jsonDecode(out.toString()), containsPair('created', true));
    });

    test('none without --create says how', () async {
      asc.on(
        'GET',
        '/v1/apps/app1/appStoreVersions',
        (_) => (status: 200, body: FakeAsc.doc(<Object?>[])),
      );
      await expectLater(
        run(['version']),
        throwsA(
          isA<CliError>().having(
            (e) => e.message,
            'message',
            contains('--create'),
          ),
        ),
      );
    });
  });

  void metadataRoutes() {
    editableVersion();
    asc
      ..on(
        'GET',
        '/v1/apps/app1/appInfos',
        (_) => (
          status: 200,
          body: FakeAsc.doc([
            FakeAsc.resource(
              'appInfos',
              'info1',
              {'state': 'PREPARE_FOR_SUBMISSION'},
              {
                'primaryCategory': {
                  'data': {'type': 'appCategories', 'id': 'UTILITIES'},
                },
              },
            ),
          ]),
        ),
      )
      ..on(
        'GET',
        '/v1/appInfos/info1/appInfoLocalizations',
        (_) => (
          status: 200,
          body: FakeAsc.doc([
            FakeAsc.resource('appInfoLocalizations', 'il1', {
              'locale': 'en-US',
              'name': 'Demo',
              'subtitle': 'Sweets',
            }),
          ]),
        ),
      )
      ..on(
        'GET',
        '/v1/appInfos/info1/ageRatingDeclaration',
        (_) => (
          status: 200,
          body: FakeAsc.doc(
            FakeAsc.resource('ageRatingDeclarations', 'ar1', {
              'gambling': false,
              'violenceCartoonOrFantasy': 'NONE',
            }),
          ),
        ),
      )
      ..on(
        'GET',
        '/v1/appStoreVersions/v1/appStoreVersionLocalizations',
        (_) => (
          status: 200,
          body: FakeAsc.doc([
            FakeAsc.resource('appStoreVersionLocalizations', 'vl1', {
              'locale': 'en-US',
              'description': 'Old text',
              'keywords': 'sweets,cake',
              'supportUrl': 'https://example.com/support',
            }),
          ]),
        ),
      );
  }

  group('AC-021-3 / AC-021-4 the metadata folder', () {
    test('pull writes the fastlane-style files', () async {
      metadataRoutes();
      await run(['metadata', 'pull']);
      String read(String relative) => File(
        p.joinAll([root.path, 'appstore', 'metadata', ...relative.split('/')]),
      ).readAsStringSync().trim();
      expect(read('en-US/name.txt'), 'Demo');
      expect(read('en-US/subtitle.txt'), 'Sweets');
      expect(read('en-US/description.txt'), 'Old text');
      expect(read('en-US/support_url.txt'), 'https://example.com/support');
      expect(read('copyright.txt'), '2026 Example');
      expect(read('primary_category.txt'), 'UTILITIES');
      expect(jsonDecode(read('age_rating.json')), {
        'gambling': false,
        'violenceCartoonOrFantasy': 'NONE',
      });
    });

    test('push creates missing localizations and patches only changes', () async {
      metadataRoutes();
      asc
        ..on(
          'PATCH',
          '/v1/appStoreVersionLocalizations/vl1',
          (_) => (status: 200, body: FakeAsc.doc(null)),
        )
        ..on(
          'POST',
          '/v1/appStoreVersionLocalizations',
          (_) => (status: 201, body: FakeAsc.doc(null)),
        )
        ..on(
          'POST',
          '/v1/appInfoLocalizations',
          (_) => (status: 201, body: FakeAsc.doc(null)),
        )
        ..on(
          'PATCH',
          '/v1/appInfos/info1',
          (_) => (status: 200, body: FakeAsc.doc(null)),
        )
        ..on(
          'PATCH',
          '/v1/ageRatingDeclarations/ar1',
          (_) => (status: 200, body: FakeAsc.doc(null)),
        );
      void put(String relative, String text) {
        final file = File(
          p.joinAll([
            root.path,
            'appstore',
            'metadata',
            ...relative.split('/'),
          ]),
        )..parent.createSync(recursive: true);
        file.writeAsStringSync(text);
      }

      put('en-US/name.txt', 'Demo\n');
      put('en-US/description.txt', 'New text\n');
      put('en-US/keywords.txt', 'sweets,cake\n');
      put('ar-SA/name.txt', 'Demo AR');
      put('ar-SA/description.txt', 'Arabic text');
      put('primary_category.txt', 'FOOD_AND_DRINK');
      put(
        'age_rating.json',
        '{"gambling": false, "violenceCartoonOrFantasy": "INFREQUENT_OR_MILD"}',
      );
      await run(['metadata', 'push']);

      expect(
        asc.bodies('PATCH', '/v1/appStoreVersionLocalizations/vl1').single,
        {
          'data': {
            'type': 'appStoreVersionLocalizations',
            'id': 'vl1',
            'attributes': {'description': 'New text'},
          },
        },
      );
      final created = asc
          .bodies('POST', '/v1/appStoreVersionLocalizations')
          .single;
      expect((created['data']! as Map)['attributes'], {
        'locale': 'ar-SA',
        'description': 'Arabic text',
      });
      expect(
        ((asc.bodies('POST', '/v1/appInfoLocalizations').single['data']!
                as Map)['attributes']!
            as Map)['name'],
        'Demo AR',
      );
      expect(asc.bodies('PATCH', '/v1/appInfoLocalizations/il1'), isEmpty);
      expect(
        jsonEncode(asc.bodies('PATCH', '/v1/appInfos/info1').single),
        contains('FOOD_AND_DRINK'),
      );
      expect(
        (asc.bodies('PATCH', '/v1/ageRatingDeclarations/ar1').single['data']!
            as Map)['attributes'],
        {'violenceCartoonOrFantasy': 'INFREQUENT_OR_MILD'},
      );
      expect(out.toString(), contains('Updated en-US description'));
      expect(
        out.toString(),
        contains('Created the version localization ar-SA'),
      );
    });

    test('push of an unchanged folder changes nothing', () async {
      metadataRoutes();
      final file = File(
        p.join(root.path, 'appstore', 'metadata', 'en-US', 'description.txt'),
      )..parent.createSync(recursive: true);
      file.writeAsStringSync('Old text\n');
      await run(['metadata', 'push']);
      expect(out.toString(), 'Nothing to change.\n');
      expect(asc.requests.where((r) => r.method != 'GET'), isEmpty);
    });
  });

  group('AC-021-5 / AC-021-6 screenshots', () {
    void shot(String locale, String type, String name, Uint8List bytes) {
      File(p.join(root.path, 'appstore', 'screenshots', locale, type, name))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(bytes);
    }

    test('a wrong size or display type stops before any request', () async {
      shot('en-US', 'APP_IPHONE_67', '1.png', png(1290, 2796));
      shot('en-US', 'APP_IPHONE_67', '2.png', png(1000, 2000));
      shot('en-US', 'APP_WATCH', '3.png', png(10, 10));
      await expectLater(
        run(['screenshots', 'push']),
        throwsA(
          isA<CliError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('2.png is 1000×2000'),
              contains('1290×2796'),
              contains('APP_WATCH: unknown display type'),
            ),
          ),
        ),
      );
      expect(asc.requests, isEmpty);
    });

    test('AC-021-6 reserve, upload to the operations Apple returns without '
        'the token, commit with the MD5; existing names are skipped', () async {
      final image = png(2796, 1290);
      shot('en-US', 'APP_IPHONE_67', 'home.png', image);
      shot('en-US', 'APP_IPHONE_67', 'old.png', png(1290, 2796));
      editableVersion();
      asc
        ..on(
          'GET',
          '/v1/appStoreVersions/v1/appStoreVersionLocalizations',
          (_) => (
            status: 200,
            body: FakeAsc.doc([
              FakeAsc.resource('appStoreVersionLocalizations', 'vl1', {
                'locale': 'en-US',
              }),
            ]),
          ),
        )
        ..on(
          'GET',
          '/v1/appStoreVersionLocalizations/vl1/appScreenshotSets',
          (_) => (status: 200, body: FakeAsc.doc(<Object?>[])),
        )
        ..on(
          'POST',
          '/v1/appScreenshotSets',
          (_) => (
            status: 201,
            body: FakeAsc.doc(FakeAsc.resource('appScreenshotSets', 'set1')),
          ),
        )
        ..on(
          'GET',
          '/v1/appScreenshotSets/set1/appScreenshots',
          (_) => (
            status: 200,
            body: FakeAsc.doc([
              FakeAsc.resource('appScreenshots', 's0', {'fileName': 'old.png'}),
            ]),
          ),
        )
        ..on(
          'POST',
          '/v1/appScreenshots',
          (_) => (
            status: 201,
            body: FakeAsc.doc(
              FakeAsc.resource('appScreenshots', 's1', {
                'uploadOperations': [
                  {
                    'method': 'PUT',
                    'url': 'https://upload.example.com/part1',
                    'offset': 0,
                    'length': image.length,
                    'requestHeaders': [
                      {'name': 'Content-Type', 'value': 'image/png'},
                    ],
                  },
                ],
              }),
            ),
          ),
        )
        ..on('PUT', '/part1', (_) => (status: 200, body: null))
        ..on(
          'PATCH',
          '/v1/appScreenshots/s1',
          (_) => (status: 200, body: FakeAsc.doc(null)),
        );
      await run(['screenshots', 'push']);

      final set = asc.bodies('POST', '/v1/appScreenshotSets').single;
      expect(
        ((set['data']! as Map)['attributes']! as Map)['screenshotDisplayType'],
        'APP_IPHONE_67',
      );
      final reservation = asc.bodies('POST', '/v1/appScreenshots').single;
      expect((reservation['data']! as Map)['attributes'], {
        'fileName': 'home.png',
        'fileSize': image.length,
      });
      final put = asc.requests.singleWhere((r) => r.method == 'PUT');
      expect(put.headers['Authorization'], isNull);
      expect(put.headers['Content-Type'], startsWith('image/png'));
      expect(put.bodyBytes, image);
      expect(
        (asc.bodies('PATCH', '/v1/appScreenshots/s1').single['data']!
            as Map)['attributes'],
        {'uploaded': true, 'sourceFileChecksum': md5.convert(image).toString()},
      );
      expect(out.toString(), contains('Skipped en-US/APP_IPHONE_67/old.png'));
      expect(out.toString(), contains('1 screenshot uploaded'));
    });
  });

  group('AC-021-7 attach', () {
    void build(String state) => asc.on(
      'GET',
      '/v1/builds',
      (request) => (
        status: 200,
        body: FakeAsc.doc([
          if (request.url.queryParameters['filter[version]'] == '7')
            FakeAsc.resource('builds', 'b7', {
              'version': '7',
              'processingState': state,
            }),
        ]),
      ),
    );

    test('a processed build is attached', () async {
      editableVersion();
      build('VALID');
      asc.on(
        'PATCH',
        '/v1/appStoreVersions/v1/relationships/build',
        (_) => (status: 204, body: null),
      );
      await run(['attach', '--build', '7']);
      expect(
        asc
            .bodies('PATCH', '/v1/appStoreVersions/v1/relationships/build')
            .single,
        {
          'data': {'type': 'builds', 'id': 'b7'},
        },
      );
      expect(out.toString(), 'Attached build 7 to 1.0.0.\n');
    });

    test('a build still processing is refused with its state', () async {
      editableVersion();
      build('PROCESSING');
      await expectLater(
        run(['attach', '--build', '7']),
        throwsA(
          isA<CliError>().having(
            (e) => e.message,
            'message',
            contains('PROCESSING'),
          ),
        ),
      );
    });
  });

  group('AC-021-8 / AC-021-10 submit', () {
    void reviewRoutes({required bool ready}) {
      metadataRoutes();
      asc
        ..on(
          'GET',
          '/v1/appStoreVersions/v1/build',
          (_) => (
            status: 200,
            body: FakeAsc.doc(
              ready ? FakeAsc.resource('builds', 'b7', {'version': '7'}) : null,
            ),
          ),
        )
        ..on(
          'GET',
          '/v1/appStoreVersionLocalizations/vl1/appScreenshotSets',
          (_) => (
            status: 200,
            body: FakeAsc.doc([
              if (ready) FakeAsc.resource('appScreenshotSets', 'set1'),
            ]),
          ),
        )
        ..on(
          'GET',
          '/v1/appScreenshotSets/set1/appScreenshots',
          (_) => (
            status: 200,
            body: FakeAsc.doc([FakeAsc.resource('appScreenshots', 's1')]),
          ),
        );
    }

    test('dry run lists the blockers and sends nothing', () async {
      reviewRoutes(ready: false);
      await run(['submit', '--dry-run']);
      final text = out.toString();
      expect(text, contains('blocker: No build is attached'));
      expect(text, contains('blocker: en-US has no screenshots'));
      expect(text, contains('App Privacy'));
      expect(text, contains('nothing was submitted'));
      expect(asc.requests.where((r) => r.method != 'GET'), isEmpty);
    });

    test('blockers stop a real submission', () async {
      reviewRoutes(ready: false);
      await expectLater(run(['submit']), throwsA(isA<CliError>()));
    });

    test('a ready version is submitted: submission, item, submitted', () async {
      reviewRoutes(ready: true);
      asc
        ..on(
          'GET',
          '/v1/reviewSubmissions',
          (_) => (status: 200, body: FakeAsc.doc(<Object?>[])),
        )
        ..on(
          'POST',
          '/v1/reviewSubmissions',
          (_) => (
            status: 201,
            body: FakeAsc.doc(FakeAsc.resource('reviewSubmissions', 'rs1')),
          ),
        )
        ..on(
          'POST',
          '/v1/reviewSubmissionItems',
          (_) => (status: 201, body: FakeAsc.doc(null)),
        )
        ..on(
          'PATCH',
          '/v1/reviewSubmissions/rs1',
          (_) => (
            status: 200,
            body: FakeAsc.doc(
              FakeAsc.resource('reviewSubmissions', 'rs1', {
                'state': 'WAITING_FOR_REVIEW',
              }),
            ),
          ),
        );
      await run(['submit']);
      final item = asc.bodies('POST', '/v1/reviewSubmissionItems').single;
      expect(
        jsonEncode(item),
        allOf(
          contains('"rs1"'),
          contains('"appStoreVersions"'),
          contains('"v1"'),
        ),
      );
      expect(
        (asc.bodies('PATCH', '/v1/reviewSubmissions/rs1').single['data']!
            as Map)['attributes'],
        {'submitted': true},
      );
      expect(
        out.toString(),
        contains('Submitted 1.0.0 for review (WAITING_FOR_REVIEW)'),
      );
    });
  });

  test('AC-021-9 status as JSON', () async {
    editableVersion();
    asc
      ..on(
        'GET',
        '/v1/appStoreVersions/v1/build',
        (_) => (
          status: 200,
          body: FakeAsc.doc(FakeAsc.resource('builds', 'b7', {'version': '7'})),
        ),
      )
      ..on(
        'GET',
        '/v1/reviewSubmissions',
        (_) => (
          status: 200,
          body: FakeAsc.doc([
            FakeAsc.resource('reviewSubmissions', 'rs1', {
              'state': 'IN_REVIEW',
              'submittedDate': '2026-11-03T10:00:00Z',
            }),
          ]),
        ),
      );
    await run(['status', '--json']);
    expect(jsonDecode(out.toString()), {
      'v': 1,
      'type': 'appstore_status',
      'version': '1.0.0',
      'state': 'PREPARE_FOR_SUBMISSION',
      'build': '7',
      'submissions': [
        {
          'id': 'rs1',
          'state': 'IN_REVIEW',
          'submittedDate': '2026-11-03T10:00:00Z',
        },
      ],
    });
  });

  test('AC-021-10 the group says what the API leaves out', () {
    final command = AppStoreCommand(
      openApi: () async => asc.api(),
      fileSystem: detectPlatformHost().fileSystem,
      paths: p.context,
      currentDirectory: () => root.path,
      write: out.write,
    );
    expect(
      command.description,
      contains('App Privacy, pricing and agreements'),
    );
  });

  test('Apple refusals name the role', () async {
    asc.on(
      'GET',
      '/v1/apps/app1/appStoreVersions',
      (_) => (
        status: 403,
        body: {
          'errors': [
            {'detail': 'The API key in use does not allow this request'},
          ],
        },
      ),
    );
    await expectLater(
      run(['version']),
      throwsA(
        isA<CliError>().having(
          (e) => e.message,
          'message',
          contains('Admin or'),
        ),
      ),
    );
  });
}
