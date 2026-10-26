import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../data/senior_link_store.dart';
import '../../../domain/family_message.dart';
import '../../guardian/application/guardian_home_apps_controller.dart';

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

final conversationProvider = FutureProvider<List<FamilyMessage>>((ref) async {
  final profileId = await ref.watch(conversationProfileIdProvider.future);
  if (profileId == null) return const [];
  try {
    return await ref.watch(messageRepositoryProvider).conversation(profileId);
  } on Object {
    // A conversation that cannot be loaded shows as empty rather than as an
    // error on the senior's launcher, which has to keep working with no signal.
    return const [];
  }
});

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
    await ref.read(messageRepositoryProvider).send(profileId, body: body);
    ref.invalidate(conversationProvider);
    ref.invalidate(messageQuotaProvider);
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
