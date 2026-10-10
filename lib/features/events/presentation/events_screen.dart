import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/event.dart';
import '../../../models/event_ticket.dart';
import '../../../shared/widgets/state_views.dart';
import '../providers/events_providers.dart';

class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Events'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Discover'),
              Tab(text: 'My events'),
              Tab(text: 'Attendance'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _EventList(myEvents: false),
            _EventList(myEvents: true),
            _AttendanceList(),
          ],
        ),
      ),
    );
  }
}

class _AttendanceList extends ConsumerWidget {
  const _AttendanceList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myAttendanceProvider);
    return state.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (error, _) => ErrorState(
        message: 'Could not load your attendance history.',
        onRetry: () => ref.invalidate(myAttendanceProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.fact_check_outlined,
            title: 'No attendance recorded',
            message: 'Checked-in events will appear here.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myAttendanceProvider);
            await ref.read(myAttendanceProvider.future);
          },
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) =>
                _AttendanceCard(attendance: items[index]),
          ),
        );
      },
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  final EventAttendance attendance;

  const _AttendanceCard({required this.attendance});

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.verified_outlined, color: AppColors.success),
      title: Text(attendance.eventTitle),
      subtitle: Text(
        '${attendance.clubName} · ${MaterialLocalizations.of(context).formatMediumDate(attendance.checkedInAt.toLocal())}',
      ),
    ),
  );
}

class _EventList extends ConsumerStatefulWidget {
  final bool myEvents;

  const _EventList({required this.myEvents});

  @override
  ConsumerState<_EventList> createState() => _EventListState();
}

enum _EventRange { upcoming, past, all }

class _EventListState extends ConsumerState<_EventList> {
  final _searchController = TextEditingController();
  _EventRange _range = _EventRange.upcoming;
  String? _category;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.myEvents
        ? ref.watch(myEventsProvider)
        : _range == _EventRange.upcoming
        ? ref.watch(upcomingEventsProvider)
        : ref.watch(allPublishedEventsProvider);
    return state.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (error, _) => ErrorState(
        message: widget.myEvents
            ? 'Could not load your event registrations.'
            : 'Could not load events.',
        onRetry: () {
          if (widget.myEvents) {
            ref.invalidate(myEventsProvider);
          } else if (_range == _EventRange.upcoming) {
            ref.invalidate(upcomingEventsProvider);
          } else {
            ref.invalidate(allPublishedEventsProvider);
          }
        },
      ),
      data: (events) {
        final now = DateTime.now();
        final filtered = events.where((event) {
          final query = _searchController.text.trim().toLowerCase();
          final matchesQuery =
              query.isEmpty ||
              event.title.toLowerCase().contains(query) ||
              event.clubName.toLowerCase().contains(query) ||
              event.venue.toLowerCase().contains(query);
          final matchesRange =
              widget.myEvents ||
              _range == _EventRange.all ||
              (_range == _EventRange.upcoming &&
                  (event.endTime ?? event.startTime).isAfter(now)) ||
              (_range == _EventRange.past &&
                  (event.endTime ?? event.startTime).isBefore(now));
          final matchesCategory =
              _category == null || event.category == _category;
          return matchesQuery && matchesRange && matchesCategory;
        }).toList();
        final categories =
            events
                .map((event) => event.category)
                .whereType<String>()
                .where((category) => category.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
        if (events.isEmpty) {
          return EmptyState(
            icon: widget.myEvents
                ? Icons.event_note_rounded
                : Icons.event_busy_rounded,
            title: widget.myEvents
                ? 'No events registered'
                : 'No upcoming events',
            message: widget.myEvents
                ? 'Events you register for will appear here.'
                : 'Published club events will appear here.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            if (widget.myEvents) {
              ref.invalidate(myEventsProvider);
              await ref.read(myEventsProvider.future);
            } else if (_range == _EventRange.upcoming) {
              ref.invalidate(upcomingEventsProvider);
              await ref.read(upcomingEventsProvider.future);
            } else {
              ref.invalidate(allPublishedEventsProvider);
              await ref.read(allPublishedEventsProvider.future);
            }
          },
          child: Column(
            children: [
              if (!widget.myEvents)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search events, clubs, venues',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.clear_rounded),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final item in _EventRange.values)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(switch (item) {
                                    _EventRange.upcoming => 'Upcoming',
                                    _EventRange.past => 'Past',
                                    _EventRange.all => 'All',
                                  }),
                                  selected: _range == item,
                                  onSelected: (_) => setState(() {
                                    _range = item;
                                    _category = null;
                                  }),
                                ),
                              ),
                            if (categories.isNotEmpty)
                              DropdownButton<String?>(
                                value: _category,
                                hint: const Text('Category'),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('All categories'),
                                  ),
                                  ...categories.map(
                                    (category) => DropdownMenuItem<String?>(
                                      value: category,
                                      child: Text(category),
                                    ),
                                  ),
                                ],
                                onChanged: (value) =>
                                    setState(() => _category = value),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (filtered.isEmpty)
                const Expanded(
                  child: EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No matching events',
                    message: 'Try a different search or filter.',
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _EventCard(
                      event: filtered[index],
                      myEvent: widget.myEvents,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EventCard extends StatelessWidget {
  final Event event;
  final bool myEvent;

  const _EventCard({required this.event, required this.myEvent});

  @override
  Widget build(BuildContext context) {
    final localStart = event.startTime.toLocal();
    final date = MaterialLocalizations.of(context).formatMediumDate(localStart);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/events/${event.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.event_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(event.clubName),
                    const SizedBox(height: 4),
                    Text(
                      '$date · ${event.venue}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (myEvent && event.registrationStatus != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Registration: ${event.registrationStatus!.name}',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
