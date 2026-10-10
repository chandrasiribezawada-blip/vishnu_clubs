import '../../../core/network/api_client.dart';
import '../../../models/announcement.dart';

abstract class AnnouncementsRepository {
  Future<List<Announcement>> getRelevant();
  Future<List<Announcement>> getClub(int clubId);
  Future<List<Announcement>> getManaged(int clubId);
  Future<List<Announcement>> getAdmin();
  Future<Announcement> createClub(int clubId, Map<String, Object?> details);
  Future<Announcement> createPlatform(Map<String, Object?> details);
  Future<Announcement> publish(int id);
  Future<Announcement> cancel(int id);
}

class ApiAnnouncementsRepository implements AnnouncementsRepository {
  final ApiClient _client;

  const ApiAnnouncementsRepository(this._client);

  List<Announcement> _parse(List<Map<String, dynamic>> rows) =>
      rows.map(Announcement.fromJson).toList();

  @override
  Future<List<Announcement>> getRelevant() async =>
      _parse(await _client.getList('announcements'));

  @override
  Future<List<Announcement>> getClub(int clubId) async => _parse(
    await _client.getList('clubs/$clubId/announcements', authenticated: false),
  );

  @override
  Future<List<Announcement>> getManaged(int clubId) async =>
      _parse(await _client.getList('clubs/$clubId/announcements/manage'));

  @override
  Future<List<Announcement>> getAdmin() async =>
      _parse(await _client.getList('admin/announcements'));

  @override
  Future<Announcement> createClub(
    int clubId,
    Map<String, Object?> details,
  ) async => Announcement.fromJson(
    await _client.post('clubs/$clubId/announcements', body: details),
  );

  @override
  Future<Announcement> createPlatform(Map<String, Object?> details) async =>
      Announcement.fromJson(
        await _client.post('admin/announcements', body: details),
      );

  @override
  Future<Announcement> publish(int id) async =>
      Announcement.fromJson(await _client.post('announcements/$id/publish'));

  @override
  Future<Announcement> cancel(int id) async =>
      Announcement.fromJson(await _client.post('announcements/$id/cancel'));
}
