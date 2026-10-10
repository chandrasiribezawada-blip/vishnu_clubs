import 'package:clubs/core/network/api_exception.dart';
import 'package:clubs/features/events/data/events_repository.dart';
import 'package:clubs/features/events/presentation/coordinator_events_screen.dart';
import 'package:clubs/features/events/presentation/event_check_in_screen.dart';
import 'package:clubs/features/events/presentation/event_detail_screen.dart';
import 'package:clubs/features/events/presentation/event_pass_screen.dart';
import 'package:clubs/features/events/presentation/events_screen.dart';
import 'package:clubs/features/events/providers/events_providers.dart';
import 'package:clubs/features/memberships/data/membership_repository.dart';
import 'package:clubs/features/memberships/providers/membership_providers.dart';
import 'package:clubs/models/club.dart';
import 'package:clubs/models/event.dart';
import 'package:clubs/models/event_ticket.dart';
import 'package:clubs/models/join_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

const _club = Club(id: 7, name: 'Verified Club', category: null);

Event _event({
  EventStatus status = EventStatus.published,
  EventRegistrationStatus? registrationStatus,
  bool attended = false,
}) => Event(
  id: 41,
  title: 'Verified Workshop',
  clubId: _club.id,
  clubName: _club.name,
  startTime: DateTime.now().add(const Duration(days: 5)),
  endTime: DateTime.now().add(const Duration(days: 5, hours: 2)),
  registrationOpensAt: DateTime.now().subtract(const Duration(minutes: 1)),
  registrationClosesAt: DateTime.now().add(const Duration(days: 4)),
  venue: 'Auditorium',
  description: 'A real event record.',
  capacity: 20,
  registrationCount: registrationStatus == null ? 0 : 1,
  status: status,
  registrationStatus: registrationStatus,
  attended: attended,
);

class _EventsFake implements EventsRepository {
  Event event = _event();
  bool failReads = false;
  bool failRegistration = false;

  @override
  Future<Event> getEvent(int eventId) async {
    if (failReads) throw const ApiException(503, 'Service unavailable');
    return event;
  }

  @override
  Future<List<Event>> getPublishedEvents({bool includePast = false}) async {
    if (failReads) throw const ApiException(503, 'Service unavailable');
    return event.status == EventStatus.published ? [event] : [];
  }

  @override
  Future<List<Event>> getMyEvents() async =>
      event.registrationStatus == null ? [] : [event];

  @override
  Future<List<Event>> getManagedEvents(int clubId) async => [event];

  @override
  Future<Event> createEvent(int clubId, Map<String, Object?> details) async =>
      event;

  @override
  Future<Event> updateEvent(int eventId, Map<String, Object?> details) async =>
      event;

  @override
  Future<Event> publishEvent(int eventId) async {
    event = _event(status: EventStatus.published);
    return event;
  }

  @override
  Future<Event> cancelEvent(int eventId) async {
    event = _event(status: EventStatus.cancelled);
    return event;
  }

  @override
  Future<void> registerForEvent(int eventId) async {
    if (failRegistration) {
      throw const ApiException(409, 'Event is at capacity.');
    }
    event = _event(registrationStatus: EventRegistrationStatus.registered);
  }

  @override
  Future<void> cancelRegistration(int eventId) async {
    event = _event(registrationStatus: EventRegistrationStatus.cancelled);
  }

  @override
  Future<EventTicket> issuePass(int eventId) async => EventTicket(
    eventId: eventId,
    eventTitle: event.title,
    ticketToken: List.filled(43, 'x').join(),
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  );

  @override
  Future<Map<String, dynamic>> checkIn(int eventId, String ticketToken) async =>
      {'event_id': eventId, 'event_title': event.title};

  @override
  Future<Map<String, dynamic>> getAttendanceSummary(int eventId) async => {
    'event_id': eventId,
    'registered_count': 0,
    'attended_count': 0,
    'not_attended_count': 0,
  };

  @override
  Future<List<Map<String, dynamic>>> getParticipants(int eventId) async => [];

  @override
  Future<List<EventAttendance>> getMyAttendance() async => [];
}

class _MembershipFake implements MembershipRepository {
  List<Club> clubs = [_club];

  @override
  Future<List<Club>> getCoordinatorClubs() async => clubs;

  @override
  Future<List<ClubMembership>> getStudentMemberships() async => [];

  @override
  Future<List<JoinRequest>> getStudentRequests() async => [];

