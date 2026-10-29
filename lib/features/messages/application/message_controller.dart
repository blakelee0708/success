import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../data/senior_link_store.dart';
import '../../../domain/family_message.dart';
import '../../guardian/application/guardian_home_apps_controller.dart';
import '../../guardian/application/guardian_pairing_controller.dart';
import '../../guardian/application/guardian_session_controller.dart';

/// Which conversation a screen is showing.
///
/// On the guardian's phone it follows the selected parent; on the parent's own
/// phone it is whichever profile this install belongs to. One provider for both
/// so the conversation widget does not have to know which phone it is on.
final conversationProfileIdProvider = FutureProvider<String?>((ref) async {
  final selected = ref.watch(selectedSeniorProfileProvider);
  if (selected != null) return selected.id;
  final link = await ref.watch(seniorLinkStoreProvider).load();
  return link.seniorProfileId;
});

/// The thread, oldest first.
///
/// A notifier rather than a plain future because **the message that was just
/// sent is already in hand.** `send_family_message` returns the row it wrote,
/// and the screen used to throw it away and re-read all two hundred rows to
/// find it again - so pressing 보내기 cost a second round trip before
/// anything appeared, on top of the one that did the sending.
class ConversationNotifier extends AsyncNotifier<List<FamilyMessage>> {
  @override
  Future<List<FamilyMessage>> build() async {
    final profileId = await ref.watch(conversationProfileIdProvider.future);
    if (profileId == null) return const [];
    try {
      return await ref.watch(messageRepositoryProvider).conversation(profileId);
    } on Object {
      // A conversation that cannot be loaded shows as empty rather than as an
      // error on the senior's launcher, which has to keep working with no
      // signal.
      return const [];
    }
  }

  /// Puts a message the server has **already accepted** on screen at once.
  ///
  /// Not an optimistic bubble: nothing is drawn until the server has written
  /// the row and handed it back, so there is no state where the screen shows
  /// a message that does not exist. What it removes is only the wait for a
  /// second read of what we were just told.
  ///
  /// Guarded on the id, because the refresh that follows carries the same row
  /// and a conversation that shows a message twice is worse than a slow one.
  void append(FamilyMessage sent) {
    final now = state.value;
    if (now == null) return;
    if (now.any((m) => m.id == sent.id)) return;
    state = AsyncData([...now, sent]);
  }
}

final conversationProvider =
    AsyncNotifierProvider<ConversationNotifier, List<FamilyMessage>>(
      ConversationNotifier.new,
    );

final messageQuotaProvider = FutureProvider<MessageQuota>((ref) async {
  final profileId = await ref.watch(conversationProfileIdProvider.future);
  if (profileId == null) return MessageQuota.free;
  try {
    return await ref.watch(messageRepositoryProvider).quota(profileId);
  } on Object {
    return MessageQuota.free;
  }
});

class MessageController extends Notifier<void> {
  @override
  void build() {}

  /// Sends, then refreshes both the conversation and the allowance. The
  /// allowance has to be re-read rather than decremented locally: the family
  /// shares one, and a sibling may have spent some of it since this screen
  /// opened.
  Future<void> send(String body) async {
    final profileId = await ref.read(conversationProfileIdProvider.future);
    if (profileId == null) return;
    final FamilyMessage sent;
    try {
      sent = await ref
          .read(messageRepositoryProvider)
          .send(profileId, body: body);
    } on Object {
      _recheckLinks();
      rethrow;
    }
    ref.read(conversationProvider.notifier).append(sent);
    // Neither of these is on the path to the bubble. The push is a round trip
    // to an Edge Function, and the allowance is a third call - awaited, they
    // were what 보내기 actually waited on.
    unawaited(_notify(sent));
    ref.invalidate(messageQuotaProvider);
  }

  /// Uploads the photo, then sends a message pointing at it.
  ///
  /// Two steps and not one, because the file and the row live in different
  /// places. If the upload works and the send fails, an orphan sits in the
  /// bucket and nobody is told about a photo that was never announced - which
  /// is the harmless way round. The other order would put a message on the
  /// parent's screen pointing at a file that is not there.
  Future<void> sendPhoto(Uint8List bytes, {required String contentType}) async {
    final profileId = await ref.read(conversationProfileIdProvider.future);
    if (profileId == null) return;
    final repo = ref.read(messageRepositoryProvider);
    final FamilyMessage sent;
    try {
      final path = await repo.uploadImage(
        profileId,
        bytes,
        contentType: contentType,
      );
      sent = await repo.send(profileId, imagePath: path);
    } on Object {
      _recheckLinks();
      rethrow;
    }
    ref.read(conversationProvider.notifier).append(sent);
    unawaited(_notify(sent));
    ref.invalidate(messageQuotaProvider);
  }

  /// A refused send is the likeliest moment to learn the parent cut the link.
  ///
  /// The tick re-reads within fifteen seconds anyway, but somebody who has
  /// just been refused is looking at the screen right now, and the notice
  /// that explains why should not wait for a timer. Each of the three is
  /// empty without a guardian session, so on the parent's phone this asks
  /// nothing.
  void _recheckLinks() {
    ref.invalidate(linkedSeniorProfilesProvider);
    ref.invalidate(pendingSeniorLinksProvider);
    ref.invalidate(guardianNoticesProvider);
  }

  /// Puts the parent's message on their children's phones.
  ///
  /// Decided from the row that came back rather than from which half of the
  /// app is running: `isFromSenior` is the server's own answer to who sent
  /// it, and it is the same question the gate asks. A guardian's send falls
  /// through here untouched, so their phone never makes a call the server
  /// would refuse.
  ///
  /// The repository swallows its own failures, which is what makes it safe to
  /// let go of: nothing on screen waits for the buzz, and a message that was
  /// written is in the conversation whether or not the other phone rang.
  Future<void> _notify(FamilyMessage sent) async {
    if (!sent.isFromSenior) return;
    await ref.read(messageRepositoryProvider).notifyFamily(sent.id);
  }

  /// Marks what the other side sent as read, because this screen is open.
  ///
  /// Not awaited by anything drawn, and the repository swallows its own
  /// failures: a receipt is a courtesy and must not hold up a conversation.
  /// The conversation is **not** invalidated afterwards — the reader has no
  /// use for their own receipt, and refreshing the list under them would
  /// scroll the message they are in the middle of reading.
  Future<void> markRead() async {
    final profileId = await ref.read(conversationProfileIdProvider.future);
    if (profileId == null) return;
    await ref.read(messageRepositoryProvider).markRead(profileId);
  }
}

final messageControllerProvider = NotifierProvider<MessageController, void>(
  MessageController.new,
);

/// A link that will load [path] for a while.
///
/// Per path rather than per conversation, so scrolling back through a year of
/// photos does not mint a hundred links for the ones nobody is looking at.
final messageImageProvider = FutureProvider.family<String?, String>(
  (ref, path) => ref.watch(messageRepositoryProvider).imageUrl(path),
);
