import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:studio_ext/shared/pods/pods_cdn.dart';
import 'package:test/test.dart';

void main() {
  late Directory cache;
  late HttpServer server;
  late PodsCdn cdn;
  final requests = <String>[];
  var indexBody = 'Example/1.0/2.0\n';
  var redirectSpec = false;

  setUp(() async {
    cache = await Directory.systemTemp.createTemp('pods-cdn-test-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    requests.clear();
    indexBody = 'Example/1.0/2.0\n';
    redirectSpec = false;
    server.listen((request) async {
      requests.add(request.uri.path);
      expect(request.headers.value('user-agent'), 'xcross');
      if (redirectSpec && request.uri.path.endsWith('Example.podspec.json')) {
        request.response.statusCode = 302;
        request.response.headers.set('location', '/spec.json');
      } else if (request.uri.path == '/spec.json' ||
          request.uri.path.endsWith('Example.podspec.json')) {
        request.response.write('{"name":"Example"}');
      } else if (request.uri.path.startsWith('/all_pods_versions_')) {
        request.response.write(indexBody);
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    cdn = PodsCdn(
      cacheRoot: cache,
      client: http.Client(),
      environment: {'XCROSS_PODS_CDN': 'http://127.0.0.1:${server.port}'},
      fileFactory: File.new,
    );
  });

  tearDown(() async {
    cdn.close();
    await server.close(force: true);
    await cache.delete(recursive: true);
  });

  test('AC-046-3 fetches mirror index and reuses fresh cache', () async {
    expect(await cdn.versions('Example'), ['1.0', '2.0']);
    expect(requests, hasLength(1));
    expect(await cdn.versions('Example'), ['1.0', '2.0']);
    expect(requests, hasLength(1));
    expect(cdn.key12('source'), hasLength(12));
    expect(cdn.cachedVersions('Example'), ['1.0', '2.0']);
  });

  test('AC-046-3 falls back to stale index when offline', () async {
    expect(await cdn.versions('Example'), ['1.0', '2.0']);
    final index = File('${cache.path}/index/${cdn.shard('Example')}.txt');
    await index.setLastModified(
      DateTime.now().subtract(const Duration(days: 3)),
    );
    await server.close(force: true);
    expect(await cdn.versions('Example'), ['1.0', '2.0']);
  });

  test('AC-046-3 caches a spec forever with its sha1', () async {
    final first = await cdn.spec('Example', '1.0');
    expect(first.json, '{"name":"Example"}');
    expect(first.sha1, hasLength(40));
    await server.close(force: true);
    expect((await cdn.spec('Example', '1.0')).sha1, first.sha1);
    expect(cdn.cachedSpec('Example', '1.0')!.sha1, first.sha1);
  });

  test('AC-046-3 follows a spec redirect', () async {
    redirectSpec = true;
    expect((await cdn.spec('Example', '1.0')).json, '{"name":"Example"}');
    expect(requests.last, '/spec.json');
  });

  test('AC-046-3 uses an injected environment proxy client', () async {
    final proxyClient = IOClient(
      HttpClient()..findProxy = (_) => 'PROXY 127.0.0.1:${server.port}',
    );
    final proxied = PodsCdn(
      cacheRoot: cache,
      client: proxyClient,
      environment: const {},
      baseUrl: Uri.parse('http://example.invalid'),
      fileFactory: File.new,
    );
    try {
      expect(await proxied.versions('Example'), ['1.0', '2.0']);
      expect(requests.single, startsWith('/all_pods_versions_'));
    } finally {
      proxied.close();
    }
  });

  test('AC-046-3 reports a missing pod as not_on_cdn', () {
    indexBody = 'Other/1.0\n';
    expect(cdn.versions('Example'), throwsA(isA<PodNotOnCdn>()));
    expect(cdn.spec('Missing', '1.0'), throwsA(isA<PodNotOnCdn>()));
  });
}
