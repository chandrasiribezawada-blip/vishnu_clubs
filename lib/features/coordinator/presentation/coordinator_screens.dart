import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/state_views.dart';
import '../providers/coordinator_providers.dart';
import 'widgets/coordinator_state.dart';

class CoordinatorDashboardScreen extends ConsumerWidget {
  const CoordinatorDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(coordinatorClubProvider);
    final stats = ref.watch(coordinatorStatsProvider);
    return coordinatorAsyncState(
      value: club,
      retry: () => ref.invalidate(coordinatorClubProvider),
      data: (clubData) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(coordinatorClubProvider);
          ref.invalidate(coordinatorStatsProvider);
          await Future.wait([
            ref.read(coordinatorClubProvider.future),
            ref.read(coordinatorStatsProvider.future),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Text(
              clubData['name']?.toString() ?? 'My club',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            stats.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => ErrorState(
                message: 'Could not load club statistics: $error',
                onRetry: () => ref.invalidate(coordinatorStatsProvider),
              ),
              data: (values) => Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _Metric(label: 'Members', value: values['members']),
                  _Metric(
                    label: 'Pending requests',
                    value: values['pending_join_requests'],
                  ),
                  _Metric(
                    label: 'Upcoming events',
                    value: values['upcoming_events'],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => context.push('/coordinator/requests'),
              icon: const Icon(Icons.pending_actions),
              label: const Text('Review join requests'),
            ),
          ],
        ),
      ),
    );
  }
}

