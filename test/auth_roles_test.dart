import 'package:clubs/core/network/session_store.dart';
import 'package:clubs/features/auth/presentation/login_screen.dart';
import 'package:clubs/features/auth/presentation/register_screen.dart';
import 'package:clubs/features/auth/providers/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySessionStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<SessionTokens?> read() async => null;

  @override
  Future<void> write(SessionTokens tokens) async {}
}

Widget _screen(Widget child) => ProviderScope(
  overrides: [sessionStoreProvider.overrideWithValue(_MemorySessionStore())],
  child: MaterialApp(home: child),
);

void main() {
  testWidgets('shared login explains all server-assigned account roles', (
    tester,
  ) async {
    await tester.pumpWidget(_screen(const LoginScreen()));

    expect(
      find.text('Sign in as a student, coordinator, or club admin'),
      findsOneWidget,
    );
    expect(
      find.textContaining('opens the right workspace automatically'),
      findsOneWidget,
    );
  });

  testWidgets('public signup explains secure role assignment', (tester) async {
    await tester.pumpWidget(_screen(const RegisterScreen()));

    expect(
      find.text('Create a student account to join your college community'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Coordinator access is assigned by a club admin'),
      findsOneWidget,
    );
    expect(find.text('Admin'), findsNothing);
  });
}
