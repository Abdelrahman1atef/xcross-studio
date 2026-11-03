// studio: 019 — generic App Store Connect API client.
import 'dart:convert';

import 'package:apple_developer_kit/shared/appstoreconnect/asc_api.dart';
import 'package:apple_developer_kit/shared/appstoreconnect/asc_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'sends the bearer token, follows links.next and parses resources',
    () async {
      final seen = <http.Request>[];
      final api = AscApi(
        token: () async => 'test-token',
        httpClient: MockClient((request) async {
          seen.add(request);
          if (request.url.queryParameters['cursor'] == null) {
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': '1',
                    'type': 'apps',
                    'attributes': {'bundleId': 'com.example.app'},
                  },
                ],
                'links': {
                  'next':
                      'https://api.appstoreconnect.apple.com/v1/apps?cursor=2',
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': '2',
                  'type': 'apps',
                  'attributes': {'bundleId': 'b'},
                },
              ],
            }),
            200,
          );
        }),
      );
      final apps = await api.getAll('/v1/apps', query: {'limit': '1'});
      expect(apps.map((a) => a.id), ['1', '2']);
      expect(seen.first.headers['Authorization'], 'Bearer test-token');
      expect(seen.first.url.queryParameters['limit'], '1');
      expect((await AscApps.findByBundleId(api, 'com.example.app'))?.id, '1');
    },
  );

  test('errors carry the status and Apple detail', () {
    final api = AscApi(
      token: () async => 't',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'errors': [
              {'title': 'Forbidden', 'detail': 'The role is not allowed'},
            ],
          }),
          403,
        ),
      ),
    );
    expect(
      api.post('/v1/buildUploads', const {}),
      throwsA(
        isA<AppleApiError>()
            .having((e) => e.statusCode, 'status', 403)
            .having((e) => e.message, 'message', contains('role is not')),
      ),
    );
  });

  test('relationships and attributes are readable', () {
    final resource = AscResource.fromJson(const {
      'id': 'b1',
      'type': 'builds',
      'attributes': {'version': '7'},
      'relationships': {
        'app': {
          'data': {'id': 'a1', 'type': 'apps'},
        },
      },
    });
    expect(resource.string('version'), '7');
    expect(resource.relatedId('app'), 'a1');
    expect(resource.string('missing'), isNull);
  });
}
