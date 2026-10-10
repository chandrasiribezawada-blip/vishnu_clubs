import 'dart:convert';

import 'package:clubs/core/network/api_client.dart';
import 'package:clubs/core/network/session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _MemorySessionStore implements SessionStore {
  SessionTokens? tokens;

  _MemorySessionStore(this.tokens);

  @override
  Future<void> clear() async {
    tokens = null;
  }

  @override
  Future<SessionTokens?> read() async => tokens;

  @override
  Future<void> write(SessionTokens value) async {
    tokens = value;
  }
}

void main() {
  test('sends the saved bearer token with authenticated requests', () async {
    final store = _MemorySessionStore(
      const SessionTokens(
        accessToken: 'saved-access',
        refreshToken: 'saved-refresh',
      ),
    );
    String? authorization;
    final client = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      httpClient: MockClient((request) async {
        authorization = request.headers['Authorization'];
        return http.Response(jsonEncode({'id': 1}), 200);
      }),
      sessionStore: store,
    );

    await client.getObject('auth/me');

    expect(authorization, 'Bearer saved-access');
  });

  test('refreshes an expired token while restoring the current user', () async {
    final store = _MemorySessionStore(
      const SessionTokens(
        accessToken: 'expired-access',
        refreshToken: 'valid-refresh',
      ),
    );
    final requests = <http.Request>[];
    final client = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/auth/refresh')) {
          return http.Response(
            jsonEncode({
              'access_token': 'refreshed-access',
              'refresh_token': 'refreshed-refresh',
            }),
            200,
          );
        }
        if (request.headers['Authorization'] == 'Bearer expired-access') {
          return http.Response('{"detail":"Invalid token"}', 401);
        }
        return http.Response(jsonEncode({'id': 1}), 200);
      }),
      sessionStore: store,
    );

    final user = await client.getObject('auth/me');

    expect(user['id'], 1);
    expect(requests.map((request) => request.url.path), [
      '/api/v1/auth/me',
      '/api/v1/auth/refresh',
      '/api/v1/auth/me',
    ]);
    expect(requests.last.headers['Authorization'], 'Bearer refreshed-access');
    expect(store.tokens?.refreshToken, 'refreshed-refresh');
  });
}
