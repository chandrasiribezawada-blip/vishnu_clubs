import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/announcements/presentation/announcements_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/admin/presentation/admin_management_screens.dart';
import '../../features/admin/presentation/admin_workspace_screen.dart';
import '../../features/clubs/presentation/club_detail_screen.dart';
import '../../features/clubs/presentation/clubs_screen.dart';
import '../../features/coordinator/presentation/coordinator_screens.dart';
import '../../features/events/presentation/event_detail_screen.dart';
import '../../features/events/presentation/events_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/memberships/presentation/join_request_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/shell/admin_shell.dart';
import '../../features/shell/coordinator_shell.dart';
import '../../features/shell/student_shell.dart';
import '../../models/app_user.dart';

String roleHome(AppRole role) => switch (role) {
  AppRole.student => '/home',
  AppRole.coordinator => '/coordinator',
  AppRole.admin => '/admin',
};

bool _isWithin(String path, String prefix) =>
    path == prefix || path.startsWith('$prefix/');

bool _canAccessRolePath(AppRole role, String path) => switch (role) {
  AppRole.student =>
    _isWithin(path, '/home') ||
        _isWithin(path, '/clubs') ||
        _isWithin(path, '/events') ||
        _isWithin(path, '/profile') ||
        _isWithin(path, '/club') ||
        _isWithin(path, '/notifications') ||
        _isWithin(path, '/announcements'),
  AppRole.coordinator => _isWithin(path, '/coordinator'),
  AppRole.admin => _isWithin(path, '/admin'),
};

GoRouter createAppRouter({
  required Listenable refreshListenable,
  required AsyncValue<AppUser?> Function() readSession,
}) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final path = state.uri.path;
      final publicPath = path == '/login' || path == '/register';
      final session = readSession();

      if (session.isLoading) {
        return path == '/splash' ? null : '/splash';
      }
      if (session.hasError) {
        return path == '/login' ? null : '/login';
      }

      final user = (session as AsyncData<AppUser?>).value;
      if (user == null) {
        if (publicPath) return null;
        return '/login';
      }

      final home = roleHome(user.role);
      if (publicPath || path == '/splash' || path == '/') return home;
      if (!_canAccessRolePath(user.role, path)) return home;
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/announcements',
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: const Text('Announcements')),
          body: const AnnouncementsScreen(),
        ),
      ),
      GoRoute(
        path: '/admin/announcements',
        builder: (context, state) => const AnnouncementsScreen(admin: true),
      ),
      GoRoute(
        path: '/club/:id',
        builder: (context, state) =>
            ClubDetailScreen(clubId: int.parse(state.pathParameters['id']!)),
        routes: [
          GoRoute(
            path: 'join',
            builder: (context, state) => JoinRequestScreen(
              clubId: int.parse(state.pathParameters['id']!),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/events/:eventId',
        builder: (context, state) => EventDetailScreen(
          eventId: int.parse(state.pathParameters['eventId']!),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            StudentShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/clubs',
                builder: (context, state) => const ClubsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/events',
                builder: (context, state) => const EventsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            CoordinatorShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/coordinator',
                builder: (context, state) => const CoordinatorDashboardScreen(),
                routes: [
                  GoRoute(
                    path: 'requests',
                    builder: (context, state) =>
                        const CoordinatorRequestsScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/coordinator/members',
                builder: (context, state) => const CoordinatorMembersScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/coordinator/events',
                builder: (context, state) => const CoordinatorEventsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/coordinator/club',
                builder: (context, state) => const CoordinatorClubScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/coordinator/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AdminShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin',
                builder: (context, state) => const AdminWorkspaceScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin/clubs',
                builder: (context, state) => const AdminClubsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin/requests',
                builder: (context, state) => const AdminModerationScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
