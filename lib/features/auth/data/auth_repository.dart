import '../../../core/network/api_client.dart';
import '../../../core/network/session_store.dart';
import '../../../models/app_user.dart';

class AuthRepository {
  final ApiClient _apiClient;
  final SessionStore _sessionStore;

  const AuthRepository(this._apiClient, this._sessionStore);

  Future<AppUser> login({
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.post(
      'auth/login',
      authenticated: false,
      body: {'email': email.trim(), 'password': password},
    );
    await _saveTokens(response);
    return AppUser.fromJson(response['user'] as Map<String, dynamic>);
  }

  Future<AppUser> register({
    required String fullName,
    required String email,
    required String registrationNumber,
    required String department,
    required String year,
    required String phoneNumber,
    required String password,
  }) async {
    final response = await _apiClient.post(
      'auth/register',
      authenticated: false,
      body: {
        'full_name': fullName.trim(),
        'email': email.trim(),
        'registration_number': registrationNumber.trim(),
        'department': department,
        'year': year,
        'phone_number': phoneNumber.trim(),
        'password': password,
      },
    );
    await _saveTokens(response);
    return AppUser.fromJson(response['user'] as Map<String, dynamic>);
  }

  Future<AppUser> currentUser() async {
    final response = await _apiClient.getObject('auth/me');
    return AppUser.fromJson(response);
  }

  Future<void> logout() async {
    final tokens = await _sessionStore.read();
    try {
      if (tokens != null) {
        await _apiClient.post(
          'auth/logout',
          body: {'refresh_token': tokens.refreshToken},
        );
      }
    } finally {
      await _sessionStore.clear();
    }
  }

  Future<void> _saveTokens(Map<String, dynamic> response) async {
    final accessToken = response['access_token'];
    final refreshToken = response['refresh_token'];
    if (accessToken is! String || refreshToken is! String) {
      throw const FormatException('The server returned an invalid session');
    }
    await _sessionStore.write(
      SessionTokens(accessToken: accessToken, refreshToken: refreshToken),
    );
  }
}
