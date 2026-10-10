import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/announcement.dart';
import '../../../models/app_user.dart';
import '../../../shared/widgets/state_views.dart';
import '../../auth/providers/auth_providers.dart';
import '../../memberships/providers/membership_providers.dart';
import '../providers/announcements_providers.dart';

class AnnouncementsScreen extends ConsumerStatefulWidget {
  final bool admin;

  const AnnouncementsScreen({super.key, this.admin = false});

  @override
  ConsumerState<AnnouncementsScreen> createState() =>
      _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  int? _clubId;

  Future<void> _compose({int? clubId}) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _AnnouncementDialog(platform: widget.admin, clubId: clubId),
    );
    if (created == true) {
      if (widget.admin) {
        ref.invalidate(adminAnnouncementsProvider);
      } else if (clubId != null) {
        ref.invalidate(managedAnnouncementsProvider(clubId));
      }
      ref.invalidate(relevantAnnouncementsProvider);
    }
  }

  Future<void> _change(Announcement announcement, {required bool publish}) async {
    try {
      final repository = ref.read(announcementsRepositoryProvider);
      if (publish) {
        await repository.publish(announcement.id);
      } else {
        await repository.cancel(announcement.id);
      }
      ref.invalidate(adminAnnouncementsProvider);
      ref.invalidate(relevantAnnouncementsProvider);
      if (announcement.clubId != null) {
        ref.invalidate(managedAnnouncementsProvider(announcement.clubId!));
      }
    } catch (error) {
      if (!mounted) return;
      final message = error is ApiException
          ? error.message
          : 'Could not reach the server. Check your connection and try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).asData?.value;
    if (widget.admin) return _adminBody();
    if (user?.role != AppRole.coordinator) return _studentBody();
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
            icon: Icons.campaign_outlined,
            title: 'No clubs assigned',
            message: 'Ask an administrator to assign a club.',
          );
        }
        final selectedId = clubs.any((club) => club.id == _clubId)
            ? _clubId!
            : clubs.first.id;
        final announcementsState = ref.watch(
          managedAnnouncementsProvider(selectedId),
        );
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: selectedId,
                      decoration: const InputDecoration(labelText: 'Club'),
                      items: clubs
                          .map(
                            (club) => DropdownMenuItem(
                              value: club.id,
                              child: Text(club.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _clubId = value),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    tooltip: 'Create announcement',
                    onPressed: () => _compose(clubId: selectedId),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: announcementsState.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
                error: (error, _) => ErrorState(
                  message: 'Could not load club announcements.',
                  onRetry: () =>
                      ref.invalidate(managedAnnouncementsProvider(selectedId)),
                ),
                data: (items) => _announcementList(
                  items,
                  managed: true,
                  onRefresh: () async {
                    ref.invalidate(managedAnnouncementsProvider(selectedId));
                    await ref.read(
                      managedAnnouncementsProvider(selectedId).future,
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _studentBody() {
    final state = ref.watch(relevantAnnouncementsProvider);
    return state.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (error, _) => ErrorState(
        message: 'Could not load announcements.',
        onRetry: () => ref.invalidate(relevantAnnouncementsProvider),
      ),
      data: (items) => _announcementList(
        items,
        managed: false,
        onRefresh: () async {
          ref.invalidate(relevantAnnouncementsProvider);
          await ref.read(relevantAnnouncementsProvider.future);
        },
      ),
    );
  }

  Widget _adminBody() {
    final state = ref.watch(adminAnnouncementsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform announcements'),
        actions: [
          IconButton(
            tooltip: 'Create platform announcement',
            onPressed: _compose,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (error, _) => ErrorState(
          message: 'Could not load platform announcements.',
          onRetry: () => ref.invalidate(adminAnnouncementsProvider),
        ),
        data: (items) => _announcementList(
          items,
          managed: true,
          onRefresh: () async {
            ref.invalidate(adminAnnouncementsProvider);
            await ref.read(adminAnnouncementsProvider.future);
          },
        ),
      ),
    );
  }

  Widget _announcementList(
    List<Announcement> items, {
    required bool managed,
    required Future<void> Function() onRefresh,
  }) {
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.campaign_outlined,
        title: managed ? 'No announcements yet' : 'No new announcements',
        message: managed
            ? 'Published updates and drafts will appear here.'
            : 'Relevant club and campus updates will appear here.',
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final announcement = items[index];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          announcement.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (managed)
                        Text(
                          announcement.status.name.toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  if (announcement.clubName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      announcement.clubName!,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(announcement.body),
                  if (managed &&
                      announcement.status != AnnouncementStatus.cancelled) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 8,
                        children: [
                          if (announcement.status == AnnouncementStatus.draft)
                            TextButton(
                              onPressed: () =>
                                  _change(announcement, publish: true),
                              child: const Text('Publish'),
                            ),
                          TextButton(
                            onPressed: () =>
                                _change(announcement, publish: false),
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AnnouncementDialog extends ConsumerStatefulWidget {
  final bool platform;
  final int? clubId;

  const _AnnouncementDialog({required this.platform, this.clubId});

  @override
  ConsumerState<_AnnouncementDialog> createState() =>
      _AnnouncementDialogState();
}

class _AnnouncementDialogState extends ConsumerState<_AnnouncementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _publish = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(announcementsRepositoryProvider);
      final payload = {
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'publish': _publish,
      };
      if (widget.platform) {
        await repository.createPlatform(payload);
      } else {
        final clubId = widget.clubId;
        if (clubId == null) {
          throw StateError('Select an assigned club first.');
        }
        await repository.createClub(clubId, payload);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is ApiException
            ? error.message
            : error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.platform ? 'Platform announcement' : 'Announcement'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) =>
                    value == null || value.trim().length < 3
                    ? 'Enter at least 3 characters'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _body,
                decoration: const InputDecoration(labelText: 'Message'),
                maxLines: 5,
                validator: (value) =>
                    value == null || value.trim().isEmpty
                    ? 'Enter an announcement message'
                    : null,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _publish,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _publish = value ?? false),
                title: const Text('Publish now'),
              ),
              if (_error case final message?)
                Text(message, style: const TextStyle(color: AppColors.error)),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context, false),
        child: const Text('Close'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: _busy
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save'),
      ),
    ],
  );
}
