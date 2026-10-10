enum EventStatus { draft, published, cancelled, completed }

enum EventRegistrationStatus { registered, cancelled }

class Event {
  final int id;
  final String title;
  final int clubId;
  final String clubName;
  final DateTime startTime;
  final DateTime? endTime;
  final DateTime? registrationOpensAt;
  final DateTime? registrationClosesAt;
  final String venue;
  final String? description;
  final String? category;
  final String? eligibility;
  final String? posterUrl;
  final double? latitude;
  final double? longitude;
  final int capacity;
  final int registrationCount;
  final EventStatus status;
  final EventRegistrationStatus? registrationStatus;
  final bool attended;

  const Event({
    required this.id,
    required this.title,
    required this.clubId,
    required this.clubName,
    required this.startTime,
    this.endTime,
    this.registrationOpensAt,
    this.registrationClosesAt,
    required this.venue,
    this.description,
    this.category,
    this.eligibility,
    this.posterUrl,
    this.latitude,
    this.longitude,
    this.capacity = 0,
    this.registrationCount = 0,
    this.status = EventStatus.published,
    this.registrationStatus,
    this.attended = false,
  });

  factory Event.fromJson(Map<String, dynamic> json) => Event(
    id: (json['id'] as num).toInt(),
    title: json['title'] as String,
    clubId: (json['club_id'] as num).toInt(),
    clubName: json['club_name'] as String,
    startTime: DateTime.parse(json['start_at'] as String),
    endTime: json['end_at'] == null
        ? null
        : DateTime.parse(json['end_at'] as String),
    registrationOpensAt: json['registration_opens_at'] == null
        ? null
        : DateTime.parse(json['registration_opens_at'] as String),
    registrationClosesAt: json['registration_closes_at'] == null
        ? null
        : DateTime.parse(json['registration_closes_at'] as String),
    venue: json['venue'] as String,
    description: json['description'] as String?,
    category: json['category'] as String?,
    eligibility: json['eligibility'] as String?,
    posterUrl: json['poster_url'] as String?,
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    capacity: (json['capacity'] as num?)?.toInt() ?? 0,
    registrationCount: (json['registration_count'] as num?)?.toInt() ?? 0,
    status: EventStatus.values.firstWhere(
      (value) => value.name.toUpperCase() == json['status'],
    ),
    registrationStatus: json['registration_status'] == null
        ? null
        : EventRegistrationStatus.values.firstWhere(
            (value) => value.name.toUpperCase() == json['registration_status'],
          ),
    attended: json['attended'] as bool? ?? false,
  );
}
