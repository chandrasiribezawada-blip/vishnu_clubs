import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/providers/auth_providers.dart';
import '../../../models/club.dart';

class AdminWorkspaceData {
  final Map<String, dynamic> dashboard;
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> assignments;
  final List<Club> clubs;

  const AdminWorkspaceData({
    required this.dashboard,
    required this.users,
    required this.assignments,
    required this.clubs,
  });
}

final adminWorkspaceProvider =
    FutureProvider.autoDispose<AdminWorkspaceData>((ref) async {
      final api = ref.watch(apiClientProvider);
      final results = await Future.wait<Object>([
        api.getObject('admin/dashboard'),
        api.getList('admin/users'),
        api.getList('admin/coordinators'),
        api.getList('clubs', authenticated: false),
      ]);
      return AdminWorkspaceData(
        dashboard: results[0] as Map<String, dynamic>,
        users: results[1] as List<Map<String, dynamic>>,
        assignments: results[2] as List<Map<String, dynamic>>,
        clubs: (results[3] as List<Map<String, dynamic>>)
            .map(Club.fromJson)
            .toList(),
      );
    });
