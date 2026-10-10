enum AppRole {
  student,
  coordinator,
  admin;

  static AppRole fromApi(String value) => switch (value) {
        'STUDENT' => AppRole.student,
        'CLUB_MEMBER_COORDINATOR' => AppRole.coordinator,
        'CLUB_ADMIN' => AppRole.admin,
        _ => throw FormatException('Unknown account role: $value'),
      };
}

class AppUser {
  final String id;
  final String email;
  final String fullName;
  final AppRole role;

  const AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        email: json['email'] as String,
        fullName: json['full_name'] as String,
        role: AppRole.fromApi(json['role'] as String),
      );
}
