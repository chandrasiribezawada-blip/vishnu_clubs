import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../data/coordinator_repository.dart';

final coordinatorRepositoryProvider = Provider<CoordinatorRepository>(
  (ref) => CoordinatorRepository(ref.watch(apiClientProvider)),
);

final coordinatorClubProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>(
      (ref) => ref.watch(coordinatorRepositoryProvider).club(),
    );

final coordinatorStatsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>(
      (ref) => ref.watch(coordinatorRepositoryProvider).stats(),
    );

final coordinatorMembersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
      (ref) => ref.watch(coordinatorRepositoryProvider).members(),
    );

final coordinatorRequestsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
      (ref) => ref.watch(coordinatorRepositoryProvider).requests(),
    );

final coordinatorEventsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
      (ref) => ref.watch(coordinatorRepositoryProvider).events(),
    );
