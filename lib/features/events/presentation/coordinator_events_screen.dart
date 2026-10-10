import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/club.dart';
import '../../../models/event.dart';
import '../../../shared/widgets/state_views.dart';
import '../../memberships/providers/membership_providers.dart';
import 'event_check_in_screen.dart';
import '../providers/events_providers.dart';

class CoordinatorEventsScreen extends ConsumerStatefulWidget {
  const CoordinatorEventsScreen({super.key});

  @override
  ConsumerState<CoordinatorEventsScreen> createState() =>
      _CoordinatorEventsScreenState();
}

class _CoordinatorEventsScreenState
    extends ConsumerState<CoordinatorEventsScreen> {
  int? _selectedClubId;

  Future<void> _createEvent(Club club, {Event? event}) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => _CreateEventDialog(club: club, event: event),
    );
    if (created == true) {
      ref.invalidate(managedClubEventsProvider(club.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final clubsState = ref.watch(coordinatorClubsProvider);
    return clubsState.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (error, _) => ErrorState(
        message: 'Could not load your assigned clubs.',
        onRetry: () => ref.invalidate(coordinatorClubsProvider),
      ),
      data: (clubs) {
        if (clubs.isEmpty) {
          return const EmptyState(
            icon: Icons.groups_outlined,
            title: 'No clubs assigned',
            message:
                'Ask a club administrator to assign a club to your account.',
          );
        }
        final selectedId = clubs.any((club) => club.id == _selectedClubId)
            ? _selectedClubId!
            : clubs.first.id;
        final selectedClub = clubs.firstWhere((club) => club.id == selectedId);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: selectedId,
                      decoration: const InputDecoration(
                        labelText: 'Assigned club',
                        prefixIcon: Icon(Icons.groups_outlined),
                      ),
                      items: clubs
                          .map(
                            (club) => DropdownMenuItem(
                              value: club.id,
                              child: Text(club.name),
                            ),
                          )
                          .toList(),
                      onChanged: (id) {
                        if (id != null) setState(() => _selectedClubId = id);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    tooltip: 'Create event draft',
                    onPressed: () => _createEvent(selectedClub),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
            Expanded(child: _ManagedEventsList(club: selectedClub)),
          ],
        );
      },
    );
  }
}

class _ManagedEventsList extends ConsumerWidget {
  final Club club;

  const _ManagedEventsList({required this.club});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsState = ref.watch(managedClubEventsProvider(club.id));
    return eventsState.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (error, _) => ErrorState(
        message: 'Could not load ${club.name} events.',
        onRetry: () => ref.invalidate(managedClubEventsProvider(club.id)),
      ),
      data: (events) {
        if (events.isEmpty) {
          return const EmptyState(
            icon: Icons.event_note_rounded,
            title: 'No events yet',
            message: 'Create an event draft for this club.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            final provider = managedClubEventsProvider(club.id);
            ref.invalidate(provider);
            await ref.read(provider.future);
          },
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: events.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) =>
                _ManagedEventCard(club: club, event: events[index]),
          ),
        );
      },
    );
  }
}

class _ManagedEventCard extends ConsumerStatefulWidget {
  final Club club;
  final Event event;

  const _ManagedEventCard({required this.club, required this.event});

  @override
  ConsumerState<_ManagedEventCard> createState() => _ManagedEventCardState();
}

class _ManagedEventCardState extends ConsumerState<_ManagedEventCard> {
  bool _busy = false;

