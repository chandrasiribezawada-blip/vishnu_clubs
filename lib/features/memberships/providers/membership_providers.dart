import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/club.dart';
import '../../../models/join_request.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/membership_repository.dart';

final membershipRepositoryProvider = Provider<MembershipRepository>(
  (ref) => ApiMembershipRepository(ref.watch(apiClientProvider)),
);

final studentJoinRequestsProvider =
    FutureProvider.autoDispose<List<JoinRequest>>((ref) {
      return ref.watch(membershipRepositoryProvider).getStudentRequests();
    });

final studentMembershipsProvider =
    FutureProvider.autoDispose<List<ClubMembership>>((ref) {
      return ref.watch(membershipRepositoryProvider).getStudentMemberships();
    });

/// Latest request status for one club (null = never requested)
final joinStatusProvider = FutureProvider.autoDispose
    .family<JoinRequestStatus?, int>((ref, clubId) async {
      final requests = await ref
          .watch(membershipRepositoryProvider)
          .getStudentRequests();
      final matching =
          requests.where((request) => request.clubId == clubId).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return matching.isEmpty ? null : matching.first.status;
    });

final coordinatorClubsProvider = FutureProvider.autoDispose<List<Club>>((ref) {
  return ref.watch(membershipRepositoryProvider).getCoordinatorClubs();
});

final pendingClubRequestsProvider = FutureProvider.autoDispose
    .family<List<JoinRequest>, int>((ref, clubId) {
      return ref.watch(membershipRepositoryProvider).getPendingRequests(clubId);
    });
