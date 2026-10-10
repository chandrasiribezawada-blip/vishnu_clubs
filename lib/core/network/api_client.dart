import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'session_store.dart';

class ApiClient {
  final String baseUrl;
  final http.Client _http;
  final SessionStore sessionStore;
  Future<String?>? _refreshInFlight;

  ApiClient({
    required this.baseUrl,
    required http.Client httpClient,
    required this.sessionStore,
  }) : _http = httpClient,
       super();

  Future<List<Map<String, dynamic>>> getList(
    String path, {
    bool authenticated = true,
  }) async {
    final result = await _request('GET', path, authenticated: authenticated);
    if (result is! List) {
      throw const FormatException('Expected an API list response');
    }
    return result.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getObject(
    String path, {
    bool authenticated = true,
  }) async {
    final result = await _request('GET', path, authenticated: authenticated);
    if (result is! Map<String, dynamic>) {
      throw const FormatException('Expected an API object response');
    }
    return result;
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, Object?>? body,
    bool authenticated = true,
  }) async {
    final result = await _request(
      'POST',
      path,
      body: body,
      authenticated: authenticated,
    );
    if (result == null) return const {};
    if (result is! Map<String, dynamic>) {
      throw const FormatException('Expected an API object response');
    }
    return result;
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    required Map<String, Object?> body,
    bool authenticated = true,
  }) async {
    final result = await _request(
      'PATCH',
      path,
      body: body,
      authenticated: authenticated,
    );
    if (result is! Map<String, dynamic>) {
      throw const FormatException('Expected an API object response');
    }
    return result;
  }

  Future<void> delete(String path, {bool authenticated = true}) async {
    await _request('DELETE', path, authenticated: authenticated);
  }

  Future<Object?> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool authenticated = true,
    bool retryAfterRefresh = true,
  }) async {
    final tokens = authenticated ? await sessionStore.read() : null;
    final response = await _send(
      method,
      path,
      body: body,
      accessToken: tokens?.accessToken,
    );
    if (response.statusCode == 401 &&
        authenticated &&
        tokens != null &&
        retryAfterRefresh &&
        (!path.startsWith('auth/') || path == 'auth/me')) {
      final accessToken = await _refreshAccessToken();
      if (accessToken != null) {
        return _request(
          method,
          path,
          body: body,
          authenticated: true,
          retryAfterRefresh: false,
        );
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, _errorMessage(response));
    }
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  Future<String?> _refreshAccessToken() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final refresh = _performRefresh();
    _refreshInFlight = refresh;
    return refresh.whenComplete(() => _refreshInFlight = null);
  }

  Future<String?> _performRefresh() async {
    final tokens = await sessionStore.read();
    if (tokens == null) return null;

    final response = await _send(
      'POST',
      'auth/refresh',
      body: {'refresh_token': tokens.refreshToken},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await sessionStore.clear();
      return null;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> ||
        decoded['access_token'] is! String ||
        decoded['refresh_token'] is! String) {
      await sessionStore.clear();
      throw const FormatException('Invalid refresh response from the server');
    }
    final refreshed = SessionTokens(
      accessToken: decoded['access_token'] as String,
      refreshToken: decoded['refresh_token'] as String,
    );
    await sessionStore.write(refreshed);
    return refreshed.accessToken;
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? accessToken,
  }) {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final uri = Uri.parse('$normalizedBase/$normalizedPath');
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
    };
    final encodedBody = body == null ? null : jsonEncode(body);
    return switch (method) {
      'GET' => _http.get(uri, headers: headers),
      'POST' => _http.post(uri, headers: headers, body: encodedBody),
      'PATCH' => _http.patch(uri, headers: headers, body: encodedBody),
      'DELETE' => _http.delete(uri, headers: headers),
      _ => throw ArgumentError.value(
        method,
        'method',
        'Unsupported HTTP method',
      ),
    };
  }

  String _errorMessage(http.Response response) {
    try {
      final payload = jsonDecode(response.body);
      if (payload is Map<String, dynamic>) {
        final detail = payload['detail'];
        if (detail is String) return detail;
        if (detail is List) {
          return detail
              .map(
                (item) => item is Map<String, dynamic>
                    ? item['msg']?.toString() ?? 'Invalid input'
                    : item.toString(),
              )
              .join('\n');
        }
      }
    } on FormatException {
      return 'The server returned an invalid response.';
    }
    return 'Request failed (${response.statusCode}).';
  }
}
