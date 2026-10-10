import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/club.dart';
import '../../../models/join_request.dart';
import '../../../shared/widgets/state_views.dart';
import '../providers/membership_providers.dart';

class CoordinatorRequestsScreen extends ConsumerStatefulWidget {
  const CoordinatorRequestsScreen({super.key});

  @override
  ConsumerState<CoordinatorRequestsScreen> createState() =>
      _CoordinatorRequestsScreenState();
}

class _CoordinatorRequestsScreenState
    extends ConsumerState<CoordinatorRequestsScreen> {
  int? _selectedClubId;

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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
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
            Expanded(child: _RequestsPanel(club: selectedClub)),
          ],
        );
      },
    );
  }
}

class _RequestsPanel extends ConsumerStatefulWidget {
  final Club club;

  const _RequestsPanel({required this.club});

  @override
  ConsumerState<_RequestsPanel> createState() => _RequestsPanelState();
}

class _RequestsPanelState extends ConsumerState<_RequestsPanel> {
  int? _busyRequestId;

  Future<void> _decide(JoinRequest request, {required bool approve}) async {
    setState(() => _busyRequestId = request.id);
    try {
      await ref
          .read(membershipRepositoryProvider)
          .decideRequest(requestId: request.id, approve: approve);
      ref.invalidate(pendingClubRequestsProvider(widget.club.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              approve
                  ? '${request.studentName ?? 'Student'} approved for ${widget.club.name}.'
                  : 'Request from ${request.studentName ?? 'student'} rejected.',
            ),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      final message = error is ApiException
          ? error.message
          : 'Could not reach the server. Check your connection and try again.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busyRequestId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requestsState = ref.watch(
      pendingClubRequestsProvider(widget.club.id),
    );
    return requestsState.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (error, _) => ErrorState(
        message: 'Could not load pending requests for ${widget.club.name}.',
        onRetry: () =>
            ref.invalidate(pendingClubRequestsProvider(widget.club.id)),
      ),
      data: (requests) {
        if (requests.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async {
              final provider = pendingClubRequestsProvider(widget.club.id);
              ref.invalidate(provider);
              await ref.read(provider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 100),
                EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'No pending requests',
                  message: 'New applications for this club will appear here.',
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            final provider = pendingClubRequestsProvider(widget.club.id);
            ref.invalidate(provider);
            await ref.read(provider.future);
          },
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: requests.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final request = requests[index];
              final busy = _busyRequestId == request.id;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.studentName ?? 'Student applicant',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${request.studentEmail ?? ''} · Applied ${MaterialLocalizations.of(context).formatShortDate(request.createdAt.toLocal())}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 14),
                      Text(request.reason),
                      const SizedBox(height: 10),
                      Text(
                        'Skills: ${request.skills}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (request.experience case final experience?)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('Experience: $experience'),
                        ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _busyRequestId == null
                                  ? () => _decide(request, approve: false)
                                  : null,
                              child: const Text('Reject'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: _busyRequestId == null
                                  ? () => _decide(request, approve: true)
                                  : null,
                              child: busy
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Approve'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
