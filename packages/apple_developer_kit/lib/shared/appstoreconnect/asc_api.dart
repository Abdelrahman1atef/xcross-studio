// studio: 019 — generic App Store Connect API access (JSON:API) for upload,
// TestFlight and App Store submission (specs/019…021).
import 'dart:convert';

import 'package:apple_developer_kit/shared/appstoreconnect/asc_client.dart';
import 'package:apple_developer_kit/shared/appstoreconnect/asc_config.dart';
import 'package:apple_developer_kit/src/shared/appstoreconnect/asc_jwt.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// One JSON:API resource.
@immutable
final class AscResource {
  const AscResource({
    required this.id,
    required this.type,
    this.attributes = const {},
    this.relationships = const {},
  });

  factory AscResource.fromJson(Map<String, dynamic> json) => AscResource(
    id: '${json['id']}',
    type: '${json['type']}',
    attributes: switch (json['attributes']) {
      final Map<dynamic, dynamic> map => map.cast<String, dynamic>(),
      _ => const {},
    },
    relationships: switch (json['relationships']) {
      final Map<dynamic, dynamic> map => map.cast<String, dynamic>(),
      _ => const {},
    },
  );

  final String id;
  final String type;
  final Map<String, dynamic> attributes;
  final Map<String, dynamic> relationships;

  /// A string attribute, or null.
  String? string(String name) => switch (attributes[name]) {
    final String value => value,
    _ => null,
  };

  /// The id of a to-one relationship's `data`, when included.
  String? relatedId(String name) => switch (relationships[name]) {
    {'data': {'id': final String id}} => id,
    _ => null,
  };
}

/// A thin authenticated client for any App Store Connect API path, with a
/// fresh JWT per request (the same signing as `AscClient`).
final class AscApi {
  /// [token] returns a bearer token per request (tests pass a fixed one).
  AscApi({
    required Future<String> Function() token,
    required http.Client httpClient,
    Uri? baseUrl,
  }) : _http = httpClient,
       _baseUrl = baseUrl ?? Uri.parse('https://api.appstoreconnect.apple.com'),
       _token = token;

  /// Signed with an API key, a fresh JWT per request (as `AscClient`).
  factory AscApi.fromCredentials(
    AscCredentials credentials, {
    required http.Client httpClient,
  }) =>
      AscApi(token: () => AscJwt.generate(credentials), httpClient: httpClient);

  final http.Client _http;
  final Uri _baseUrl;
  final Future<String> Function() _token;

  /// The plain HTTP client, for presigned upload URLs that must not carry
  /// the API token.
  http.Client get httpClient => _http;

  Uri _uri(String path, [Map<String, String>? query]) {
    final relative = Uri.parse(path);
    return _baseUrl.replace(
      path: relative.path,
      queryParameters: {...relative.queryParameters, ...?query}.isEmpty
          ? null
          : {...relative.queryParameters, ...?query},
    );
  }

  Future<Map<String, String>> _headers() async => {
    'Authorization': 'Bearer ${await _token()}',
    'Content-Type': 'application/json',
  };

  /// `GET path`; the decoded document.
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
  }) async =>
      _decode(await _http.get(_uri(path, query), headers: await _headers()));

  /// The resources of a collection at [path], following `links.next`.
  Future<List<AscResource>> getAll(
    String path, {
    Map<String, String>? query,
    int maxPages = 20,
  }) async {
    final resources = <AscResource>[];
    var next = _uri(path, query);
    for (var page = 0; page < maxPages; page++) {
      final document = _decode(
        await _http.get(next, headers: await _headers()),
      );
      resources.addAll(dataList(document));
      final link = switch (document['links']) {
        {'next': final String value} when value.isNotEmpty => value,
        _ => null,
      };
      if (link == null) break;
      next = Uri.parse(link);
    }
    return resources;
  }

  /// `POST path` with a JSON body.
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async => _decode(
    await _http.post(
      _uri(path),
      headers: await _headers(),
      body: jsonEncode(body),
    ),
  );

  /// `PATCH path` with a JSON body.
  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body,
  ) async => _decode(
    await _http.patch(
      _uri(path),
      headers: await _headers(),
      body: jsonEncode(body),
    ),
  );

  /// `DELETE path`, with an optional relationship body.
  Future<void> delete(String path, [Map<String, dynamic>? body]) async {
    final request = http.Request('DELETE', _uri(path))
      ..headers.addAll(await _headers());
    if (body != null) request.body = jsonEncode(body);
    _decode(await http.Response.fromStream(await _http.send(request)));
  }

  void close() => _http.close();

  /// The primary resource of a document.
  static AscResource data(Map<String, dynamic> document) =>
      AscResource.fromJson((document['data'] as Map).cast<String, dynamic>());

  /// The resources of a collection document.
  static List<AscResource> dataList(Map<String, dynamic> document) =>
      _resources(document['data'] as Object?);

  /// The `included` resources of a document.
  static List<AscResource> included(Map<String, dynamic> document) =>
      _resources(document['included'] as Object?);

  static List<AscResource> _resources(Object? list) => [
    if (list is List<Object?>)
      for (final entry in list)
        if (entry is Map) AscResource.fromJson(entry.cast<String, dynamic>()),
  ];

  /// Decodes a JSON:API response; throws [AppleApiError] with Apple's
  /// `errors[].detail` for non-2xx statuses.
  static Map<String, dynamic> _decode(http.Response response) {
    final Object? decoded = response.body.isEmpty
        ? null
        : _tryJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppleApiError(
        response.statusCode,
        'App Store Connect API error (HTTP ${response.statusCode}): '
        '${errorDetail(decoded) ?? response.body}',
      );
    }
    return decoded is Map ? decoded.cast<String, dynamic>() : const {};
  }

  static Object? _tryJson(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  /// Every `errors[]` entry's detail (or title), joined.
  static String? errorDetail(Object? decoded) {
    if (decoded case {'errors': final List<dynamic> errors}) {
      final parts = [
        for (final error in errors)
          if (error is Map && (error['detail'] ?? error['title']) != null)
            '${error['detail'] ?? error['title']}',
      ];
      return parts.isEmpty ? null : parts.join('; ');
    }
    return null;
  }
}

/// Finds the App Store Connect app for a bundle ID.
abstract final class AscApps {
  /// The app record for [bundleId], or null when App Store Connect has none.
  static Future<AscResource?> findByBundleId(
    AscApi api,
    String bundleId,
  ) async {
    final document = await api.get(
      '/v1/apps',
      query: {'filter[bundleId]': bundleId, 'limit': '10'},
    );
    for (final app in AscApi.dataList(document)) {
      if (app.string('bundleId') == bundleId) return app;
    }
    return null;
  }
}
