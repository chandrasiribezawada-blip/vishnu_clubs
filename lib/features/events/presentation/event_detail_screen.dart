import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/event.dart';
import '../../../shared/widgets/state_views.dart';
import 'event_pass_screen.dart';
import '../providers/events_providers.dart';

class EventDetailScreen extends ConsumerStatefulWidget {
  final int eventId;

  const EventDetailScreen({super.key, required this.eventId});

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  bool _working = false;
  String? _actionError;

  Future<void> _shareEvent(Event event) async {
    final start = event.startTime.toLocal();
    final date = MaterialLocalizations.of(context).formatMediumDate(start);
    try {
      await SharePlus.instance.share(
        ShareParams(
          title: event.title,
          text:
              '${event.title}\n${event.clubName}\n$date at ${event.venue}\n\nJoin us at VishnuConnect!',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share this event: $error')),
      );
    }
  }

  Future<void> _openDirections(Event event) async {
    if (event.venue.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Directions are unavailable for this venue.'),
        ),
      );
      return;
    }
    final destination = event.latitude != null && event.longitude != null
        ? '${event.latitude},${event.longitude}'
        : event.venue;
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': destination,
    });
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('No application can open the map link.');
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open directions: $error')),
      );
    }
  }

  Future<void> _changeRegistration({required bool registered}) async {
    setState(() {
      _working = true;
      _actionError = null;
    });
    try {
      final repository = ref.read(eventsRepositoryProvider);
      if (registered) {
        await repository.cancelRegistration(widget.eventId);
      } else {
        await repository.registerForEvent(widget.eventId);
      }
      ref.invalidate(myEventsProvider);
      ref.invalidate(upcomingEventsProvider);
      ref.invalidate(eventByIdProvider(widget.eventId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            registered ? 'Registration cancelled.' : 'You are registered.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _actionError = error is ApiException
            ? error.message
            : 'Could not reach the server. Check your connection and try again.';
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Widget _eventContent(Event event, Event? myEvent) {
    final registered =
        myEvent?.registrationStatus == EventRegistrationStatus.registered;
    final registrationState = ref.watch(myEventsProvider);
    final registrationLoading = registrationState.isLoading;
    final start = event.startTime.toLocal();
    final end = event.endTime?.toLocal();
    final opens = event.registrationOpensAt?.toLocal();
    final closes = event.registrationClosesAt?.toLocal();
    final timeRange = end == null
        ? MaterialLocalizations.of(
            context,
          ).formatTimeOfDay(TimeOfDay.fromDateTime(start))
        : '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(start))}–${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(end))}';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(event.clubName, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          event.title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 20),
        _DetailRow(
          icon: Icons.calendar_month_outlined,
          label: MaterialLocalizations.of(context).formatMediumDate(start),
          value: timeRange,
        ),
        _DetailRow(
          icon: Icons.location_on_outlined,
          label: 'Venue',
          value: event.venue,
        ),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _openDirections(event),
              icon: const Icon(Icons.directions_rounded),
              label: const Text('Directions'),
            ),
            OutlinedButton.icon(
              onPressed: () => _shareEvent(event),
              icon: const Icon(Icons.share_rounded),
              label: const Text('Share event'),
            ),
          ],
        ),
        _DetailRow(
          icon: Icons.people_outline_rounded,
          label: 'Registrations',
          value: '${event.registrationCount} / ${event.capacity}',
        ),
        if (event.eligibility case final eligibility?)
          _DetailRow(
            icon: Icons.verified_user_outlined,
            label: 'Eligibility',
            value: eligibility,
          ),
        if (myEvent != null)
          _DetailRow(
            icon: myEvent.attended
                ? Icons.verified_rounded
                : Icons.confirmation_number_outlined,
            label: 'Your status',
            value: myEvent.attended
                ? 'Attendance recorded'
                : myEvent.registrationStatus ==
                      EventRegistrationStatus.registered
                ? 'Registered · awaiting check-in'
                : 'Registration cancelled',
          ),
        if (opens != null && closes != null)
          _DetailRow(
            icon: Icons.schedule_rounded,
            label: 'Registration window',
            value:
                '${MaterialLocalizations.of(context).formatShortDate(opens)} – ${MaterialLocalizations.of(context).formatShortDate(closes)}',
          ),
        if (event.description case final description?) ...[
          const SizedBox(height: 20),
          Text(
            'About this event',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(description),
        ],
        if (_actionError case final message?) ...[
          const SizedBox(height: 20),
          Text(message, style: const TextStyle(color: AppColors.error)),
        ],
        const SizedBox(height: 28),
        if (registered && !myEvent!.attended)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => EventPassScreen(event: event),
                  ),
                ),
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Text('Show event pass'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _working
                    ? null
                    : () => _changeRegistration(registered: true),
                child: _working
                    ? const CircularProgressIndicator()
                    : const Text('Cancel registration'),
              ),
            ],
          )
        else if (!registered)
          FilledButton(
            onPressed: _working || registrationLoading
                ? null
                : () => _changeRegistration(registered: false),
            child: _working
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Register for event'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final eventState = ref.watch(eventByIdProvider(widget.eventId));
    final myEventsState = ref.watch(myEventsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Event details')),
      body: eventState.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (error, _) => ErrorState(
          message: 'Could not load event details.',
          onRetry: () => ref.invalidate(eventByIdProvider(widget.eventId)),
        ),
        data: (event) {
          final myEvent = myEventsState.asData?.value
              .where((item) => item.id == widget.eventId)
              .firstOrNull;
          return _eventContent(event, myEvent);
        },
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 12),
        SizedBox(
          width: 115,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
