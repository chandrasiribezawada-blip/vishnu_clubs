import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_search_field.dart';
import '../../../shared/widgets/category_chips.dart';
import '../../../shared/widgets/state_views.dart';
import '../providers/clubs_providers.dart';
import 'widgets/club_card.dart';

class ClubsScreen extends ConsumerWidget {
  const ClubsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clubsState = ref.watch(filteredClubsProvider);
    final categories = ref.watch(categoriesProvider);
    final selected = ref.watch(selectedCategoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Clubs')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
            child: AppSearchField(
              hint: 'Search clubs',
              onChanged: (v) =>
                  ref.read(searchQueryProvider.notifier).set(v),
            ),
          ),
          if (categories.length > 1)
            CategoryChips(
              labels: categories,
              selected: selected,
              onSelected: (v) =>
                  ref.read(selectedCategoryProvider.notifier).set(v),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: clubsState.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (e, _) => ErrorState(
                message: 'Could not load clubs.',
                onRetry: () => ref.invalidate(clubsProvider),
              ),
              data: (clubs) {
                if (clubs.isEmpty) {
                  return const EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No clubs found',
                    message: 'Try a different name or category.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  itemCount: clubs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => ClubCard(
                    club: clubs[i],
                    onTap: () => context.push('/club/${clubs[i].id}'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}