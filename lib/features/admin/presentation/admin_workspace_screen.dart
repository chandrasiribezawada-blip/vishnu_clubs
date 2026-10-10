import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/auth/providers/auth_providers.dart';
import '../../../shared/widgets/state_views.dart';
import '../providers/admin_providers.dart';

class AdminWorkspaceScreen extends ConsumerStatefulWidget {
  const AdminWorkspaceScreen({super.key});

  @override
  ConsumerState<AdminWorkspaceScreen> createState() =>
      _AdminWorkspaceScreenState();
}

class _AdminWorkspaceScreenState extends ConsumerState<AdminWorkspaceScreen> {
  String? _selectedUserId;
  int? _selectedClubId;
  bool _working = false;

  Future<void> _assign() async {
    if (_selectedUserId == null || _selectedClubId == null) return;
    setState(() => _working = true);
    try {
      await ref
          .read(apiClientProvider)
          .post(
            'admin/clubs/$_selectedClubId/coordinators',
            body: {'user_id': _selectedUserId},
          );
      ref.invalidate(adminWorkspaceProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Coordinator assigned.')));
    } catch (error) {
      if (!mounted) return;
      final message = error is ApiException
          ? error.message
          : 'Could not reach the server. Check your connection and try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _revoke(Map<String, dynamic> assignment) async {
    setState(() => _working = true);
    try {
      await ref
          .read(apiClientProvider)
          .delete(
            'admin/clubs/${assignment['club_id']}/coordinators/${assignment['user_id']}',
          );
      ref.invalidate(adminWorkspaceProvider);
    } catch (error) {
      if (!mounted) return;
      final message = error is ApiException
          ? error.message
          : 'Could not reach the server. Check your connection and try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminWorkspaceProvider);
    return state.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (error, _) => ErrorState(
        message: 'Could not load administrator data.',
        onRetry: () => ref.invalidate(adminWorkspaceProvider),
      ),
      data: (data) {
        final users = data.users;
        final clubs = data.clubs;
        final userValue = users.any((user) => user['id'] == _selectedUserId)
            ? _selectedUserId
            : users.isEmpty
            ? null
            : users.first['id'] as String;
        final clubValue = clubs.any((club) => club.id == _selectedClubId)
            ? _selectedClubId
            : clubs.isEmpty
            ? null
            : clubs.first.id;
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(adminWorkspaceProvider);
            await ref.read(adminWorkspaceProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.all(20),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Text(
                'Campus overview',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetricCard(
                    label: 'Active clubs',
                    value: data.dashboard['active_clubs'],
                    icon: Icons.groups_rounded,
                  ),
                  _MetricCard(
                    label: 'Active users',
                    value: data.dashboard['active_users'],
                    icon: Icons.people_alt_rounded,
                  ),
                  _MetricCard(
                    label: 'Students',
                    value: data.dashboard['total_students'],
                    icon: Icons.school_rounded,
                  ),
                  _MetricCard(
                    label: 'Coordinators',
                    value: data.dashboard['total_coordinators'],
                    icon: Icons.admin_panel_settings_rounded,
                  ),
                  _MetricCard(
                    label: 'Pending requests',
                    value: data.dashboard['pending_join_requests'],
                    icon: Icons.pending_actions_rounded,
                  ),
                  _MetricCard(
                    label: 'Events',
                    value: data.dashboard['events'],
                    icon: Icons.event_rounded,
                  ),
                  _MetricCard(
                    label: 'Registrations',
                    value: data.dashboard['active_event_registrations'],
                    icon: Icons.confirmation_number_rounded,
                  ),
                  _MetricCard(
                    label: 'Coordinator roles',
                    value: data.dashboard['coordinator_assignments'],
                    icon: Icons.admin_panel_settings_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Assign a coordinator',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              OutlinedButton.icon(
                onPressed: () => context.push('/admin/announcements'),
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Manage platform announcements'),
              ),
              const SizedBox(height: 10),
              if (users.isEmpty || clubs.isEmpty)
                const Text('An active user and club are required to assign.'),
              if (users.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: userValue,
                  decoration: const InputDecoration(labelText: 'User'),
                  items: users
                      .map(
                        (user) => DropdownMenuItem(
                          value: user['id'] as String,
                          child: Text(
                            '${user['full_name']} (${user['email']})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _selectedUserId = value),
                ),
              const SizedBox(height: 10),
              if (clubs.isNotEmpty)
                DropdownButtonFormField<int>(
                  initialValue: clubValue,
                  decoration: const InputDecoration(labelText: 'Club'),
                  items: clubs
                      .map(
                        (club) => DropdownMenuItem(
                          value: club.id,
                          child: Text(club.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _selectedClubId = value),
                ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _working || users.isEmpty || clubs.isEmpty
                    ? null
                    : _assign,
                icon: _working
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Assign coordinator'),
              ),
              const SizedBox(height: 24),
              Text(
                'Current assignments',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (data.assignments.isEmpty)
                const EmptyState(
                  icon: Icons.assignment_ind_outlined,
                  title: 'No coordinators assigned',
                  message: 'Assignments will appear here.',
                )
              else
                ...data.assignments.map(
                  (assignment) => Card(
                    child: ListTile(
                      title: Text(assignment['full_name'] as String),
                      subtitle: Text(
                        '${assignment['email']} · ${assignment['club_name']}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Revoke assignment',
                        onPressed: _working ? null : () => _revoke(assignment),
                        icon: const Icon(
                          Icons.person_remove_alt_1_rounded,
                          color: AppColors.error,
                        ),
                      ),
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

class _MetricCard extends StatelessWidget {
  final String label;
  final Object? value;
  final IconData icon;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 155,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(height: 8),
            Text(
              '$value',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}
