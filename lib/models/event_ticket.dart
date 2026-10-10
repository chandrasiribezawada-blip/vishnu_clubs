import 'dart:convert';

class EventTicket {
  final int eventId;
  final String eventTitle;
  final String ticketToken;
  final DateTime expiresAt;

  const EventTicket({
    required this.eventId,
    required this.eventTitle,
    required this.ticketToken,
    required this.expiresAt,
  });

  String get qrValue => jsonEncode({
    'event_id': eventId,
    'ticket_token': ticketToken,
  });

  factory EventTicket.fromJson(Map<String, dynamic> json, int eventId) =>
      EventTicket(
        eventId: eventId,
        eventTitle: json['event_title'] as String? ?? '',
        ticketToken: json['ticket_token'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}

class EventAttendance {
  final int eventId;
  final String eventTitle;
  final String clubName;
  final DateTime checkedInAt;

  const EventAttendance({
    required this.eventId,
    required this.eventTitle,
    required this.clubName,
    required this.checkedInAt,
  });

  factory EventAttendance.fromJson(Map<String, dynamic> json) =>
      EventAttendance(
        eventId: (json['event_id'] as num).toInt(),
        eventTitle: json['event_title'] as String,
        clubName: json['club_name'] as String,
        checkedInAt: DateTime.parse(json['checked_in_at'] as String),
      );
}
