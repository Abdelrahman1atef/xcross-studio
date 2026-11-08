// Feature 031: who an App Store Connect key belongs to.
import 'dart:convert';

import 'package:studio_ext/shared/auth/account_lookup.dart';
import 'package:test/test.dart';

import '../../support/fake_asc.dart';

void main() {
  late FakeAsc asc;
  setUp(() => asc = FakeAsc());

  test('AC-031-1 the Account Holder is read from the team users', () async {
    asc.on('GET', '/v1/users', (request) {
      expect(request.url.queryParameters['filter[roles]'], 'ACCOUNT_HOLDER');
      return (
        status: 200,
        body: FakeAsc.doc([
          FakeAsc.resource('users', 'u1', {
            'firstName': 'Test',
            'lastName': 'Holder',
            'username': 'holder@example.invalid',
          }),
        ]),
      );
    });
    asc.on(
      'GET',
      '/v1/bundleIds',
      (_) => (
        status: 200,
        body: FakeAsc.doc([
          FakeAsc.resource('bundleIds', 'b1', {'seedId': 'TEAM123456'}),
        ]),
      ),
    );
    final details = await lookupAccountDetails(asc.api());
    expect(details.holderName, 'Test Holder');
    expect(details.teamId, 'TEAM123456');
    expect(details.problem, isNull);
  });

  test(
    'AC-031-2 a key that may not read users is a note, not a failure',
    () async {
      asc.on(
        'GET',
        '/v1/users',
        (_) => (
          status: 403,
          body: {
            'errors': [
              {'status': '403', 'detail': 'Forbidden'},
            ],
          },
        ),
      );
      asc.on(
        'GET',
        '/v1/bundleIds',
        (_) => (status: 403, body: {'errors': <Object?>[]}),
      );
      final details = await lookupAccountDetails(asc.api());
      expect(details.holderName, isNull);
      expect(details.teamId, isNull);
      expect(details.problem, contains('Admin'));
    },
  );

  test('AC-031-3 an empty answer says no holder came back', () async {
    asc.on('GET', '/v1/users', (_) => (status: 200, body: FakeAsc.doc([])));
    asc.on('GET', '/v1/bundleIds', (_) => (status: 200, body: FakeAsc.doc([])));
    final details = await lookupAccountDetails(asc.api());
    expect(details.holderName, isNull);
    expect(details.problem, contains('no Account Holder'));
  });

  test(
    'AC-031-4 the JSON line has the fields Studio reads and nothing else',
    () {
      const details = AccountDetails(holderName: 'A B', teamId: 'T1');
      expect(jsonDecode(jsonEncode(details.toJson())), {
        'v': 1,
        'type': 'asc_account',
        'holderName': 'A B',
        'teamId': 'T1',
        'problem': null,
      });
    },
  );
}
