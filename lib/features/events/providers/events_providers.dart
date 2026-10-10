import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/event.dart';
import '../../../models/event_ticket.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/events_repository.dart';

final eventsRepositoryProvider = Provider<EventsRepository>(
  (ref) => ApiEventsRepository(ref.watch(apiClientProvider)),
);

final upcomingEventsProvider = FutureProvider.autoDispose<List<Event>>(
  (ref) => ref.watch(eventsRepositoryProvider).getPublishedEvents(),
);

final allPublishedEventsProvider = FutureProvider.autoDispose<List<Event>>(
  (ref) => ref
      .watch(eventsRepositoryProvider)
      .getPublishedEvents(includePast: true),
);

final myEventsProvider = FutureProvider.autoDispose<List<Event>>(
  (ref) => ref.watch(eventsRepositoryProvider).getMyEvents(),
);

final myAttendanceProvider = FutureProvider.autoDispose<List<EventAttendance>>(
  (ref) => ref.watch(eventsRepositoryProvider).getMyAttendance(),
);

final eventByIdProvider = FutureProvider.autoDispose.family<Event, int>((
  ref,
  eventId,
) {
  return ref.watch(eventsRepositoryProvider).getEvent(eventId);
});

final managedClubEventsProvider = FutureProvider.autoDispose
    .family<List<Event>, int>((ref, clubId) {
      return ref.watch(eventsRepositoryProvider).getManagedEvents(clubId);
    });

class EventMutationController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> register(int eventId) =>
      _run(() => ref.read(eventsRepositoryProvider).registerForEvent(eventId));

  Future<void> cancelRegistration(int eventId) => _run(
    () => ref.read(eventsRepositoryProvider).cancelRegistration(eventId),
  );

  Future<void> publish(int eventId) =>
      _run(() => ref.read(eventsRepositoryProvider).publishEvent(eventId));

  Future<void> cancelEvent(int eventId) =>
      _run(() => ref.read(eventsRepositoryProvider).cancelEvent(eventId));

  Future<void> create(int clubId, Map<String, Object?> details) => _run(
    () => ref.read(eventsRepositoryProvider).createEvent(clubId, details),
  );

  Future<void> editEvent(int eventId, Map<String, Object?> details) => _run(
    () => ref.read(eventsRepositoryProvider).updateEvent(eventId, details),
  );

  Future<void> _run(Future<Object?> Function() operation) async {
    state = const AsyncLoading();
    try {
      await operation();
      state = const AsyncData(null);
      ref.invalidate(upcomingEventsProvider);
      ref.invalidate(myEventsProvider);
      ref.invalidate(managedClubEventsProvider);
      ref.invalidate(eventByIdProvider);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

final eventMutationControllerProvider =
    AsyncNotifierProvider<EventMutationController, void>(
      EventMutationController.new,
    );
