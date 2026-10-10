import 'package:clubs/features/notifications/data/notifications_repository.dart';
import 'package:clubs/features/notifications/presentation/notifications_screen.dart';
import 'package:clubs/features/notifications/providers/notifications_providers.dart';
import 'package:clubs/models/app_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NotificationsFake implements NotificationsRepository {
  final List<AppNotification> items = [
    AppNotification(
      id: 3,
      title: 'Membership approved',
      message: 'Your request was approved.',
      createdAt: DateTime.utc(2026, 1, 1),
    ),
  ];

  @override
  Future<List<AppNotification>> getNotifications() async => items;

  @override
  Future<void> markRead(int notificationId) async {
    final index = items.indexWhere((item) => item.id == notificationId);
    if (index >= 0) {
      final item = items[index];
      items[index] = AppNotification(
        id: item.id,
        title: item.title,
        message: item.message,
        createdAt: item.createdAt,
        readAt: DateTime.now(),
      );
    }
  }
}

void main() {
  testWidgets('notifications load persisted items and mark them read', (
    tester,
  ) async {
    final repository = _NotificationsFake();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationsRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: NotificationsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Membership approved'), findsOneWidget);
    expect(find.text('Your request was approved.'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);

    await tester.tap(find.text('Membership approved'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    expect(repository.items.single.isRead, isTrue);
  });

  testWidgets('notifications show a useful empty state', (tester) async {
    final repository = _NotificationsFake()..items.clear();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationsRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: NotificationsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('You are all caught up'), findsOneWidget);
  });
}
