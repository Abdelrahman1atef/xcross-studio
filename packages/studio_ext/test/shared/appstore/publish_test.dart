// studio: 019 — `xcross publish` (specs/019-upload-processing).
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:args/command_runner.dart';
import 'package:cli_kit/composition/native_host.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:studio_ext/shared/appstore/build_numbers.dart';
import 'package:studio_ext/shared/appstore/command_exit.dart';
import 'package:studio_ext/shared/appstore/publish_command.dart';
import 'package:studio_ext/src/shared/appstore/transporter.dart';
import 'package:test/test.dart';

import '../../support/fake_asc.dart';

void main() {
  late Directory root;
  late FakeAsc asc;
  late StringBuffer out;
  late List<int> payload;

  setUp(() {
    root = Directory.systemTemp.createTempSync('publish-');
    asc = FakeAsc();
    out = StringBuffer();
    final info =
        PropertyListSerialization.stringWithPropertyList(<String, Object>{
          'CFBundleIdentifier': 'com.example.app',
          'CFBundleShortVersionString': '1.2.3',
          'CFBundleVersion': '7',
          'CFBundleExecutable': 'Runner',
          'MinimumOSVersion': '15.0',
          'DTSDKName': 'iphoneos27.1',
        });
    final archive = Archive()
      ..addFile(ArchiveFile.string('Payload/Runner.app/Info.plist', info))
      ..addFile(
        ArchiveFile.bytes('Payload/Runner.app/Runner', List.filled(64, 7)),
      );
    payload = ZipEncoder().encode(archive);
    final dir = Directory(p.join(root.path, 'build', 'xcross-ios', 'ipa'))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'Runner.ipa')).writeAsBytesSync(payload);
  });
  tearDown(() => root.deleteSync(recursive: true));

  int half() => payload.length ~/ 2;

  void routeApp({List<Object?> builds = const []}) {
    asc
      ..on(
        'GET',
        '/v1/apps',
        (_) => (
          status: 200,
          body: FakeAsc.doc([
            FakeAsc.resource('apps', 'app-1', {
              'bundleId': 'com.example.app',
              'name': 'Example',
            }),
          ]),
        ),
      )
      ..on(
        'GET',
        '/v1/builds',
        (_) => (status: 200, body: FakeAsc.doc(builds)),
      );
  }

  void routeUpload({int failPart2 = 0}) {
    var part2Failures = 0;
    asc
      ..on(
        'POST',
        '/v1/buildUploads',
        (_) => (
          status: 201,
          body: FakeAsc.doc(FakeAsc.resource('buildUploads', 'u1')),
        ),
      )
      ..on(
        'POST',
        '/v1/buildUploadFiles',
        (_) => (
          status: 201,
          body: FakeAsc.doc(
            FakeAsc.resource('buildUploadFiles', 'f1', {
              'uploadOperations': [
                {
                  'method': 'PUT',
                  'url': 'https://upload.example/part1',
                  'offset': 0,
                  'length': half(),
                  'partNumber': 1,
                  'requestHeaders': [
                    {
                      'name': 'Content-Type',
                      'value': 'application/octet-stream',
                    },
                  ],
                },
                {
                  'method': 'PUT',
                  'url': 'https://upload.example/part2',
                  'offset': half(),
                  'length': payload.length - half(),
                  'partNumber': 2,
                  'requestHeaders': <Object?>[],
                },
              ],
            }),
          ),
        ),
      )
      ..on('PUT', '/part1', (_) => (status: 200, body: null))
      ..on('PUT', '/part2', (_) {
        if (part2Failures < failPart2) {
          part2Failures++;
          return (status: 500, body: null);
        }
        return (status: 200, body: null);
      })
      ..on(
        'PATCH',
        '/v1/buildUploadFiles/f1',
        (_) => (
          status: 200,
          body: FakeAsc.doc(FakeAsc.resource('buildUploadFiles', 'f1')),
        ),
      );
  }

  Future<void> run(List<String> args) =>
      (CommandRunner<void>('xcross', 't')..addCommand(
            PublishCommand(
              openApi: () async => asc.api(),
              loadCredentials: () =>
                  throw StateError('no credentials in tests'),
              fileSystem: detectPlatformHost().fileSystem,
              currentDirectory: () => root.path,
              write: out.write,
              runProcess: (executable, arguments, {workingDirectory}) async =>
                  ProcessResult(0, 1, '', 'not a repository'),
              temporaryRoot: Directory.systemTemp.path,
              pollInterval: Duration.zero,
              sleep: (_) async {},
            ),
          ))
          .run(['publish', ...args]);

  List<http.Request> sent(String method, String path) => [
    for (final request in asc.requests)
      if (request.method == method && request.url.path == path) request,
  ];

  test('AC-019-1 creates, reserves, sends every part and commits', () async {
    routeApp();
    routeUpload();
    await run([]);

    final create = asc.bodies('POST', '/v1/buildUploads').single;
    expect((create['data']! as Map)['attributes'], {
      'cfBundleShortVersionString': '1.2.3',
      'cfBundleVersion': '7',
      'platform': 'IOS',
    });
    final reserve = asc.bodies('POST', '/v1/buildUploadFiles').single;
    expect(
      ((reserve['data']! as Map)['attributes'] as Map)['fileSize'],
      payload.length,
    );
    expect(
      ((reserve['data']! as Map)['attributes'] as Map)['uti'],
      'com.apple.ipa',
    );

    final part1 = sent('PUT', '/part1').single;
    expect(part1.bodyBytes, payload.sublist(0, half()));
    expect(part1.headers['Authorization'], isNull, reason: 'no API token');
    expect(part1.headers['Content-Type'], 'application/octet-stream');
    expect(sent('PUT', '/part2').single.bodyBytes, payload.sublist(half()));

    final commit =
        (asc.bodies('PATCH', '/v1/buildUploadFiles/f1').single['data']!
                as Map)['attributes']
            as Map;
    expect(commit['uploaded'], isTrue);
    expect(
      ((commit['sourceFileChecksums'] as Map)['file'] as Map)['algorithm'],
      'MD5',
    );
    expect(out.toString(), contains('Uploading 1.2.3 (7) to Example'));
    expect(
      File(
        p.join(root.path, 'build', 'xcross-ios', '.publish-1.2.3-7.json'),
      ).existsSync(),
      isFalse,
    );
  });

  test('AC-019-2 a duplicate build number stops before any upload', () async {
    routeApp(
      builds: [
        FakeAsc.resource('builds', 'b1', {
          'version': '7',
          'processingState': 'VALID',
        }),
      ],
    );
    routeUpload();
    await expectLater(
      run([]),
      throwsA(
        isA<CommandExit>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('publish.duplicate_build'),
            contains('--build-number auto'),
          ),
        ),
      ),
    );
    expect(sent('POST', '/v1/buildUploads'), isEmpty);
  });

  group('AC-019-3 retries and resume', () {
    test('a failing part is retried', () async {
      routeApp();
      routeUpload(failPart2: 2);
      await run([]);
      expect(sent('PUT', '/part2'), hasLength(3));
    });

    test('an interrupted upload resumes the missing parts', () async {
      routeApp();
      routeUpload(failPart2: 99);
      await expectLater(run([]), throwsA(isA<CommandExit>()));
      final state = File(
        p.join(root.path, 'build', 'xcross-ios', '.publish-1.2.3-7.json'),
      );
      expect(state.existsSync(), isTrue);
      expect((jsonDecode(state.readAsStringSync()) as Map)['done'], [1]);

      asc = FakeAsc();
      routeApp();
      routeUpload();
      asc
        ..on(
          'GET',
          '/v1/buildUploads/u1',
          (_) => (
            status: 200,
            body: FakeAsc.doc(
              FakeAsc.resource('buildUploads', 'u1', {
                'state': {'state': 'AWAITING_UPLOAD'},
              }),
            ),
          ),
        )
        ..on('GET', '/v1/buildUploadFiles/f1', (request) async {
          final reserve = await asc.routes['POST /v1/buildUploadFiles']!(
            request,
          );
          return reserve;
        });
      await run([]);
      expect(sent('POST', '/v1/buildUploads'), isEmpty, reason: 'resumed');
      expect(sent('PUT', '/part1'), isEmpty);
      expect(sent('PUT', '/part2'), hasLength(1));
      expect(out.toString(), contains('Resuming the interrupted upload'));
    });
  });

  test('AC-019-4 a refused key names the role', () async {
    asc.on(
      'GET',
      '/v1/apps',
      (_) => (
        status: 403,
        body: {
          'errors': [
            {'detail': 'not allowed'},
          ],
        },
      ),
    );
    await expectLater(
      run([]),
      throwsA(
        isA<Exception>().having(
          (e) => '$e',
          'message',
          contains('Admin or App Manager'),
        ),
      ),
    );
  });

  group('AC-019-5 / AC-019-6 processing', () {
    void routeStates(List<String> uploadStates, List<String?> buildStates) {
      var u = 0;
      var b = 0;
      asc.on('GET', '/v1/buildUploads/u1', (_) {
        final state =
            uploadStates[u < uploadStates.length
                ? u++
                : uploadStates.length - 1];
        return (
          status: 200,
          body: FakeAsc.doc(
            FakeAsc.resource('buildUploads', 'u1', {
              'state': {
                'state': state,
                'warnings': [
                  {'code': 'ITMS-90078', 'description': 'Missing push'},
                ],
                if (state == 'FAILED')
                  'errors': [
                    {'code': 'ITMS-90725', 'description': 'SDK too old'},
                  ],
              },
            }),
          ),
        );
      });
      var duplicateCheckDone = false;
      asc.on('GET', '/v1/builds', (_) {
        if (!duplicateCheckDone) {
          duplicateCheckDone = true;
          return (status: 200, body: FakeAsc.doc(<Object?>[]));
        }
        final state =
            buildStates[b < buildStates.length ? b++ : buildStates.length - 1];
        return (
          status: 200,
          body: FakeAsc.doc([
            if (state != null)
              FakeAsc.resource('builds', 'b7', {'processingState': state}),
          ]),
        );
      });
    }

    test('--wait follows the upload and the build to VALID', () async {
      routeApp();
      routeUpload();
      routeStates(
        ['AWAITING_UPLOAD', 'PROCESSING', 'COMPLETE'],
        [null, 'PROCESSING', 'VALID'],
      );
      await run(['--wait', '--json']);
      final events = [
        for (final line in const LineSplitter().convert(out.toString()))
          jsonDecode(line) as Map,
      ];
      expect(events.where((e) => e['event'] == 'progress'), hasLength(2));
      expect(
        events
            .where((e) => e['event'] == 'state')
            .map((e) => e['upload'] ?? e['processing']),
        containsAllInOrder(['PROCESSING', 'COMPLETE', 'VALID']),
      );
      final published = events.lastWhere((e) => e['event'] == 'published');
      expect(published['processingState'], 'VALID');
      expect(
        ((published['issues'] as List).single as Map)['code'],
        'ITMS-90078',
      );

      final record =
          jsonDecode(
                File(
                  p.join(root.path, 'build', 'xcross-ios', 'release.json'),
                ).readAsStringSync(),
              )
              as Map;
      // AC-019-8
      expect(record['bundleId'], 'com.example.app');
      expect(record['version'], '1.2.3');
      expect(record['build'], '7');
      expect((record['ipa'] as Map)['sha256'], hasLength(64));
      expect((record['upload'] as Map)['state'], 'COMPLETE');
      expect((record['build_record'] as Map)['processingState'], 'VALID');
    });

    test('a FAILED upload lists Apple codes and fails', () async {
      routeApp();
      routeUpload();
      routeStates(['FAILED'], [null]);
      await expectLater(
        run(['--wait']),
        throwsA(
          isA<CommandExit>().having(
            (e) => e.message,
            'message',
            allOf(contains('publish.upload_failed'), contains('ITMS-90725')),
          ),
        ),
      );
    });

    test('a timeout exits 2', () async {
      routeApp();
      routeUpload();
      routeStates(['PROCESSING'], [null]);
      await expectLater(
        run(['--wait', '--timeout', '0']),
        throwsA(isA<CommandExit>().having((e) => e.exitCode, 'exit', 2)),
      );
    });
  });

  test('AC-019-7 build numbers', () async {
    expect(nextBuildNumber(local: 3, latest: 9), 10);
    expect(nextBuildNumber(local: 12, latest: 9), 12);
    expect(nextBuildNumber(local: 3, latest: null), 3);
    asc.on(
      'GET',
      '/v1/builds',
      (_) => (
        status: 200,
        body: FakeAsc.doc([
          FakeAsc.resource('builds', 'a', {'version': '8'}),
          FakeAsc.resource('builds', 'b', {'version': '11'}),
          FakeAsc.resource('builds', 'c', {'version': 'x'}),
        ]),
      ),
    );
    expect(await latestBuildNumber(asc.api(), 'app-1'), 11);
  });

  test('--build-number keep: the chosen number unless this version has it '
      'or a higher one', () async {
    // 2.0.0 (1) with build 1 uploaded becomes 2.0.0 (2).
    expect(keptBuildNumber(chosen: 1, existing: [1]), 2);
    // Free for this version: kept as chosen.
    expect(keptBuildNumber(chosen: 1, existing: []), 1);
    expect(keptBuildNumber(chosen: 15, existing: [9, 10]), 15);
    // Lower than the version's newest: App Store Connect refuses it, so one
    // past the newest (release.asc_build_not_higher).
    expect(keptBuildNumber(chosen: 2, existing: [1, 10]), 11);

    asc.on(
      'GET',
      '/v1/builds',
      (_) => (
        status: 200,
        body: FakeAsc.doc([
          FakeAsc.resource('builds', 'a', {'version': '1'}),
          FakeAsc.resource('builds', 'b', {'version': 'x'}),
        ]),
      ),
    );
    expect(await buildNumbersOfVersion(asc.api(), 'app-1', '2.0.0'), [1]);
    final query = asc.requests.last.url.queryParameters;
    expect(query['filter[app]'], 'app-1');
    expect(query['filter[preReleaseVersion.version]'], '2.0.0');
  });

  test('AC-019-9 Transporter is looked up, never downloaded', () {
    expect(
      Transporter.locate(const {
        'XCROSS_TRANSPORTER': '/opt/itms/iTMSTransporter',
      }, exists: (path) => path == '/opt/itms/iTMSTransporter'),
      '/opt/itms/iTMSTransporter',
    );
    expect(Transporter.locate(const {}, exists: (_) => false), isNull);
    expect(
      Transporter.arguments(
        ipa: 'a.ipa',
        keyId: 'K',
        issuerId: 'I',
        verify: true,
      ),
      containsAllInOrder([
        '-m',
        'verify',
        '-assetFile',
        'a.ipa',
        '-apiKey',
        'K',
        '-apiIssuer',
        'I',
      ]),
    );
  });
}
