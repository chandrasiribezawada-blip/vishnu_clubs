enum JoinRequestStatus { pending, approved, rejected }

extension JoinRequestStatusLabel on JoinRequestStatus {
  String get label {
    switch (this) {
      case JoinRequestStatus.pending:
        return 'Pending';
      case JoinRequestStatus.approved:
        return 'Approved';
      case JoinRequestStatus.rejected:
        return 'Rejected';
    }
  }
}

class JoinRequest {
  final int id;
  final int clubId;
  final String clubName;
  final String reason;
  final String skills;
  final String? experience;
  final String? studentName;
  final String? studentEmail;
  final JoinRequestStatus status;
  final DateTime createdAt;
  final DateTime? decidedAt;

  const JoinRequest({
    required this.id,
    required this.clubId,
    required this.clubName,
    required this.reason,
    required this.skills,
    this.experience,
    this.studentName,
    this.studentEmail,
    required this.status,
    required this.createdAt,
    this.decidedAt,
  });

  factory JoinRequest.fromJson(Map<String, dynamic> json) => JoinRequest(
    id: (json['id'] as num).toInt(),
    clubId: (json['club_id'] as num).toInt(),
    clubName: json['club_name'] as String,
    reason: json['reason'] as String,
    skills: json['skills'] as String,
    experience: json['experience'] as String?,
    studentName: json['student_name'] as String?,
    studentEmail: json['student_email'] as String?,
    status: JoinRequestStatus.values.firstWhere(
      (value) => value.name.toUpperCase() == json['status'],
    ),
    createdAt: DateTime.parse(json['created_at'] as String),
    decidedAt: json['decided_at'] == null
        ? null
        : DateTime.parse(json['decided_at'] as String),
  );
}

class ClubMembership {
  final int id;
  final int clubId;
  final String clubName;
  final DateTime createdAt;

  const ClubMembership({
    required this.id,
    required this.clubId,
    required this.clubName,
    required this.createdAt,
  });

  factory ClubMembership.fromJson(Map<String, dynamic> json) => ClubMembership(
    id: (json['id'] as num).toInt(),
    clubId: (json['club_id'] as num).toInt(),
    clubName: json['club_name'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}
