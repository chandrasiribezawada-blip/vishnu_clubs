import '../../../core/network/api_client.dart';
import '../../../models/club.dart';
import '../../../models/join_request.dart';

abstract class MembershipRepository {
  Future<List<JoinRequest>> getStudentRequests();
  Future<List<ClubMembership>> getStudentMemberships();
  Future<List<Club>> getCoordinatorClubs();
  Future<List<JoinRequest>> getPendingRequests(int clubId);

  Future<JoinRequest> submitJoinRequest({
    required Club club,
    required String reason,
    required String skills,
    String? experience,
  });

  Future<JoinRequest> decideRequest({
    required int requestId,
    required bool approve,
    String? note,
  });
}

class ApiMembershipRepository implements MembershipRepository {
  final ApiClient _apiClient;

  const ApiMembershipRepository(this._apiClient);

  @override
  Future<List<JoinRequest>> getStudentRequests() async {
    final response = await _apiClient.getList('me/join-requests');
    return response.map(JoinRequest.fromJson).toList();
  }

  @override
  Future<List<ClubMembership>> getStudentMemberships() async {
    final response = await _apiClient.getList('me/memberships');
    return response.map(ClubMembership.fromJson).toList();
  }

  @override
  Future<List<Club>> getCoordinatorClubs() async {
    final response = await _apiClient.getList('me/coordinator-clubs');
    return response.map(Club.fromJson).toList();
  }

  @override
  Future<List<JoinRequest>> getPendingRequests(int clubId) async {
    final response = await _apiClient.getList('clubs/$clubId/join-requests');
    return response.map(JoinRequest.fromJson).toList();
  }

  @override
  Future<JoinRequest> submitJoinRequest({
    required Club club,
    required String reason,
    required String skills,
    String? experience,
  }) async {
    final response = await _apiClient.post(
      'clubs/${club.id}/join-requests',
      body: {'reason': reason, 'skills': skills, 'experience': ?experience},
    );
    return JoinRequest.fromJson(response);
  }

  @override
  Future<JoinRequest> decideRequest({
    required int requestId,
    required bool approve,
    String? note,
  }) async {
    final response = await _apiClient.post(
      'join-requests/$requestId/${approve ? 'approve' : 'reject'}',
      body: {'note': ?note},
    );
    return JoinRequest.fromJson(response);
  }
}
