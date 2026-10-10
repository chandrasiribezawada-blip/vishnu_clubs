import 'package:clubs/core/network/api_exception.dart';
import 'package:clubs/features/clubs/data/clubs_repository.dart';
import 'package:clubs/features/clubs/providers/clubs_providers.dart';
import 'package:clubs/features/memberships/data/membership_repository.dart';
import 'package:clubs/features/memberships/presentation/coordinator_requests_screen.dart';
import 'package:clubs/features/memberships/presentation/join_request_screen.dart';
import 'package:clubs/features/memberships/providers/membership_providers.dart';
import 'package:clubs/models/club.dart';
import 'package:clubs/models/join_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _club = Club(id: 1, name: 'Design Club', category: null);

class _FakeClubsRepository implements ClubsRepository {
  @override
  Future<List<Club>> getClubs() async => [_club];
}

class _FakeMembershipRepository implements MembershipRepository {
  List<JoinRequest> pendingRequests = [];
  bool failCoordinatorClubs = false;
  bool failSubmission = false;
  int submitCalls = 0;

  @override
  Future<List<JoinRequest>> getStudentRequests() async => pendingRequests;

  @override
  Future<List<ClubMembership>> getStudentMemberships() async => [];

  @override
  Future<List<Club>> getCoordinatorClubs() async {
    if (failCoordinatorClubs) {
      throw const ApiException(503, 'Coordinator clubs unavailable');
    }
    return [_club];
  }

  @override
  Future<List<JoinRequest>> getPendingRequests(int clubId) async =>
      pendingRequests.where((request) => request.clubId == clubId).toList();

  @override
  Future<JoinRequest> submitJoinRequest({
    required Club club,
    required String reason,
    required String skills,
    String? experience,
  }) async {
    submitCalls++;
    if (failSubmission) {
      throw const ApiException(409, 'A pending request already exists.');
    }
    return JoinRequest(
      id: 12,
      clubId: club.id,
      clubName: club.name,
      reason: reason,
      skills: skills,
      experience: experience,
      status: JoinRequestStatus.pending,
      createdAt: DateTime.utc(2026),
    );
  }

  @override
  Future<JoinRequest> decideRequest({
    required int requestId,
    required bool approve,
    String? note,
  }) async {
    final request = pendingRequests.firstWhere((item) => item.id == requestId);
    pendingRequests = pendingRequests
        .where((item) => item.id != requestId)
        .toList();
    return JoinRequest(
      id: request.id,
      clubId: request.clubId,
      clubName: request.clubName,
      reason: request.reason,
      skills: request.skills,
      status: approve ? JoinRequestStatus.approved : JoinRequestStatus.rejected,
      createdAt: request.createdAt,
    );
  }
}

Widget _joinFormApp(_FakeMembershipRepository repository) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) => Scaffold(
          body: TextButton(
            onPressed: () => context.push('/club/1/join'),
            child: const Text('Open join form'),
          ),
        ),
      ),
      GoRoute(
        path: '/club/:id/join',
        builder: (context, state) =>
            JoinRequestScreen(clubId: int.parse(state.pathParameters['id']!)),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      clubsRepositoryProvider.overrideWithValue(_FakeClubsRepository()),
      membershipRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Widget _coordinatorApp(_FakeMembershipRepository repository) => ProviderScope(
  overrides: [membershipRepositoryProvider.overrideWithValue(repository)],
  child: const MaterialApp(home: Scaffold(body: CoordinatorRequestsScreen())),
);

JoinRequest _pendingRequest({int id = 21}) => JoinRequest(
  id: id,
  clubId: _club.id,
  clubName: _club.name,
  reason: 'I want to contribute to club projects.',
  skills: 'Design and illustration',
  status: JoinRequestStatus.pending,
  createdAt: DateTime.utc(2026, 6, 1),
  studentName: 'A Student',
  studentEmail: 'student@example.edu',
);

void main() {
  testWidgets('join request validates required application details', (
    tester,
  ) async {
    final repository = _FakeMembershipRepository();
    await tester.pumpWidget(_joinFormApp(repository));
    await tester.tap(find.text('Open join form'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Submit request'));
    await tester.tap(find.text('Submit request'));
    await tester.pumpAndSettle();

    expect(find.text('Reason is required'), findsOneWidget);
    expect(find.text('Skills is required'), findsOneWidget);
    expect(repository.submitCalls, 0);
  });

  testWidgets('join request shows server validation errors', (tester) async {
    final repository = _FakeMembershipRepository()..failSubmission = true;
    await tester.pumpWidget(_joinFormApp(repository));
    await tester.tap(find.text('Open join form'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'I want to contribute to club projects.',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Design and illustration',
    );
    await tester.ensureVisible(find.text('Submit request'));
    await tester.tap(find.text('Submit request'));
    await tester.pumpAndSettle();

    expect(find.text('A pending request already exists.'), findsOneWidget);
    expect(repository.submitCalls, 1);
  });

  testWidgets('join request submits successfully to the repository', (
    tester,
  ) async {
    final repository = _FakeMembershipRepository();
    await tester.pumpWidget(_joinFormApp(repository));
    await tester.tap(find.text('Open join form'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'I want to contribute to club projects.',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Design and illustration',
    );
    await tester.ensureVisible(find.text('Submit request'));
    await tester.tap(find.text('Submit request'));
    await tester.pumpAndSettle();

    expect(repository.submitCalls, 1);
    expect(find.text('Open join form'), findsOneWidget);
    expect(find.textContaining('Request sent to Design Club.'), findsOneWidget);
  });

  testWidgets(
    'coordinator approves a pending request and refreshes the queue',
    (tester) async {
      final repository = _FakeMembershipRepository()
        ..pendingRequests = [_pendingRequest(), _pendingRequest(id: 22)];
      await tester.pumpWidget(_coordinatorApp(repository));
      await tester.pumpAndSettle();

      expect(find.text('A Student'), findsNWidgets(2));
      expect(find.text('Skills: Design and illustration'), findsNWidgets(2));
      await tester.tap(find.text('Reject').first);
      await tester.pumpAndSettle();
      expect(find.text('Request from A Student rejected.'), findsOneWidget);

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(find.text('No pending requests'), findsOneWidget);
      expect(find.text('A Student approved for Design Club.'), findsOneWidget);
    },
  );

  testWidgets('coordinator sees empty and network-error states', (
    tester,
  ) async {
    final repository = _FakeMembershipRepository();
    await tester.pumpWidget(_coordinatorApp(repository));
    await tester.pumpAndSettle();
    expect(find.text('No pending requests'), findsOneWidget);

    await tester.pumpWidget(
      _coordinatorApp(_FakeMembershipRepository()..failCoordinatorClubs = true),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load your assigned clubs.'), findsOneWidget);
  });
}
