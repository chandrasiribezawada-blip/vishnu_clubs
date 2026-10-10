

import 'package:clubs/core/network/session_store.dart';
import 'package:clubs/core/routing/app_router.dart';
import 'package:clubs/features/auth/providers/auth_providers.dart';
import 'package:clubs/models/app_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _MemorySessionStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<SessionTokens?> read() async => null;

  @override
  Future<void> write(SessionTokens tokens) async {}
}

AppUser _user(AppRole role) => AppUser(
  id: 'test-user',
  email: 'test@example.edu',
  fullName: 'Test User',
  role: role,
);

Future<GoRouter> _pumpRouter(
  WidgetTester tester, {
  required AsyncValue<AppUser?> session,
}) async {
  final refresh = ChangeNotifier();
  final router = createAppRouter(
    refreshListenable: refresh,
    readSession: () => session,
  );
  addTearDown(() {
    router.dispose();
    refresh.dispose();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionStoreProvider.overrideWithValue(_MemorySessionStore()),
        httpClientProvider.overrideWithValue(
          MockClient((_) async => http.Response('[]', 200)),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('unauthenticated users are redirected to login', (tester) async {
    final router = await _pumpRouter(
      tester,
      session: const AsyncData<AppUser?>(null),
    );

    router.go('/admin/clubs');
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/login');
  });

  testWidgets('auth loading keeps the splash visible', (tester) async {
    final router = await _pumpRouter(
      tester,
      session: const AsyncLoading<AppUser?>(),
    );

    router.go('/login');
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/splash');
  });

  testWidgets('student is routed home and cannot open coordinator routes', (
    tester,
  ) async {
    final router = await _pumpRouter(
      tester,
      session: AsyncData<AppUser?>(_user(AppRole.student)),
    );

    expect(router.routeInformationProvider.value.uri.path, '/home');
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Clubs'), findsOneWidget);
    expect(find.text('Events'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    router.go('/coordinator/events');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/home');
  });

  testWidgets('coordinator gets its shell and cannot open admin routes', (
    tester,
  ) async {
    final router = await _pumpRouter(
      tester,
      session: AsyncData<AppUser?>(_user(AppRole.coordinator)),
    );

    expect(router.routeInformationProvider.value.uri.path, '/coordinator');
    for (final label in ['Dashboard', 'Members', 'Events', 'Club', 'Profile']) {
      expect(find.text(label), findsWidgets);
    }

    router.go('/admin/requests');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/coordinator');
  });

  testWidgets('admin gets its shell and cannot open student routes', (
    tester,
  ) async {
    final router = await _pumpRouter(
      tester,
      session: AsyncData<AppUser?>(_user(AppRole.admin)),
    );

    expect(router.routeInformationProvider.value.uri.path, '/admin');
    for (final label in ['Dashboard', 'Clubs', 'Requests', 'Profile']) {
      expect(find.text(label), findsWidgets);
    }

    router.go('/clubs');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/admin');
  });
}
