import '../../../core/network/api_client.dart';
import '../../../models/app_notification.dart';

abstract class NotificationsRepository {
  Future<List<AppNotification>> getNotifications();
  Future<void> markRead(int notificationId);
}

class ApiNotificationsRepository implements NotificationsRepository {
  final ApiClient _apiClient;

  const ApiNotificationsRepository(this._apiClient);

  @override
  Future<List<AppNotification>> getNotifications() async {
    final rows = await _apiClient.getList('me/notifications');
    return rows.map(AppNotification.fromJson).toList();
  }

  @override
  Future<void> markRead(int notificationId) async {
    await _apiClient.patch('me/notifications/$notificationId/read', body: {});
  }
}
