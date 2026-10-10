import '../../../core/network/api_client.dart';
import '../../../models/event.dart';
import '../../../models/event_ticket.dart';

abstract class EventsRepository {
  Future<List<Event>> getPublishedEvents({bool includePast = false});
  Future<List<Event>> getMyEvents();
  Future<Event> getEvent(int eventId);
  Future<List<Event>> getManagedEvents(int clubId);
  Future<Event> createEvent(int clubId, Map<String, Object?> details);
  Future<Event> updateEvent(int eventId, Map<String, Object?> details);
  Future<Event> publishEvent(int eventId);
  Future<Event> cancelEvent(int eventId);
  Future<void> registerForEvent(int eventId);
  Future<void> cancelRegistration(int eventId);
  Future<EventTicket> issuePass(int eventId);
  Future<Map<String, dynamic>> checkIn(int eventId, String ticketToken);
  Future<Map<String, dynamic>> getAttendanceSummary(int eventId);
  Future<List<Map<String, dynamic>>> getParticipants(int eventId);
  Future<List<EventAttendance>> getMyAttendance();
}

class ApiEventsRepository implements EventsRepository {
  final ApiClient _apiClient;

  const ApiEventsRepository(this._apiClient);

  @override
  Future<List<Event>> getPublishedEvents({bool includePast = false}) async {
    final path = includePast ? 'events?include_past=true' : 'events';
    final response = await _apiClient.getList(path, authenticated: false);
    return response.map(Event.fromJson).toList();
  }

  @override
  Future<List<Event>> getMyEvents() async {
    final response = await _apiClient.getList('me/events');
    return response.map(Event.fromJson).toList();
  }

  @override
  Future<Event> getEvent(int eventId) async {
    return Event.fromJson(await _apiClient.getObject('events/$eventId'));
  }

  @override
  Future<List<Event>> getManagedEvents(int clubId) async {
    final response = await _apiClient.getList('clubs/$clubId/events/manage');
    return response.map(Event.fromJson).toList();
  }

  @override
  Future<Event> createEvent(int clubId, Map<String, Object?> details) async {
    return Event.fromJson(
      await _apiClient.post('clubs/$clubId/events', body: details),
    );
  }

  @override
  Future<Event> updateEvent(int eventId, Map<String, Object?> details) async {
    return Event.fromJson(
      await _apiClient.patch('events/$eventId', body: details),
    );
  }

  @override
  Future<Event> publishEvent(int eventId) async =>
      Event.fromJson(await _apiClient.post('events/$eventId/publish'));

  @override
  Future<Event> cancelEvent(int eventId) async =>
      Event.fromJson(await _apiClient.post('events/$eventId/cancel'));

  @override
  Future<void> registerForEvent(int eventId) async {
    await _apiClient.post('events/$eventId/registrations');
  }

  @override
  Future<void> cancelRegistration(int eventId) async {
    await _apiClient.delete('events/$eventId/registrations/me');
  }

  @override
  Future<EventTicket> issuePass(int eventId) async {
    final response = await _apiClient.post('events/$eventId/pass');
    return EventTicket.fromJson(response, eventId);
  }

  @override
  Future<Map<String, dynamic>> checkIn(
    int eventId,
    String ticketToken,
  ) async => _apiClient.post(
    'events/$eventId/attendance/check-in',
    body: {'ticket_token': ticketToken},
  );

  @override
  Future<Map<String, dynamic>> getAttendanceSummary(int eventId) =>
      _apiClient.getObject('events/$eventId/attendance/summary');

  @override
  Future<List<Map<String, dynamic>>> getParticipants(int eventId) =>
      _apiClient.getList('events/$eventId/participants');

  @override
  Future<List<EventAttendance>> getMyAttendance() async {
    final response = await _apiClient.getList('me/attendance');
    return response.map(EventAttendance.fromJson).toList();
  }
}
