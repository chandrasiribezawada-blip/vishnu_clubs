import '../../../core/network/api_client.dart';

class CoordinatorRepository {
  final ApiClient _api;

  const CoordinatorRepository(this._api);

  Future<Map<String, dynamic>> club() => _api.getObject('coordinator/club');

  Future<Map<String, dynamic>> stats() =>
      _api.getObject('coordinator/club/stats');

  Future<List<Map<String, dynamic>>> members() =>
      _api.getList('coordinator/club/members');

  Future<List<Map<String, dynamic>>> requests() =>
      _api.getList('coordinator/club/join-requests');

  Future<List<Map<String, dynamic>>> events() =>
      _api.getList('coordinator/club/events');

  Future<Map<String, dynamic>> decide(int requestId, String decision) =>
      _api.post(
        'coordinator/club/join-requests/$requestId/$decision',
        body: const {},
      );

  Future<void> removeMember(String userId) =>
      _api.delete('coordinator/club/members/$userId');

  Future<Map<String, dynamic>> updateClub(Map<String, Object?> values) =>
      _api.patch('coordinator/club', body: values);

  Future<Map<String, dynamic>> cancelEvent(int eventId) =>
      _api.post('coordinator/club/events/$eventId/cancel');
}