  @override
  Future<List<JoinRequest>> getPendingRequests(int clubId) async => [];

  @override
  Future<JoinRequest> submitJoinRequest({
    required Club club,
    required String reason,
    required String skills,
    String? experience,
  }) => throw UnimplementedError();

  @override
  Future<JoinRequest> decideRequest({
    required int requestId,
    required bool approve,
    String? note,
  }) => throw UnimplementedError();
}

Widget _detailApp(_EventsFake repository) {
  final router = GoRouter(
    initialLocation: '/events/41',
    routes: [
      GoRoute(
        path: '/events/:eventId',
        builder: (context, state) => EventDetailScreen(
          eventId: int.parse(state.pathParameters['eventId']!),
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: [eventsRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('event directory uses API provider and shows persisted events', (
    tester,
  ) async {
    final repository = _EventsFake();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [eventsRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: EventsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Verified Workshop'), findsOneWidget);
    expect(find.text('Verified Club'), findsOneWidget);
    await tester.tap(find.text('My events'));
    await tester.pumpAndSettle();
    expect(find.text('No events registered'), findsOneWidget);
  });

  testWidgets('event directory filters persisted events by search', (
    tester,
  ) async {
    final repository = _EventsFake();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [eventsRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: EventsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'no matching event',
    );
    await tester.pumpAndSettle();
    expect(find.text('No matching events'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.clear_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Verified Workshop'), findsOneWidget);
  });

  testWidgets('student registration refreshes My Events state', (tester) async {
    final repository = _EventsFake();
    await tester.pumpWidget(_detailApp(repository));
    await tester.pumpAndSettle();
    expect(find.text('Register for event'), findsOneWidget);
    await tester.tap(find.text('Register for event'));
    await tester.pumpAndSettle();

    expect(find.text('You are registered.'), findsOneWidget);
    expect(find.text('Cancel registration'), findsOneWidget);
    expect(
      repository.event.registrationStatus,
      EventRegistrationStatus.registered,
    );
  });

  testWidgets('event detail shows server-recorded attendance status', (
    tester,
  ) async {
    final repository = _EventsFake()
      ..event = _event(
        registrationStatus: EventRegistrationStatus.registered,
        attended: true,
      );
    await tester.pumpWidget(_detailApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('Attendance recorded'), findsOneWidget);
    expect(find.text('Show event pass'), findsNothing);
  });

  testWidgets('registered student can load their QR event pass', (
    tester,
  ) async {
    final repository = _EventsFake()
      ..event = _event(registrationStatus: EventRegistrationStatus.registered);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [eventsRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: EventPassScreen(event: repository.event)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Verified Workshop'), findsOneWidget);
    expect(find.textContaining('Show this QR code'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('coordinator check-in validates a pass and reports success', (
    tester,
  ) async {
    final repository = _EventsFake();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [eventsRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: EventCheckInScreen(
            eventId: 41,
            eventTitle: 'Verified Workshop',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Validate pass'));
    await tester.tap(find.text('Validate pass'));
    await tester.pumpAndSettle();
    expect(
      find.text('This QR code is not a valid event pass.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), List.filled(43, 'x').join());
    await tester.tap(find.text('Validate pass'));
    await tester.pumpAndSettle();
    expect(
      find.text('Attendance recorded for Verified Workshop'),
      findsOneWidget,
    );
  });

  testWidgets('event detail shows network and capacity errors', (tester) async {
    final repository = _EventsFake()..failRegistration = true;
    await tester.pumpWidget(_detailApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Register for event'));
    await tester.pumpAndSettle();

    expect(find.text('Event is at capacity.'), findsOneWidget);
  });

  testWidgets('event detail has a network-error state', (tester) async {
    final repository = _EventsFake()..failReads = true;
    await tester.pumpWidget(_detailApp(repository));
    await tester.pumpAndSettle();
    expect(find.text('Could not load event details.'), findsOneWidget);
  });

  testWidgets('coordinator can publish only the event in managed queue', (
    tester,
  ) async {
    final eventRepository = _EventsFake()
      ..event = _event(status: EventStatus.draft);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventsRepositoryProvider.overrideWithValue(eventRepository),
          membershipRepositoryProvider.overrideWithValue(_MembershipFake()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CoordinatorEventsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Verified Workshop'), findsOneWidget);
    expect(find.text('Publish'), findsOneWidget);
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();
    expect(find.text('Event published.'), findsOneWidget);
    expect(eventRepository.event.status, EventStatus.published);
  });
}
