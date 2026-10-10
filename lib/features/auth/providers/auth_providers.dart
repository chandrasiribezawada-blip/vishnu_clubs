import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/session_store.dart';
import '../../../models/app_user.dart';
import '../data/auth_repository.dart';

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: kIsWeb
      ? 'http://localhost:8000/api/v1'
      : 'http://10.0.2.2:8000/api/v1',
);

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SecureSessionStore(const FlutterSecureStorage()),
);

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    baseUrl: apiBaseUrl,
    httpClient: ref.watch(httpClientProvider),
    sessionStore: ref.watch(sessionStoreProvider),
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(sessionStoreProvider),
  );
});

final authControllerProvider = AsyncNotifierProvider<AuthController, AppUser?>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<AppUser?> {
  @override
  Future<AppUser?> build() async {
    final tokens = await ref.read(sessionStoreProvider).read();
    if (tokens == null) return null;
    try {
      return await ref.read(authRepositoryProvider).currentUser();
    } catch (error) {
      if (error case final ApiException exception
          when exception.statusCode == 401) {
        await ref.read(sessionStoreProvider).clear();
        return null;
      }
      rethrow;
    }
  }

  Future<void> login({required String email, required String password}) async {
    state = const AsyncLoading();
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .login(email: email, password: password);
      state = AsyncData(user);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> register({
    required String fullName,
    required String email,
    required String registrationNumber,
    required String department,
    required String year,
    required String phoneNumber,
    required String password,
  }) async {
    state = const AsyncLoading();
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .register(
            fullName: fullName,
            email: email,
            registrationNumber: registrationNumber,
            department: department,
            year: year,
            phoneNumber: phoneNumber,
            password: password,
          );
      state = AsyncData(user);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> logout() async {
    state = const AsyncLoading();
    try {
      await ref.read(authRepositoryProvider).logout();
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}
