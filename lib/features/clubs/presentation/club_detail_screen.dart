import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../models/club.dart';
import '../../../models/join_request.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../../../shared/widgets/state_views.dart';
import '../../memberships/providers/membership_providers.dart';
import '../../announcements/providers/announcements_providers.dart';
import '../providers/clubs_providers.dart';
import 'widgets/club_card.dart';
import 'widgets/detail_section.dart';

class ClubDetailScreen extends ConsumerWidget {
  final int clubId;

  const ClubDetailScreen({super.key, required this.clubId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clubState = ref.watch(clubByIdProvider(clubId));

    return clubState.when(
      loading: () => const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorState(
          message: 'Could not load this club.',
          onRetry: () => ref.invalidate(clubsProvider),
        ),
      ),
      data: (club) {
        if (club == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Club not found',
              message: 'This club may have been removed.',
            ),
          );
        }
        return _ClubDetailView(club: club);
      },
    );
  }
}

class _ClubDetailView extends ConsumerWidget {
  final Club club;

  const _ClubDetailView({required this.club});

  Widget _stat(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.primary.withAlpha(18)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBox(String label, IconData icon, Color color) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _joinButton(BuildContext context, JoinRequestStatus? status) {
    switch (status) {
      case JoinRequestStatus.pending:
        return _statusBox(
          'Request pending',
          Icons.hourglass_top_rounded,
          const Color(0xFFE59500),
        );
      case JoinRequestStatus.approved:
        return _statusBox(
          'You are a member',
          Icons.verified_rounded,
          AppColors.success,
        );
      case JoinRequestStatus.rejected:
      case null:
        return GradientButton(
          label: status == JoinRequestStatus.rejected
              ? 'Request again'
              : 'Request to join',
          onPressed: () => context.push('/club/${club.id}/join'),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ClubCard.gradients[club.id % ClubCard.gradients.length];
    final statusState = ref.watch(joinStatusProvider(club.id));
    final followedState = ref.watch(followedClubsProvider);
    final following = followedState.asData?.value.contains(club.id) ?? false;
    final eventsState = ref.watch(clubEventsProvider(club.id));
    final announcementsState = ref.watch(clubAnnouncementsProvider(club.id));
    final eventCount = eventsState.value?.length ?? 0;

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: colors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(36),
                      bottomRight: Radius.circular(36),
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => context.pop(),
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(50),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.arrow_back_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Container(
                          width: 84,
                          height: 84,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(60),
                            borderRadius: BorderRadius.circular(26),
                          ),
                          child: Text(
                            club.initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          club.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                        if (club.category case final category?) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(60),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              category,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Body
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _stat('${club.memberCount}', 'Members'),
                          const SizedBox(width: 12),
                          _stat('${club.followerCount}', 'Followers'),
                          const SizedBox(width: 12),
                          _stat('$eventCount', 'Events'),
                        ],
                      ),
                      const SizedBox(height: 18),
                      DetailSection(
                        title: 'About',
                        icon: Icons.info_outline_rounded,
                        child: DetailSection.textOrPlaceholder(
                          club.description,
                        ),
                      ),
                      const SizedBox(height: 14),
                      DetailSection(
                        title: 'Objectives',
                        icon: Icons.flag_outlined,
                        child: DetailSection.textOrPlaceholder(club.objectives),
                      ),
                      const SizedBox(height: 14),
                      DetailSection(
                        title: 'Faculty coordinator',
                        icon: Icons.school_outlined,
                        child: DetailSection.textOrPlaceholder(
                          club.facultyCoordinator,
                        ),
                      ),
                      const SizedBox(height: 14),
                      DetailSection(
                        title: 'Contact',
                        icon: Icons.mail_outline_rounded,
                        child: DetailSection.textOrPlaceholder(
                          club.contactEmail,
                        ),
                      ),
                      const SizedBox(height: 14),
                      DetailSection(
                        title: 'Upcoming events',
                        icon: Icons.event_outlined,
                        child: eventsState.when(
                          loading: () => const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          error: (e, _) => const Text('Could not load events.'),
                          data: (events) {
                            if (events.isEmpty) {
                              return const Text(
                                'No upcoming events right now.',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 13.5,
                                ),
                              );
                            }
                            return Column(
                              children: events
                                  .map(
                                    (e) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.calendar_today_rounded,
                                            size: 16,
                                            color: AppColors.accent,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  e.title,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                Text(
                                                  '${AppDateUtils.shortDate(e.startTime)} · ${AppDateUtils.time(e.startTime)} · ${e.venue}',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: AppColors.textMuted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      DetailSection(
                        title: 'Announcements',
                        icon: Icons.campaign_outlined,
                        child: announcementsState.when(
                          loading: () => const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          error: (error, _) =>
                              const Text('Could not load announcements.'),
                          data: (items) => items.isEmpty
                              ? const Text(
                                  'No announcements yet.',
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 13.5,
                                  ),
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: items
                                      .map(
                                        (item) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 10,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.title,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(item.body),
                                            ],
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bottom action bar
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withAlpha(20),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      try {
                        await ref
                            .read(followedClubsProvider.notifier)
                            .toggle(club.id);
                        ref.invalidate(clubsProvider);
                      } catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(
                                'Could not update follow status: $error',
                              ),
                            ),
                          );
                        return;
                      }
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(
                              following
                                  ? 'Unfollowed ${club.name}'
                                  : 'Following ${club.name}',
                            ),
                          ),
                        );
                    },
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: following
                            ? AppColors.accent.withAlpha(30)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: following
                              ? AppColors.accent
                              : AppColors.primary.withAlpha(50),
                        ),
                      ),
                      child: Icon(
                        following
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: following
                            ? AppColors.accent
                            : AppColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'Share club',
                    onPressed: () async {
                      try {
                        await SharePlus.instance.share(
                          ShareParams(
                            title: club.name,
                            text: [
                              club.name,
                              if (club.category != null) club.category!,
                              if (club.description != null) club.description!,
                              'Explore this club on VishnuConnect.',
                            ].join('\n'),
                          ),
                        );
                      } catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Could not share this club: $error'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.share_rounded),
                  ),
                  Expanded(
                    child: statusState.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                      error: (error, stackTrace) => TextButton(
                        onPressed: () =>
                            ref.invalidate(joinStatusProvider(club.id)),
                        child: const Text('Retry loading membership status'),
                      ),
                      data: (status) => _joinButton(context, status),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
