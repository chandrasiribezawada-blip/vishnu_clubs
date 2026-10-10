import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_providers.dart';
import '../../../models/club.dart';
import '../../../models/event.dart';
import '../../../shared/widgets/section_header.dart';
import '../../clubs/providers/clubs_providers.dart';
import '../../events/providers/events_providers.dart';
import '../../announcements/providers/announcements_providers.dart';
import '../../memberships/providers/membership_providers.dart';
import '../../../models/join_request.dart';
import 'widgets/club_mini_card.dart';
import 'widgets/event_mini_card.dart';
import 'widgets/featured_event_card.dart';
import 'widgets/home_header.dart';
import 'widgets/info_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Widget _loading() => const SizedBox(
    height: 120,
    child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
  );

  Widget _error(String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    child: Text(text, style: const TextStyle(color: AppColors.error)),
  );

  Widget _eventsSection(AsyncValue<List<Event>> state) {
    return state.when(
      loading: _loading,
      error: (e, _) => _error('Could not load events.'),
      data: (events) {
        if (events.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: InfoCard(
              icon: Icons.event_busy_rounded,
              title: 'No upcoming events',
              message: 'New events from clubs will show up here.',
            ),
          );
        }
        final rest = events.skip(1).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: FeaturedEventCard(event: events.first),
            ),
            if (rest.isNotEmpty) ...[
              const SizedBox(height: 26),
              const SectionHeader(title: 'Upcoming events'),
              const SizedBox(height: 12),
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: rest.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => EventMiniCard(event: rest[i]),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _clubsSection(BuildContext context, AsyncValue<List<Club>> state) {
    return state.when(
      loading: _loading,
      error: (e, _) => _error('Could not load clubs.'),
      data: (clubs) {
        if (clubs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: InfoCard(
              icon: Icons.groups_outlined,
              title: 'No clubs available',
              message: 'Club listings will appear here once they are loaded.',
              actionLabel: 'Browse clubs',
              onAction: () => context.go('/clubs'),
            ),
          );
        }
        final items = clubs.take(6).toList();
        return SizedBox(
          height: 172,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) =>
                ClubMiniCard(club: items[i], onTap: () => context.go('/clubs')),
          ),
        );
      },
    );
  }

  Widget _membershipsSection(
    BuildContext context,
    AsyncValue<List<ClubMembership>> state,
  ) {
    return state.when(
      loading: _loading,
      error: (error, stackTrace) => _error('Could not load your clubs.'),
      data: (memberships) {
        if (memberships.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: InfoCard(
              icon: Icons.groups_rounded,
              title: 'No clubs joined yet',
              message: 'Send a join request and your clubs will appear here.',
              actionLabel: 'Explore clubs',
              onAction: () => context.go('/clubs'),
            ),
          );
        }
        return Column(
          children: memberships.map((membership) {
            return ListTile(
              title: Text(membership.clubName),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/club/${membership.clubId}'),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsState = ref.watch(upcomingEventsProvider);
    final clubsState = ref.watch(clubsProvider);
    final membershipsState = ref.watch(studentMembershipsProvider);
    final announcementsState = ref.watch(relevantAnnouncementsProvider);
    final user = ref.watch(authControllerProvider).asData?.value;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Placeholder name. Comes from the logged-in user later.
          HomeHeader(name: user?.fullName ?? 'Student'),
          const SizedBox(height: 24),

          _eventsSection(eventsState),

          const SizedBox(height: 26),
          SectionHeader(
            title: 'Recommended clubs',
            actionLabel: 'See all',
            onAction: () => context.go('/clubs'),
          ),
          const SizedBox(height: 12),
          _clubsSection(context, clubsState),

          const SizedBox(height: 26),
          const SectionHeader(title: 'My clubs'),
          const SizedBox(height: 12),
          _membershipsSection(context, membershipsState),

          const SizedBox(height: 26),
          const SectionHeader(title: 'Latest announcements'),
          const SizedBox(height: 12),
          announcementsState.when(
            loading: _loading,
            error: (error, stackTrace) => _error('Could not load announcements.'),
            data: (announcements) => announcements.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: InfoCard(
                      icon: Icons.campaign_outlined,
                      title: 'No announcements yet',
                      message: 'Relevant club and campus updates will appear here.',
                    ),
                  )
                : Column(
                    children: announcements.take(3).map((announcement) {
                      return ListTile(
                        leading: const Icon(
                          Icons.campaign_outlined,
                          color: AppColors.primary,
                        ),
                        title: Text(announcement.title),
                        subtitle: Text(
                          '${announcement.clubName ?? 'Campus'} · ${announcement.body}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => context.push('/announcements'),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
