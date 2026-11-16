import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meta/meta.dart';
import 'package:studio_ext/shared/events/ndjson_events.dart';
import 'package:studio_ext/src/shared/pods/pod_archive.dart';
import 'package:studio_ext/src/shared/pods/pod_source_downloader.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late HttpServer server;
  late http.Client client;
  late PodSourceDownloader downloader;
  late List<int> zip;
  var requests = 0;
  var failFirst = false;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pod-source-test-');
    zip = ZipEncoder().encode(
      Archive()..addFile(ArchiveFile.string('repo/Sources/A.m', 'source')),
    );
    requests = 0;
    failFirst = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      expect(request.headers.value('user-agent'), 'xcross');
      if (failFirst && requests == 1) {
        request.response.statusCode = 503;
      } else {
        request.response.add(zip);
      }
      await request.response.close();
    });
    client = http.Client();
    downloader = PodSourceDownloader(
      client: client,
      archive: const PodArchive(
        directoryFactory: Directory.new,
        fileFactory: File.new,
      ),
    );
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
    await root.delete(recursive: true);
  });

  test('AC-046-6 downloads, verifies sha256, and reports progress', () async {
    final progress = <int>[];
    final destination = Directory('${root.path}/source');
    await downloader.fetchHttp(
      PodHttpSource(
        url: Uri.parse('http://127.0.0.1:${server.port}/archive.zip'),
        sha256Value: sha256.convert(zip).toString(),
        flatten: true,
      ),
      destination,
      onProgress: (done, _) => progress.add(done),
    );
    expect(
      File('${destination.path}/Sources/A.m').readAsStringSync(),
      'source',
    );
    expect(progress.last, zip.length);
  });

  test('AC-046-6 sends download bytes through NDJSON build events', () async {
    final bytes = <int>[];
    final events = NdjsonEvents.fromEnvironment(const {
      'XCROSS_EVENTS': 'ndjson',
    }, bytes.addAll)!;
    final eventDownloader = PodSourceDownloader(
      client: client,
      archive: const PodArchive(
        directoryFactory: Directory.new,
        fileFactory: File.new,
      ),
      events: events,
    );
    await eventDownloader.fetchHttp(
      PodHttpSource(
        url: Uri.parse('http://127.0.0.1:${server.port}/archive.zip'),
      ),
      Directory('${root.path}/pod-Test'),
    );
    final records = utf8
        .decode(bytes)
        .trim()
        .split('\n')
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
    expect(records.first['name'], 'pod_download');
    expect(records.first['status'], 'start');
    expect(records.first['pod'], 'pod-Test');
    expect(
      records
          .where((record) => record['status'] == 'progress')
          .last['bytesDone'],
      zip.length,
    );
    expect(records.last['status'], 'done');
  });

  test('AC-046-6 refuses a checksum mismatch without publishing', () async {
    final destination = Directory('${root.path}/source');
    await expectLater(
      downloader.fetchHttp(
        PodHttpSource(
          url: Uri.parse('http://127.0.0.1:${server.port}/archive.zip'),
          sha1Value: 'bad',
        ),
        destination,
      ),
      throwsA(isA<PodDownloadFailed>()),
    );
    expect(destination.existsSync(), isFalse);
    expect(requests, 1);
  });

  test('AC-046-6 retries a transient HTTP error', () async {
    failFirst = true;
    final destination = Directory('${root.path}/source');
    await downloader.fetchHttp(
      PodHttpSource(
        url: Uri.parse('http://127.0.0.1:${server.port}/archive.zip'),
      ),
      destination,
    );
    expect(requests, 2);
    expect(File('${destination.path}/repo/Sources/A.m').existsSync(), isTrue);
  });

  test('AC-046-6 uses codeload for tagged GitHub sources', () {
    final url = downloader.githubArchiveUrl(
      PodGitSource(
        url: Uri.parse('https://github.com/owner/repo.git'),
        tag: 'v1.2.3',
      ),
    );
    expect(
      url.toString(),
      'https://codeload.github.com/owner/repo/tar.gz/v1.2.3',
    );
    expect(
      downloader.githubArchiveUrl(
        PodGitSource(
          url: Uri.parse('https://github.com/owner/repo'),
          branch: 'main',
        ),
      ),
      isNull,
    );
  });

  test('AC-046-6 gives a git missing message for an Azure source', () async {
    await expectLater(
      downloader.fetchGit(
        PodGitSource(
          url: Uri.parse('https://dev.azure.com/example/_git/repo'),
          tag: '1.0',
        ),
        Directory('${root.path}/azure'),
      ),
      throwsA(
        isA<PodDownloadFailed>().having(
          (error) => error.reason,
          'reason',
          contains('install Git'),
        ),
      ),
    );
  });

  test('AC-046-6 uses git for Azure tags and submodules', () async {
    final commands = <List<String>>[];
    final gitDownloader = PodSourceDownloader(
      client: client,
      archive: const PodArchive(
        directoryFactory: Directory.new,
        fileFactory: File.new,
      ),
      directoryFactory: Directory.new,
      gitRunner: (arguments, _) async {
        commands.add(arguments);
        return const PodGitResult(0, '');
      },
    );
    final destination = Directory('${root.path}/azure');
    await gitDownloader.fetchGit(
      PodGitSource(
        url: Uri.parse('https://dev.azure.com/example/_git/repo'),
        tag: '2.0.164',
        submodules: true,
      ),
      destination,
    );
    expect(commands.map((command) => command.first), [
      'clone',
      'rev-parse',
      'submodule',
    ]);
    expect(commands.first, containsAll(['--branch', '2.0.164']));
    expect(destination.existsSync(), isTrue);
  });

  test('AC-046-6 fetches an exact git commit', () async {
    final commands = <List<String>>[];
    final gitDownloader = PodSourceDownloader(
      client: client,
      archive: const PodArchive(
        directoryFactory: Directory.new,
        fileFactory: File.new,
      ),
      directoryFactory: Directory.new,
      gitRunner: (arguments, _) async {
        commands.add(arguments);
        return const PodGitResult(0, '');
      },
    );
    await gitDownloader.fetchGit(
      PodGitSource(
        url: Uri.parse('https://gitlab.com/example/repo'),
        commit: 'abc123',
      ),
      Directory('${root.path}/commit'),
    );
    expect(commands.map((command) => command.first), [
      'init',
      'remote',
      'fetch',
      'checkout',
    ]);
    expect(commands[2], contains('abc123'));
  });

  test('AC-046-6 resolves a branch to a commit before fetching', () async {
    final commands = <List<String>>[];
    const commit = '0123456789abcdef0123456789abcdef01234567';
    final gitDownloader = PodSourceDownloader(
      client: client,
      archive: const PodArchive(
        directoryFactory: Directory.new,
        fileFactory: File.new,
      ),
      directoryFactory: Directory.new,
      gitRunner: (arguments, _) async {
        commands.add(arguments);
        return PodGitResult(
          0,
          '',
          arguments.first == 'ls-remote' ? '$commit\trefs/heads/main' : '',
        );
      },
    );
    final resolved = await gitDownloader.fetchGit(
      PodGitSource(
        url: Uri.parse('https://gitlab.com/example/repo'),
        branch: 'main',
      ),
      Directory('${root.path}/branch'),
    );
    expect(resolved, commit);
    expect(commands.map((command) => command.first), [
      'ls-remote',
      'init',
      'remote',
      'fetch',
      'checkout',
    ]);
    expect(commands[3], contains(commit));
  });

  test('AC-046-6 falls back to git for export-ignore gaps', () async {
    final tar = TarEncoder().encode(
      Archive()..addFile(ArchiveFile.string('repo-1.0/README', 'incomplete')),
    );
    final archiveClient = MockClient(
      (_) async => http.Response.bytes(const GZipEncoder().encode(tar), 200),
    );
    final commands = <String>[];
    final gitDownloader = PodSourceDownloader(
      client: archiveClient,
      archive: const PodArchive(
        directoryFactory: Directory.new,
        fileFactory: File.new,
      ),
      directoryFactory: Directory.new,
      gitRunner: (arguments, _) async {
        commands.add(arguments.first);
        return const PodGitResult(0, '');
      },
    );
    final destination = Directory('${root.path}/github');
    await gitDownloader.fetchGit(
      PodGitSource(url: Uri.parse('https://github.com/owner/repo'), tag: '1.0'),
      destination,
      sourceComplete: (directory) =>
          File('${directory.path}/Sources/A.m').existsSync(),
    );
    expect(commands, ['clone', 'rev-parse']);
    expect(destination.existsSync(), isTrue);
    archiveClient.close();
  });

  test('AC-046-6 falls back to git for an LFS pointer', () async {
    final tar = TarEncoder().encode(
      Archive()..addFile(
        ArchiveFile.string(
          'repo-1.0/SDK',
          'version https://git-lfs.github.com/spec/v1\noid sha256:abc\nsize 5',
        ),
      ),
    );
    final archiveClient = MockClient(
      (_) async => http.Response.bytes(const GZipEncoder().encode(tar), 200),
    );
    final commands = <String>[];
    final gitDownloader = PodSourceDownloader(
      client: archiveClient,
      archive: const PodArchive(
        directoryFactory: Directory.new,
        fileFactory: File.new,
      ),
      directoryFactory: Directory.new,
      gitRunner: (arguments, _) async {
        commands.add(arguments.first);
        return const PodGitResult(0, '');
      },
    );
    await gitDownloader.fetchGit(
      PodGitSource(url: Uri.parse('https://github.com/owner/repo'), tag: '1.0'),
      Directory('${root.path}/github'),
    );
    expect(commands, ['clone', 'rev-parse']);
    archiveClient.close();
  });

  test('AC-046-6 retries an interrupted response stream', () async {
    final interrupted = InterruptingPodClient(zip);
    final retrying = PodSourceDownloader(
      client: interrupted,
      archive: const PodArchive(
        directoryFactory: Directory.new,
        fileFactory: File.new,
      ),
      retries: 2,
    );
    final destination = Directory('${root.path}/interrupted');
    await retrying.fetchHttp(
      PodHttpSource(url: Uri.parse('https://example.invalid/archive.zip')),
      destination,
    );
    expect(interrupted.requests, 2);
    expect(File('${destination.path}/repo/Sources/A.m').existsSync(), isTrue);
    interrupted.close();
  });

  test(
    'AC-046-6 times out a stalled response and removes the partial file',
    () async {
      final stalled = StallingPodClient();
      final waiting = PodSourceDownloader(
        client: stalled,
        archive: const PodArchive(
          directoryFactory: Directory.new,
          fileFactory: File.new,
        ),
        retries: 1,
        stallTimeout: const Duration(milliseconds: 20),
      );
      final destination = Directory('${root.path}/stalled');
      await expectLater(
        waiting.fetchHttp(
          PodHttpSource(url: Uri.parse('https://example.invalid/archive.zip')),
          destination,
        ),
        throwsA(isA<PodDownloadFailed>()),
      );
      expect(destination.existsSync(), isFalse);
      expect(
        root.listSync().where((entry) => entry.path.contains('.download-')),
        isEmpty,
      );
      stalled.close();
    },
  );

  test(
    'AC-046-6 partial fetch for big github.com repo downloads only matched globs',
    () async {
      final destination = Directory('${root.path}/tflite');
      final mockClient = MockClient((request) async {
        expect(request.headers['user-agent'], 'xcross');
        if (request.url.host == 'api.github.com') {
          if (request.url.path == '/repos/tensorflow/tensorflow') {
            return http.Response(
              jsonEncode({'size': 500000}), // 500 MB (in KB)
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
              '/repos/tensorflow/tensorflow/git/trees/v2.12.0') {
            return http.Response(
              jsonEncode({
                'sha': 'abc123commit',
                'tree': [
                  {
                    'path':
                        'tensorflow/lite/experimental/swift/Sources/TFLite.swift',
                    'type': 'blob',
                    'size': 123,
                  },
                  {
                    'path': 'tensorflow/core/kernels/heavy_kernel.cc',
                    'type': 'blob',
                    'size': 999999,
                  },
                  {'path': 'LICENSE', 'type': 'blob', 'size': 456},
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
        } else if (request.url.host == 'raw.githubusercontent.com') {
          if (request.url.path ==
              '/tensorflow/tensorflow/v2.12.0/tensorflow/lite/experimental/swift/Sources/TFLite.swift') {
            return http.Response('public class TFLite {}', 200);
          }
          if (request.url.path == '/tensorflow/tensorflow/v2.12.0/LICENSE') {
            return http.Response('Apache License', 200);
          }
        }
        return http.Response('Not found: ${request.url}', 404);
      });

      final partialDownloader = PodSourceDownloader(
        client: mockClient,
        archive: const PodArchive(
          directoryFactory: Directory.new,
          fileFactory: File.new,
        ),
        githubToken: 'test_token',
      );

      final commit = await partialDownloader.fetchGit(
        PodGitSource(
          url: Uri.parse('https://github.com/tensorflow/tensorflow.git'),
          tag: 'v2.12.0',
        ),
        destination,
        specGlobs: const ['tensorflow/lite/experimental/swift/Sources/*.swift'],
      );

      expect(commit, 'abc123commit');
      expect(
        File(
          '${destination.path}/tensorflow/lite/experimental/swift/Sources/TFLite.swift',
        ).existsSync(),
        isTrue,
      );
      expect(File('${destination.path}/LICENSE').existsSync(), isTrue);
      expect(
        File(
          '${destination.path}/tensorflow/core/kernels/heavy_kernel.cc',
        ).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'AC-046-6 partial fetch falls back to archive on HTTP 403 rate limit',
    () async {
      final destination = Directory('${root.path}/fallback-archive');
      final mockClient = MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response('API rate limit exceeded', 403);
        }
        if (request.url.host == 'codeload.github.com') {
          final tarGz = const GZipEncoder().encode(
            TarEncoder().encode(
              Archive()..addFile(
                ArchiveFile.string(
                  'repo-1.0/Sources/Fallback.m',
                  'int fallback = 1;',
                ),
              ),
            ),
          );
          return http.Response.bytes(tarGz, 200);
        }
        return http.Response('Not found', 404);
      });

      final fallbackDownloader = PodSourceDownloader(
        client: mockClient,
        archive: const PodArchive(
          directoryFactory: Directory.new,
          fileFactory: File.new,
        ),
        directoryFactory: Directory.new,
      );

      await fallbackDownloader.fetchGit(
        PodGitSource(
          url: Uri.parse('https://github.com/example/repo.git'),
          tag: '1.0',
        ),
        destination,
        specGlobs: const ['Sources/*.m'],
      );

      expect(destination.existsSync(), isTrue);
      expect(
        File('${destination.path}/Sources/Fallback.m').existsSync(),
        isTrue,
      );
    },
  );
}

@internal
final class InterruptingPodClient extends http.BaseClient {
  InterruptingPodClient(this.bytes);
  final List<int> bytes;
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    if (requests == 1) {
      return http.StreamedResponse(
        Stream<List<int>>.error(const SocketException('connection lost')),
        200,
      );
    }
    return http.StreamedResponse(Stream.value(bytes), 200);
  }
}

@internal
final class StallingPodClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream<List<int>>.periodic(const Duration(seconds: 10), (_) => [1]),
        200,
      );
}
