import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../data/notifications_repository.dart';
import '../../../models/app_notification.dart';

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => ApiNotificationsRepository(ref.watch(apiClientProvider)),
);

final notificationsProvider =
    FutureProvider.autoDispose<List<AppNotification>>(
      (ref) => ref.watch(notificationsRepositoryProvider).getNotifications(),
    );

final unreadNotificationCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(notificationsProvider).asData?.value ?? [];
  return notifications.where((notification) => !notification.isRead).length;
});
