import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_version.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../data/remote/announcement_repository.dart';

final announcementDismissalsProvider = Provider<AnnouncementDismissals>(
  (ref) => AnnouncementDismissals(),
);

/// What this phone has closed, read once and then kept in memory so a close
/// takes the card off at once rather than after the next read.
class DismissedNotices extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() => ref.read(announcementDismissalsProvider).ids();

  Future<void> dismiss(String id) async {
    state = AsyncData({...?state.value, id});
    await ref.read(announcementDismissalsProvider).dismiss(id);
  }
}

final dismissedNoticesProvider =
    AsyncNotifierProvider<DismissedNotices, Set<String>>(DismissedNotices.new);

/// The running notices for [audience] this build should see, minus the ones
/// closed here. Re-read on resume by `HomeKeyListener`.
final runningNoticesProvider =
    FutureProvider.family<List<Announcement>, AnnouncementAudience>((
      ref,
      audience,
    ) async {
      final all = await ref
          .watch(announcementRepositoryProvider)
          .running(audience);
      final build = buildNumberOf(appVersion);
      return [
        for (final a in all)
          if (a.showsTo(build)) a,
      ];
    });

/// The senior's one card, or null. One at a time, newest first: a stack of
/// notices on a parent's home screen is a wall, not a notice.
final seniorNoticeProvider = Provider<Announcement?>((ref) {
  final running =
      ref.watch(runningNoticesProvider(AnnouncementAudience.senior)).value ??
      const [];
  final closed = ref.watch(dismissedNoticesProvider).value;
  // Until the closed list has been read, nothing - a card that appears and
  // then vanishes is worse than one that appears a moment late.
  if (closed == null) return null;
  for (final a in running) {
    if (!closed.contains(a.id)) return a;
  }
  return null;
});

/// The guardian's 새 버전이 나왔어요: the newest build on Play when it is
/// newer than this one and not already put off for that build.
class UpdateOffer extends AsyncNotifier<int?> {
  @override
  Future<int?> build() async {
    final latest = (await ref.watch(appConfigProvider.future)).latestBuild;
    final mine = buildNumberOf(appVersion);
    if (latest == null || mine == null || latest <= mine) return null;
    final putOff = await ref
        .read(announcementDismissalsProvider)
        .updateDismissedFor();
    if (putOff != null && putOff >= latest) return null;
    return latest;
  }

  Future<void> later() async {
    final latest = state.value;
    if (latest == null) return;
    state = const AsyncData(null);
    await ref.read(announcementDismissalsProvider).dismissUpdate(latest);
  }
}

final updateOfferProvider = AsyncNotifierProvider<UpdateOffer, int?>(
  UpdateOffer.new,
);