  Future<void> _editDraft() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _CreateEventDialog(club: widget.club, event: widget.event),
    );
    if (saved == true) {
      ref.invalidate(managedClubEventsProvider(widget.club.id));
      ref.invalidate(upcomingEventsProvider);
    }
  }

  Future<void> _showParticipants() async {
    try {
      final repository = ref.read(eventsRepositoryProvider);
      final summary = await repository.getAttendanceSummary(widget.event.id);
      final participants = await repository.getParticipants(widget.event.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${widget.event.title} attendance'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Registered ${summary['registered_count']} · '
                  'Attended ${summary['attended_count']} · '
                  'Not attended ${summary['not_attended_count']}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                if (participants.isEmpty)
                  const Text('No active registrations yet.')
                else
                  SizedBox(
                    height: 280,
                    child: ListView(
                      children: participants
                          .map(
                            (participant) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                participant['student_name'] as String,
                              ),
                              subtitle: Text(
                                participant['student_email'] as String,
                              ),
                              trailing: Icon(
                                participant['attended'] == true
                                    ? Icons.verified_rounded
                                    : Icons.schedule_rounded,
                                color: participant['attended'] == true
                                    ? AppColors.success
                                    : AppColors.textMuted,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is ApiException
          ? error.message
          : 'Could not load attendance details.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _changeStatus({required bool publish}) async {
    setState(() => _busy = true);
    try {
      final repository = ref.read(eventsRepositoryProvider);
      if (publish) {
        await repository.publishEvent(widget.event.id);
      } else {
        await repository.cancelEvent(widget.event.id);
      }
      ref.invalidate(managedClubEventsProvider(widget.club.id));
      ref.invalidate(upcomingEventsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(publish ? 'Event published.' : 'Event cancelled.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is ApiException
          ? error.message
          : 'Could not reach the server. Check your connection and try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(event.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 5),
            Text(
              '${event.status.name.toUpperCase()} · ${event.registrationCount}/${event.capacity} registered',
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 5),
            Text(
              '${MaterialLocalizations.of(context).formatMediumDate(event.startTime.toLocal())} · ${event.venue}',
            ),
            if (event.status == EventStatus.draft) ...[
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _editDraft,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit draft'),
                  ),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _changeStatus(publish: true),
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Publish'),
                  ),
                ],
              ),
            ] else if (event.status == EventStatus.published) ...[
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _showParticipants,
                    icon: const Icon(Icons.people_alt_outlined),
                    label: const Text('Participants'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => EventCheckInScreen(
                          eventId: event.id,
                          eventTitle: event.title,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('Check in'),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _changeStatus(publish: false),
                    child: const Text('Cancel event'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CreateEventDialog extends ConsumerStatefulWidget {
  final Club club;
  final Event? event;

  const _CreateEventDialog({required this.club, this.event});

  @override
  ConsumerState<_CreateEventDialog> createState() => _CreateEventDialogState();
}

class _CreateEventDialogState extends ConsumerState<_CreateEventDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _category = TextEditingController();
  final _eligibility = TextEditingController();
  final _posterUrl = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _venue = TextEditingController();
  final _capacity = TextEditingController(text: '50');
  late DateTime _registrationOpens;
  late DateTime _registrationCloses;
  late DateTime _start;
  late DateTime _end;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final event = widget.event;
    _title.text = event?.title ?? '';
    _description.text = event?.description ?? '';
    _category.text = event?.category ?? '';
    _eligibility.text = event?.eligibility ?? '';
    _posterUrl.text = event?.posterUrl ?? '';
    _latitude.text = event?.latitude?.toString() ?? '';
    _longitude.text = event?.longitude?.toString() ?? '';
    _venue.text = event?.venue ?? '';
    _capacity.text = '${event?.capacity ?? 50}';
    _start = event?.startTime.toLocal() ?? now.add(const Duration(days: 7));
    _end = event?.endTime?.toLocal() ?? _start.add(const Duration(hours: 2));
    _registrationOpens = event?.registrationOpensAt?.toLocal() ?? now;
    _registrationCloses =
        event?.registrationClosesAt?.toLocal() ??
        _start.subtract(const Duration(hours: 1));
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _category.dispose();
    _eligibility.dispose();
    _posterUrl.dispose();
    _latitude.dispose();
    _longitude.dispose();
    _venue.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime(
    DateTime current,
    ValueChanged<DateTime> onSelected,
  ) async {
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    onSelected(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  String _formatDateTime(DateTime value) {
    final date = MaterialLocalizations.of(context).formatMediumDate(value);
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(value));
    return '$date at $time';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final details = {
        'title': _title.text.trim(),
        'description': _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        'category': _category.text.trim().isEmpty
            ? null
            : _category.text.trim(),
        'eligibility': _eligibility.text.trim().isEmpty
            ? null
            : _eligibility.text.trim(),
        'poster_url': _posterUrl.text.trim().isEmpty
            ? null
            : _posterUrl.text.trim(),
        'start_at': _start.toUtc().toIso8601String(),
        'end_at': _end.toUtc().toIso8601String(),
        'registration_opens_at': _registrationOpens.toUtc().toIso8601String(),
        'registration_closes_at': _registrationCloses.toUtc().toIso8601String(),
        'venue': _venue.text.trim(),
        'latitude': _latitude.text.trim().isEmpty
            ? null
            : double.tryParse(_latitude.text.trim()),
        'longitude': _longitude.text.trim().isEmpty
            ? null
            : double.tryParse(_longitude.text.trim()),
        'capacity': int.parse(_capacity.text),
      };
      final repository = ref.read(eventsRepositoryProvider);
      if (widget.event == null) {
        await repository.createEvent(widget.club.id, details);
      } else {
        await repository.updateEvent(widget.event!.id, details);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is ApiException
            ? error.message
            : 'Could not reach the server. Check your connection and try again.';
      });
    }
  }

  Widget _dateButton(
    String label,
    DateTime value,
    ValueChanged<DateTime> onSelected,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(_formatDateTime(value)),
      trailing: const Icon(Icons.edit_calendar_outlined),
      onTap: () => _pickDateTime(value, onSelected),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.event == null
            ? 'New ${widget.club.name} event'
            : 'Edit ${widget.club.name} event',
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Event title'),
                  validator: (value) => value == null || value.trim().length < 3
                      ? 'Enter at least 3 characters'
                      : null,
                ),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 3,
                ),
                TextFormField(
                  controller: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                TextFormField(
                  controller: _eligibility,
                  decoration: const InputDecoration(
                    labelText: 'Eligibility (optional)',
                    hintText: 'e.g. Open to all students',
                  ),
                  maxLength: 500,
                ),
                TextFormField(
                  controller: _posterUrl,
                  decoration: const InputDecoration(
                    labelText: 'Poster URL (optional)',
                  ),
                  keyboardType: TextInputType.url,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final uri = Uri.tryParse(value.trim());
                    return uri == null ||
                            !uri.hasScheme ||
                            !{'http', 'https'}.contains(uri.scheme)
                        ? 'Enter a valid HTTP(S) URL'
                        : null;
                  },
                ),
                TextFormField(
                  controller: _venue,
                  decoration: const InputDecoration(
                    labelText: 'Verified venue',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter the event venue'
                      : null,
                ),
                TextFormField(
                  controller: _capacity,
                  decoration: const InputDecoration(labelText: 'Capacity'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final capacity = int.tryParse(value ?? '');
                    return capacity == null || capacity <= 0
                        ? 'Enter a positive capacity'
                        : null;
                  },
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _latitude,
                        decoration: const InputDecoration(
                          labelText: 'Latitude (optional)',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return _longitude.text.trim().isNotEmpty
                                ? 'Both coordinates required'
                                : null;
                          }
                          final parsed = double.tryParse(value.trim());
                          return parsed == null || parsed < -90 || parsed > 90
                              ? 'Use -90 to 90'
                              : null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _longitude,
                        decoration: const InputDecoration(
                          labelText: 'Longitude (optional)',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return _latitude.text.trim().isNotEmpty
                                ? 'Both coordinates required'
                                : null;
                          }
                          final parsed = double.tryParse(value.trim());
                          return parsed == null || parsed < -180 || parsed > 180
                              ? 'Use -180 to 180'
                              : null;
                        },
                      ),
                    ),
                  ],
                ),
                _dateButton(
                  'Registration opens',
                  _registrationOpens,
                  (value) => setState(() => _registrationOpens = value),
                ),
                _dateButton(
                  'Registration closes',
                  _registrationCloses,
                  (value) => setState(() => _registrationCloses = value),
                ),
                _dateButton(
                  'Event starts',
                  _start,
                  (value) => setState(() => _start = value),
                ),
                _dateButton(
                  'Event ends',
                  _end,
                  (value) => setState(() => _end = value),
                ),
                if (_error case final message?) ...[
                  const SizedBox(height: 8),
                  Text(message, style: const TextStyle(color: AppColors.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.event == null ? 'Save draft' : 'Save changes'),
        ),
      ],
    );
  }
}
