class AppNotification {
  final int id;
  final String title;
  final String message;
  final DateTime createdAt;
  final DateTime? readAt;
  final String? targetPath;

  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    this.readAt,
    this.targetPath,
  });

  bool get isRead => readAt != null;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: (json['id'] as num).toInt(),
        title: json['title'] as String,
        message: json['message'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        readAt: json['read_at'] == null
            ? null
            : DateTime.parse(json['read_at'] as String),
        targetPath: json['target_path'] as String?,
      );
}
