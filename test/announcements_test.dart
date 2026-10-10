import 'package:clubs/features/announcements/data/announcements_repository.dart';
import 'package:clubs/features/announcements/presentation/announcements_screen.dart';
import 'package:clubs/features/announcements/providers/announcements_providers.dart';
import 'package:clubs/models/announcement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _AnnouncementsFake implements AnnouncementsRepository {
  final List<Announcement> items = [
    const Announcement(
      id: 5,
      clubId: 8,
      clubName: 'Verified Club',
      title: 'Workshop update',
      body: 'Registration is open.',
      status: AnnouncementStatus.published,
      publishedAt: null,
      expiresAt: null,
    ),
  ];

  @override
  Future<List<Announcement>> getRelevant() async => items;

  @override
  Future<List<Announcement>> getClub(int clubId) async => items;

  @override
  Future<List<Announcement>> getManaged(int clubId) async => items;

  @override
  Future<List<Announcement>> getAdmin() async => items;

  @override
  Future<Announcement> createClub(int clubId, Map<String, Object?> details) =>
      throw UnimplementedError();

  @override
  Future<Announcement> createPlatform(Map<String, Object?> details) =>
      throw UnimplementedError();

  @override
  Future<Announcement> publish(int id) => throw UnimplementedError();

  @override
  Future<Announcement> cancel(int id) => throw UnimplementedError();
}

void main() {
  testWidgets('student sees real announcements in a published state', (
    tester,
  ) async {
    final repository = _AnnouncementsFake();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          announcementsRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: Scaffold(body: AnnouncementsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Workshop update'), findsOneWidget);
    expect(find.text('Registration is open.'), findsOneWidget);
    expect(find.text('No new announcements'), findsNothing);
  });

  testWidgets('student sees an empty state when no announcements exist', (
    tester,
  ) async {
    final repository = _AnnouncementsFake()..items.clear();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          announcementsRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: Scaffold(body: AnnouncementsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No new announcements'), findsOneWidget);
  });
}