class CoordinatorRequestsScreen extends ConsumerWidget {
  const CoordinatorRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(coordinatorRequestsProvider);
    return coordinatorAsyncState(
      value: state,
      retry: () => ref.invalidate(coordinatorRequestsProvider),
      data: (requests) {
        if (requests.isEmpty) {
          return const EmptyState(
            icon: Icons.inbox_outlined,
            title: 'No join requests',
            message: 'New requests for your club will appear here.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final request = requests[index];
            final pending = request['status'] == 'PENDING';
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request['student_name']?.toString() ?? 'Student',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(request['student_email']?.toString() ?? ''),
                    const SizedBox(height: 10),
                    Text('Reason: ${request['reason'] ?? ''}'),
                    Text('Skills: ${request['skills'] ?? ''}'),
                    if (request['experience'] != null)
                      Text('Experience: ${request['experience']}'),
                    if (pending) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton(
                            onPressed: () =>
                                _decide(context, ref, request, 'approve'),
                            child: const Text('Approve'),
                          ),
                          OutlinedButton(
                            onPressed: () =>
                                _decide(context, ref, request, 'reject'),
                            child: const Text('Reject'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> request,
    String decision,
  ) async {
    try {
      await ref
          .read(coordinatorRepositoryProvider)
          .decide(request['id'] as int, decision);
      ref.invalidate(coordinatorRequestsProvider);
      ref.invalidate(coordinatorStatsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Request ${decision}d successfully.')),
        );
      }
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }
}

class CoordinatorMembersScreen extends ConsumerStatefulWidget {
  const CoordinatorMembersScreen({super.key});

  @override
  ConsumerState<CoordinatorMembersScreen> createState() =>
      _CoordinatorMembersScreenState();
}

class _CoordinatorMembersScreenState
    extends ConsumerState<CoordinatorMembersScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(coordinatorMembersProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search members',
            ),
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
        ),
        Expanded(
          child: coordinatorAsyncState(
            value: state,
            retry: () => ref.invalidate(coordinatorMembersProvider),
            data: (members) {
              final filtered = members.where((member) {
                final search = '${member['full_name']} ${member['email']}'
                    .toLowerCase();
                return search.contains(_query.toLowerCase());
              }).toList();
              if (filtered.isEmpty) {
                return const EmptyState(
                  icon: Icons.groups_outlined,
                  title: 'No members found',
                  message: 'Members of your club will appear here.',
                );
              }
              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final member = filtered[index];
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(member['full_name']?.toString() ?? ''),
                    subtitle: Text(
                      '${member['email'] ?? ''}\n${member['department'] ?? ''}',
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: 'Remove member',
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: () => _remove(member),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _remove(Map<String, dynamic> member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text('Remove ${member['full_name']} from this club?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep member'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(coordinatorRepositoryProvider)
          .removeMember(member['user_id'] as String);
      ref.invalidate(coordinatorMembersProvider);
      ref.invalidate(coordinatorStatsProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Member removed.')));
      }
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }
}

class CoordinatorEventsScreen extends ConsumerWidget {
  const CoordinatorEventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(coordinatorEventsProvider);
    return coordinatorAsyncState(
      value: state,
      retry: () => ref.invalidate(coordinatorEventsProvider),
      data: (events) {
        if (events.isEmpty) {
          return const EmptyState(
            icon: Icons.event_busy_outlined,
            title: 'No events yet',
            message: 'Events managed by your club will appear here.',
          );
        }
        return ListView.builder(
          itemCount: events.length,
          itemBuilder: (context, index) {
            final event = events[index];
            return ListTile(
              title: Text(event['title']?.toString() ?? ''),
              subtitle: Text(
                '${event['venue'] ?? ''} · ${event['status'] ?? ''}',
              ),
              trailing: IconButton(
                tooltip: 'Cancel event',
                icon: const Icon(Icons.cancel_outlined),
                onPressed: event['status'] == 'CANCELLED'
                    ? null
                    : () async {
                        try {
                          await ref
                              .read(coordinatorRepositoryProvider)
                              .cancelEvent(event['id'] as int);
                          ref.invalidate(coordinatorEventsProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Event cancelled.')),
                            );
                          }
                        } catch (error) {
                          if (context.mounted) _showError(context, error);
                        }
                      },
              ),
            );
          },
        );
      },
    );
  }
}

class CoordinatorClubScreen extends ConsumerStatefulWidget {
  const CoordinatorClubScreen({super.key});

  @override
  ConsumerState<CoordinatorClubScreen> createState() =>
      _CoordinatorClubScreenState();
}

class _CoordinatorClubScreenState extends ConsumerState<CoordinatorClubScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _description = TextEditingController();
  final _objectives = TextEditingController();
  final _contact = TextEditingController();
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _description.dispose();
    _objectives.dispose();
    _contact.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(coordinatorClubProvider);
    return coordinatorAsyncState(
      value: state,
      retry: () => ref.invalidate(coordinatorClubProvider),
      data: (club) {
        if (!_initialized) {
          _name.text = club['name']?.toString() ?? '';
          _category.text = club['category']?.toString() ?? '';
          _description.text = club['description']?.toString() ?? '';
          _objectives.text = club['objectives']?.toString() ?? '';
          _contact.text = club['contact_email']?.toString() ?? '';
          _initialized = true;
        }
        return Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Club profile',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _field(_name, 'Club name', required: true),
              _field(_category, 'Category'),
              _field(_description, 'Description', maxLines: 4),
              _field(_objectives, 'Objectives', maxLines: 4),
              _field(_contact, 'Contact email'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const CircularProgressIndicator()
                    : const Text('Save changes'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
        validator: required
            ? (value) => value == null || value.trim().length < 2
                  ? 'Enter at least two characters.'
                  : null
            : null,
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(coordinatorRepositoryProvider).updateClub({
        'name': _name.text.trim(),
        'category': _category.text.trim(),
        'description': _description.text.trim(),
        'objectives': _objectives.text.trim(),
        'contact_email': _contact.text.trim(),
      });
      ref.invalidate(coordinatorClubProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Club profile updated.')));
      }
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 155,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value?.toString() ?? '0',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(label, style: const TextStyle(color: AppColors.textMuted)),
          ],
        ),
      ),
    ),
  );
}

void _showError(BuildContext context, Object error) {
  final message = error is ApiException
      ? error.message
      : 'Could not reach the server. Check your connection and try again.';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
