import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/auth/providers/auth_providers.dart';
import '../../../shared/widgets/state_views.dart';

final _adminClubsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
      (ref) => ref.watch(apiClientProvider).getList('admin/clubs'),
    );

final _adminEventsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
      (ref) => ref.watch(apiClientProvider).getList('admin/events'),
    );

class AdminClubsScreen extends ConsumerWidget {
  const AdminClubsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_adminClubsProvider);
    return state.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (error, _) => ErrorState(
        message: 'Could not load clubs: $error',
        onRetry: () => ref.invalidate(_adminClubsProvider),
      ),
      data: (clubs) {
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _createClub(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Add club'),
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_adminClubsProvider);
              await ref.read(_adminClubsProvider.future);
            },
            child: clubs.isEmpty
                ? ListView(
                    physics: AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: 300,
                        child: EmptyState(
                          icon: Icons.groups_outlined,
                          title: 'No clubs',
                          message: 'Create a club to get started.',
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: clubs.length,
                    itemBuilder: (context, index) {
                      final club = clubs[index];
                      final active = club['is_active'] == true;
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.groups)),
                        title: Text(club['name']?.toString() ?? ''),
                        subtitle: Text(
                          '${club['category'] ?? 'Uncategorized'} · ${active ? 'Active' : 'Inactive'}',
                        ),
                        trailing: Switch(
                          value: active,
                          onChanged: (value) => _setActive(
                            context,
                            ref,
                            club['id'] as int,
                            value,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  Future<void> _createClub(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final category = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create club'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Club name'),
                validator: (value) => value == null || value.trim().length < 2
                    ? 'Enter a club name.'
                    : null,
              ),
              TextField(
                controller: category,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, {
                  'name': name.text.trim(),
                  'category': category.text.trim(),
                });
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    name.dispose();
    category.dispose();
    if (values == null) return;
    try {
      await ref.read(apiClientProvider).post('admin/clubs', body: values);
      ref.invalidate(_adminClubsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Club created.')));
      }
    } catch (error) {
      if (context.mounted) _showAdminError(context, error);
    }
  }

  Future<void> _setActive(
    BuildContext context,
    WidgetRef ref,
    int clubId,
    bool active,
  ) async {
    try {
      await ref
          .read(apiClientProvider)
          .patch(
            'admin/clubs/$clubId/activation?active=$active',
            body: const {},
          );
      ref.invalidate(_adminClubsProvider);
    } catch (error) {
      if (context.mounted) _showAdminError(context, error);
    }
  }
}

class AdminModerationScreen extends ConsumerWidget {
  const AdminModerationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_adminEventsProvider);
    return state.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (error, _) => ErrorState(
        message: 'Could not load events: $error',
        onRetry: () => ref.invalidate(_adminEventsProvider),
      ),
      data: (events) {
        if (events.isEmpty) {
          return const EmptyState(
            icon: Icons.event_busy_outlined,
            title: 'No events',
            message: 'Events requiring moderation will appear here.',
          );
        }
        return ListView.builder(
          itemCount: events.length,
          itemBuilder: (context, index) {
            final event = events[index];
            final cancelled = event['status'] == 'CANCELLED';
            return ListTile(
              title: Text(event['title']?.toString() ?? ''),
              subtitle: Text(
                '${event['club_name'] ?? ''} · ${event['status'] ?? ''}',
              ),
              trailing: IconButton(
                tooltip: 'Cancel event',
                onPressed: cancelled
                    ? null
                    : () async {
                        try {
                          await ref
                              .read(apiClientProvider)
                              .post('admin/events/${event['id']}/cancel');
                          ref.invalidate(_adminEventsProvider);
                        } catch (error) {
                          if (context.mounted) _showAdminError(context, error);
                        }
                      },
                icon: const Icon(Icons.cancel_outlined),
              ),
            );
          },
        );
      },
    );
  }
}

void _showAdminError(BuildContext context, Object error) {
  final message = error is ApiException
      ? error.message
      : 'Could not reach the server. Check your connection and try again.';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
