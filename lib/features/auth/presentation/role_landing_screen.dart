import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/app_user.dart';
import '../../admin/presentation/admin_workspace_screen.dart';
import '../../events/presentation/coordinator_events_screen.dart';
import '../../memberships/presentation/coordinator_requests_screen.dart';
import '../../announcements/presentation/announcements_screen.dart';
import '../providers/auth_providers.dart';

class RoleLandingScreen extends ConsumerWidget {
  const RoleLandingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final title = switch (user?.role) {
      AppRole.coordinator => 'Coordinator workspace',
      AppRole.admin => 'Club admin workspace',
      _ => 'Account workspace',
    };

    if (user?.role == AppRole.coordinator) {
      return DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              IconButton(
                tooltip: 'Log out',
                onPressed: () =>
                    ref.read(authControllerProvider.notifier).logout(),
                icon: const Icon(Icons.logout_rounded),
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Join requests'),
                Tab(text: 'Events'),
                Tab(text: 'Announcements'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              CoordinatorRequestsScreen(),
              CoordinatorEventsScreen(),
              AnnouncementsScreen(),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: switch (user?.role) {
        AppRole.coordinator => const CoordinatorRequestsScreen(),
        AppRole.admin => const AdminWorkspaceScreen(),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
