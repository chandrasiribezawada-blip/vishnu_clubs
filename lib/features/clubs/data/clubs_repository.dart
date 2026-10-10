import '../../../models/club.dart';
import '../../../core/network/api_client.dart';

abstract class ClubsRepository {
  Future<List<Club>> getClubs();
}

class ApiClubsRepository implements ClubsRepository {
  final ApiClient _apiClient;

  const ApiClubsRepository(this._apiClient);

  @override
  Future<List<Club>> getClubs() async {
    final response = await _apiClient.getList('clubs', authenticated: false);
    return response.map(Club.fromJson).toList();
  }
}