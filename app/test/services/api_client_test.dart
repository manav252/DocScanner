import 'dart:convert';

import 'package:docscanner/services/api/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const old = Session(accessToken: 'old', refreshToken: 'r1', userId: 'u', email: 'e@x.com');

String tokens(String access) => jsonEncode({
      'access_token': access,
      'refresh_token': 'r2',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {'id': 'u', 'email': 'e@x.com'},
    });

void main() {
  test('expired access token is refreshed once and the request retried', () async {
    final seen = <String>[];
    Session? stored;
    final client = ApiClient(
      baseUrl: 'http://api/',
      session: old,
      onSessionChanged: (s) => stored = s,
      httpClient: MockClient((req) async {
        seen.add('${req.method} ${req.url.path} ${req.headers['Authorization'] ?? ''}');
        if (req.url.path == '/auth/refresh') return http.Response(tokens('new'), 200);
        if (req.headers['Authorization'] == 'Bearer old') return http.Response('{"detail":"expired"}', 401);
        return http.Response('{"documents":[],"cursor":0,"has_more":false}', 200);
      }),
    );
    final r = await client.listDocuments();
    expect(r['cursor'], 0);
    expect(seen, ['GET /documents Bearer old', 'POST /auth/refresh ', 'GET /documents Bearer new']);
    expect(stored!.accessToken, 'new');
  });

  test('failed refresh signs out', () async {
    Session? stored = old;
    final client = ApiClient(
      baseUrl: 'http://api',
      session: old,
      onSessionChanged: (s) => stored = s,
      httpClient: MockClient((req) async => http.Response('{"detail":"nope"}', 401)),
    );
    await expectLater(client.listDocuments(), throwsA(isA<ApiException>().having((e) => e.isUnauthorized, '401', true)));
    expect(stored, isNull);
    expect(client.session, isNull);
  });

  test('409 on PUT becomes ConflictException with the server copy', () async {
    final client = ApiClient(
      baseUrl: 'http://api',
      session: old,
      httpClient: MockClient((req) async =>
          http.Response(jsonEncode({'detail': 'changed', 'document': {'id': 'd', 'version': 3}}), 409)),
    );
    await expectLater(
      client.putDocument('d', {}),
      throwsA(isA<ConflictException>().having((c) => c.server['version'], 'version', 3)),
    );
  });

  test('network failure is OfflineException', () async {
    final client = ApiClient(
      baseUrl: 'http://api',
      httpClient: MockClient((req) async => throw http.ClientException('connection refused')),
    );
    await expectLater(client.login('e@x.com', 'password1'), throwsA(isA<OfflineException>()));
  });

  test('error detail is surfaced', () async {
    final client = ApiClient(
      baseUrl: 'http://api',
      httpClient: MockClient((req) async => http.Response('{"detail":"Wrong email or password"}', 401)),
    );
    await expectLater(client.login('e@x.com', 'password1'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Wrong email or password')));
  });
}
