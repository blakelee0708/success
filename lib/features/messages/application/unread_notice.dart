import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/family_message.dart';
import 'message_controller.dart';

/// The newest thing the family said that the parent has not opened yet.
///
/// `readAt` is set on a guardian's message when the parent opens the
/// conversation, so a null one is genuinely unread. Messages the parent sent
/// are never counted - this is about what is waiting *for* them.
final unreadFromFamilyProvider = Provider<FamilyMessage?>((ref) {
  final all = ref.watch(conversationProvider).value ?? const <FamilyMessage>[];
  final dismissed = ref.watch(dismissedNoticeProvider);
  for (final message in all.reversed) {
    if (message.isFromSenior || message.isRead) continue;
    if ((message.body?.trim().isEmpty ?? true) && message.imageUrl == null) {
      continue;
    }
    return message.id == dismissed ? null : message;
  }
  return null;
});

/// The one message 나중에 was pressed on, for this run of the app only.
///
/// **Pressing 나중에 must not mark anything read.** The guardian's 읽음 확인
/// says 어머니가 두 시에 읽으셨다, and a card the parent pushed aside without
/// looking at is not that. So the dismissal is held in memory, the card comes
/// back next time the launcher starts, and the server is never told.
///
/// It stores the message id rather than a flag, so the next message from the
/// family raises the card again instead of inheriting the last dismissal.
class DismissedNotice extends Notifier<String?> {
  @override
  String? build() => null;

  void dismiss(String messageId) => state = messageId;
}

final dismissedNoticeProvider =
    NotifierProvider<DismissedNotice, String?>(DismissedNotice.new);

/// How many things the parent said that the guardian has not opened yet.
///
/// The mirror of [unreadFromFamilyProvider], and it is drawn differently on
/// purpose. The senior gets a card over their launcher because they do not go
/// looking and that launcher *is* their phone. The guardian is an adult with
/// an ordinary phone on which this is one app among many, so a card that can
/// only appear once they have already opened it would be both late and
/// redundant. What reaches them when it matters is an ordinary push
/// notification, which does not exist yet; until it does, a count on the tab
/// is what the app can honestly offer.
///
/// This is the opposite of the rule FCM follows for the senior, and for the
/// same reason: a status-bar entry is the one place a senior who cannot find
/// their contacts app will not look, and it is the first place their child
/// will.
final unreadFromSeniorProvider = Provider<int>((ref) {
  final all = ref.watch(conversationProvider).value ?? const <FamilyMessage>[];
  return all.where((m) => m.isFromSenior && !m.isRead).length;
});
