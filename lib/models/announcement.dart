enum AnnouncementStatus { draft, published, cancelled }

class Announcement {
  final int id;
  final int? clubId;
  final String? clubName;
  final String title;
  final String body;
  final AnnouncementStatus status;
  final DateTime? publishedAt;
  final DateTime? expiresAt;

  const Announcement({
    required this.id,
    required this.clubId,
    required this.clubName,
    required this.title,
    required this.body,
    required this.status,
    required this.publishedAt,
    required this.expiresAt,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) => Announcement(
    id: (json['id'] as num).toInt(),
    clubId: (json['club_id'] as num?)?.toInt(),
    clubName: json['club_name'] as String?,
    title: json['title'] as String,
    body: json['body'] as String,
    status: AnnouncementStatus.values.firstWhere(
      (value) => value.name.toUpperCase() == json['status'],
    ),
    publishedAt: json['published_at'] == null
        ? null
        : DateTime.parse(json['published_at'] as String),
    expiresAt: json['expires_at'] == null
        ? null
        : DateTime.parse(json['expires_at'] as String),
  );
}
