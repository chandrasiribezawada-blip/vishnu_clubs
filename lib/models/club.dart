class Club {
  final int id;
  final String name;
  final String? category;
  final String? description; // null until coordinator/admin fills it in
  final String? objectives;
  final String? facultyCoordinator;
  final String? contactEmail;
  final String? logoUrl;
  final int memberCount;
  final int followerCount;

  const Club({
    required this.id,
    required this.name,
    required this.category,
    this.description,
    this.objectives,
    this.facultyCoordinator,
    this.contactEmail,
    this.logoUrl,
    this.memberCount = 0,
    this.followerCount = 0,
  });

  /// Two-letter initials used for the avatar, e.g. "A A A Club" -> "AA"
  String get initials {
    final words = name
        .split(RegExp(r'[\s\-]+'))
        .where((w) => w.isNotEmpty && RegExp(r'[A-Za-z]').hasMatch(w[0]))
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final w = words.first;
      return w.substring(0, w.length > 1 ? 2 : 1).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  // Ready for the backend later
  factory Club.fromJson(Map<String, dynamic> json) => Club(
        id: json['id'] as int,
        name: json['name'] as String,
        category: json['category'] as String?,
        description: json['description'] as String?,
        objectives: json['objectives'] as String?,
        facultyCoordinator: json['faculty_coordinator'] as String?,
        contactEmail: json['contact_email'] as String?,
        logoUrl: json['logo_url'] as String?,
        memberCount: (json['member_count'] ?? 0) as int,
        followerCount: (json['follower_count'] ?? 0) as int,
      );
}