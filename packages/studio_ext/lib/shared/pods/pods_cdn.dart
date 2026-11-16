import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

final class PodNotOnCdn implements Exception {
  const PodNotOnCdn(this.pod);
  final String pod;
  @override
  String toString() => 'not_on_cdn: $pod';
}

final class CachedPodSpec {
  const CachedPodSpec(this.json, this.sha1);
  final String json;
  final String sha1;
}

/// CocoaPods trunk CDN reads. The caller supplies the engine cache's pods root.
final class PodsCdn {
  PodsCdn({
    required this.cacheRoot,
    required http.Client client,
    required Map<String, String> environment,
    required File Function(String) fileFactory,
    Uri? baseUrl,
    DateTime Function()? now,
  }) : _client = client,
       _fileFactory = fileFactory,
       _baseUrl =
           baseUrl ??
           Uri.parse(
             environment['XCROSS_PODS_CDN'] ?? 'https://cdn.cocoapods.org',
           ),
       _now = now ?? DateTime.now;

  final Directory cacheRoot;
  final http.Client _client;
  final File Function(String) _fileFactory;
  final Uri _baseUrl;
  final DateTime Function() _now;

  String shard(String pod) {
    final hex = md5.convert(utf8.encode(pod)).toString();
    return '${hex[0]}_${hex[1]}_${hex[2]}';
  }

  String key12(String input) =>
      sha1.convert(utf8.encode(input)).toString().substring(0, 12);

  Future<List<String>> versions(String pod) async {
    final file = _fileFactory(
      path.join(cacheRoot.path, 'index', '${shard(pod)}.txt'),
    );
    final fresh =
        file.existsSync() &&
        _now().difference(file.lastModifiedSync()) < const Duration(hours: 24);
    String body;
    if (fresh) {
      body = await file.readAsString();
    } else {
      try {
        body = await _get('all_pods_versions_${shard(pod)}.txt', pod);
        await file.parent.create(recursive: true);
        await file.writeAsString(body);
      } on Object {
        if (!file.existsSync()) rethrow;
        body = await file.readAsString();
      }
    }
    for (final line in const LineSplitter().convert(body)) {
      final separator = line.indexOf('/');
      if (separator >= 0 && line.substring(0, separator) == pod) {
        return line.substring(separator + 1).split('/');
      }
    }
    throw PodNotOnCdn(pod);
  }

  /// Reads only the local shard index; status/check never call the network.
  List<String>? cachedVersions(String pod) {
    final file = _fileFactory(
      path.join(cacheRoot.path, 'index', '${shard(pod)}.txt'),
    );
    if (!file.existsSync()) return null;
    for (final line in const LineSplitter().convert(file.readAsStringSync())) {
      final separator = line.indexOf('/');
      if (separator >= 0 && line.substring(0, separator) == pod) {
        return line.substring(separator + 1).split('/');
      }
    }
    return null;
  }

  Future<CachedPodSpec> spec(String pod, String version) async {
    if (!RegExp(r'^[A-Za-z0-9_.+-]+$').hasMatch(pod) ||
        !RegExp(r'^[A-Za-z0-9_.+-]+$').hasMatch(version)) {
      throw ArgumentError('Invalid pod or version');
    }
    final file = _fileFactory(
      path.join(cacheRoot.path, 'specs', pod, '$version.json'),
    );
    final body = file.existsSync()
        ? await file.readAsString()
        : await _get(
            'Specs/${shard(pod).replaceAll('_', '/')}/$pod/$version/$pod.podspec.json',
            pod,
          );
    if (!file.existsSync()) {
      await file.parent.create(recursive: true);
      await file.writeAsString(body);
    }
    return CachedPodSpec(body, sha1.convert(utf8.encode(body)).toString());
  }

  CachedPodSpec? cachedSpec(String pod, String version) {
    if (!RegExp(r'^[A-Za-z0-9_.+-]+$').hasMatch(pod) ||
        !RegExp(r'^[A-Za-z0-9_.+-]+$').hasMatch(version)) {
      throw ArgumentError('Invalid pod or version');
    }
    final file = _fileFactory(
      path.join(cacheRoot.path, 'specs', pod, '$version.json'),
    );
    if (!file.existsSync()) return null;
    final body = file.readAsStringSync();
    return CachedPodSpec(body, sha1.convert(utf8.encode(body)).toString());
  }

  Future<String> _get(String relative, String pod) async {
    var uri = _baseUrl.resolve(relative);
    for (var redirects = 0; redirects < 6; redirects++) {
      final request = http.Request('GET', uri)
        ..headers['User-Agent'] = 'xcross'
        ..followRedirects = false;
      final response = await http.Response.fromStream(
        await _client.send(request),
      );
      if (response.statusCode == 404) throw PodNotOnCdn(pod);
      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.headers['location'];
        if (location == null) {
          throw const HttpException('CDN redirect has no location');
        }
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode != 200) {
        throw HttpException('CocoaPods CDN returned ${response.statusCode}');
      }
      return response.body;
    }
    throw const HttpException('Too many CocoaPods CDN redirects');
  }

  void close() => _client.close();
}
