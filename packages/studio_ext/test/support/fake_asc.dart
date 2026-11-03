// studio: 019–021 — a scripted App Store Connect API for command tests.
import 'dart:async';
import 'dart:convert';

import 'package:apple_developer_kit/shared/appstoreconnect/asc_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meta/meta.dart';

/// Answers a request with a status and JSON body.
@internal
typedef FakeAscHandler =
    FutureOr<({int status, Object? body})> Function(http.Request request);

/// Routes `METHOD /path` (query ignored) to handlers and records every
/// request. Unrouted requests answer 404 with an App Store Connect error.
@internal
final class FakeAsc {
  final Map<String, FakeAscHandler> routes = {};
  final List<http.Request> requests = [];

  /// Adds a route; [path] may end with `*` to match a prefix.
  void on(String method, String path, FakeAscHandler handler) =>
      routes['$method $path'] = handler;

  /// A JSON:API document with [data].
  static Map<String, Object?> doc(Object? data, {List<Object?>? included}) => {
    'data': data,
    'included': ?included,
  };

  /// One resource.
  static Map<String, Object?> resource(
    String type,
    String id, [
    Map<String, Object?> attributes = const {},
    Map<String, Object?> relationships = const {},
  ]) => {
    'type': type,
    'id': id,
    'attributes': attributes,
    'relationships': relationships,
  };

  /// The JSON bodies sent to `METHOD path`, decoded.
  List<Map<String, Object?>> bodies(String method, String path) => [
    for (final request in requests)
      if (request.method == method && request.url.path == path)
        (jsonDecode(request.body) as Map).cast<String, Object?>(),
  ];

  http.Client get client => MockClient((request) async {
    requests.add(request);
    final key = '${request.method} ${request.url.path}';
    var handler = routes[key];
    if (handler == null) {
      for (final MapEntry(key: route, value: candidate) in routes.entries) {
        if (route.endsWith('*') &&
            key.startsWith(route.substring(0, route.length - 1))) {
          handler = candidate;
          break;
        }
      }
    }
    if (handler == null) {
      return http.Response(
        jsonEncode({
          'errors': [
            {'status': '404', 'detail': 'No fake route for $key'},
          ],
        }),
        404,
      );
    }
    final (:status, :body) = await handler(request);
    return http.Response(body == null ? '' : jsonEncode(body), status);
  });

  /// An API session over this fake.
  AscApi api() => AscApi(token: () async => 'test-token', httpClient: client);
}
