import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/providers/auth_providers.dart';
import '../../../models/announcement.dart';
import '../data/announcements_repository.dart';

final announcementsRepositoryProvider = Provider<AnnouncementsRepository>(
  (ref) => ApiAnnouncementsRepository(ref.watch(apiClientProvider)),
);

final relevantAnnouncementsProvider =
    FutureProvider.autoDispose<List<Announcement>>(
      (ref) => ref.watch(announcementsRepositoryProvider).getRelevant(),
    );

final clubAnnouncementsProvider = FutureProvider.autoDispose
    .family<List<Announcement>, int>(
      (ref, clubId) =>
          ref.watch(announcementsRepositoryProvider).getClub(clubId),
    );

final managedAnnouncementsProvider = FutureProvider.autoDispose
    .family<List<Announcement>, int>(
      (ref, clubId) =>
          ref.watch(announcementsRepositoryProvider).getManaged(clubId),
    );

final adminAnnouncementsProvider =
    FutureProvider.autoDispose<List<Announcement>>(
      (ref) => ref.watch(announcementsRepositoryProvider).getAdmin(),
    );
