import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/club.dart';
import '../../../models/event.dart';
import '../../auth/providers/auth_providers.dart';
import '../../clubs/data/clubs_repository.dart';
import '../../events/providers/events_providers.dart';

final clubsRepositoryProvider = Provider<ClubsRepository>(
  (ref) => ApiClubsRepository(ref.watch(apiClientProvider)),
);

final clubsProvider = FutureProvider<List<Club>>(
  (ref) => ref.watch(clubsRepositoryProvider).getClubs(),
);

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

class SelectedCategoryNotifier extends Notifier<String> {
  @override
  String build() => 'All';

  void set(String value) => state = value;
}

final selectedCategoryProvider = NotifierProvider<SelectedCategoryNotifier, String>(
  SelectedCategoryNotifier.new,
);

final categoriesProvider = Provider<List<String>>((ref) {
  final clubs = ref.watch(clubsProvider).asData?.value ?? const <Club>[];
  final categories = clubs
      .map((club) => club.category)
      .whereType<String>()
      .toSet()
      .toList();
  categories.sort();
  return ['All', ...categories];
});

final filteredClubsProvider = Provider<AsyncValue<List<Club>>>((ref) {
  final clubsState = ref.watch(clubsProvider);
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  final selectedCategory = ref.watch(selectedCategoryProvider);

  return clubsState.whenData((clubs) {
    final filtered = clubs.where((club) {
      final matchesCategory =
          selectedCategory == 'All' || club.category == selectedCategory;
      final matchesQuery = query.isEmpty ||
          club.name.toLowerCase().contains(query);
      return matchesCategory && matchesQuery;
    }).toList();

    return filtered;
  });
});

/// Find one club by id from the clubs list
final clubByIdProvider = Provider.family<AsyncValue<Club?>, int>((ref, id) {
  return ref.watch(clubsProvider).whenData((list) {
    for (final c in list) {
      if (c.id == id) return c;
    }
    return null;
  });
});

/// Upcoming events of one club
final clubEventsProvider =
    Provider.family<AsyncValue<List<Event>>, int>((ref, clubId) {
  return ref
      .watch(upcomingEventsProvider)
      .whenData((list) => list.where((e) => e.clubId == clubId).toList());
});

/// Clubs the student follows (follow is different from joining)
class FollowedClubsNotifier extends AsyncNotifier<Set<int>> {
  @override
  Future<Set<int>> build() async {
    final clubs = await ref.read(apiClientProvider).getList('me/followed-clubs');
    return clubs.map((club) => (club['id'] as num).toInt()).toSet();
  }

  Future<void> toggle(int clubId) async {
    final current = state.asData?.value ?? const <int>{};
    final following = current.contains(clubId);
    if (following) {
      await ref.read(apiClientProvider).delete('clubs/$clubId/follow');
    } else {
      await ref.read(apiClientProvider).post('clubs/$clubId/follow');
    }
    state = AsyncData({
      if (following) ...current.where((id) => id != clubId),
      if (!following) ...current,
      if (!following) clubId,
    });
  }
}

final followedClubsProvider =
    AsyncNotifierProvider<FollowedClubsNotifier, Set<int>>(
        FollowedClubsNotifier.new);