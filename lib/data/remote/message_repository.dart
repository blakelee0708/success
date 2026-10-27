import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../domain/family_message.dart';
import 'senior_link_repository.dart';
import 'subscription_repository.dart';

/// 가족 메시지, the same conversation from both ends.
///
/// Who a message is from is decided by the server from the caller's session,
/// not passed in: on the parent's phone it is the device, on the guardian's it
/// is the account, and a sender that can be claimed is a sender that can be
/// faked.
abstract interface class MessageRepository {
  Future<List<FamilyMessage>> conversation(String seniorProfileId);

  /// Throws [MessageQuotaExceeded] when the family's free allowance is spent —
  /// which can only happen to a guardian.
  Future<FamilyMessage> send(String seniorProfileId, {String? body});

  Future<MessageQuota> quota(String seniorProfileId);

  /// Marks everything the *other* side sent as read.
  ///
  /// Takes no message ids on purpose: the caller marks the conversation, not
  /// a message, so nothing can claim a read on something it never showed.
  /// Fails quietly — a receipt that did not land is not worth an error on
  /// either person's screen.
  Future<void> markRead(String seniorProfileId);
}

/// The free allowance is gone for this month.
class MessageQuotaExceeded implements Exception {
  const MessageQuotaExceeded(this.message);

  final String message;

  @override
  String toString() => message;
}

class SupabaseMessageRepository implements MessageRepository {
  SupabaseMessageRepository(this._client);

  final sb.SupabaseClient _client;

  @override
  Future<List<FamilyMessage>> conversation(String seniorProfileId) async {
    try {
      final rows = await _client
          .from('messages')
          .select()
          .eq('senior_profile_id', seniorProfileId)
          .order('created_at')
          .limit(200);
      return [for (final row in rows) ?FamilyMessage.fromRow(row)];
    } on sb.PostgrestException catch (e) {
      throw SeniorLinkException(e.message);
    }
  }

  @override
  Future<FamilyMessage> send(String seniorProfileId, {String? body}) async {
    try {
      final row = await _client.rpc(
        'send_family_message',
        params: {'p_senior_profile_id': seniorProfileId, 'p_body': body},
      );
      final message = row is Map<String, Object?>
          ? FamilyMessage.fromRow(row)
          : null;
      if (message == null) {
        throw const SeniorLinkException('메시지를 보내지 못했어요.');
      }
      return message;
    } on sb.PostgrestException catch (e) {
      if (e.message.contains('quota reached')) {
        throw const MessageQuotaExceeded(
          '이번 달 무료 메시지를 다 쓰셨어요. 안심 케어를 시작하시면 제한 없이 보낼 수 있어요.',
        );
      }
      if (e.message.contains('not allowed to manage')) {
        throw const SeniorLinkException('이 부모님께 메시지를 보낼 권한이 없어요.');
      }
      throw SeniorLinkException(e.message);
    }
  }

  @override
  Future<void> markRead(String seniorProfileId) async {
    try {
      await _client.rpc(
        'mark_conversation_read',
        params: {'p_senior_profile_id': seniorProfileId},
      );
    } on Object {
      // A receipt is a courtesy. Nothing on either screen depends on it.
    }
  }
  @override
  Future<MessageQuota> quota(String seniorProfileId) async {
    final result = await _client.rpc(
      'family_message_quota',
      params: {'p_senior_profile_id': seniorProfileId},
    );
    if (result is Map<String, Object?>) return MessageQuota.fromJson(result);
    return MessageQuota.free;
  }
}

/// Stand-in used when the build carries no Supabase keys, and by tests.
///
/// Enforces the rule the screens are built around: the quota counts guardian
/// messages and never stops the parent replying.
class InMemoryMessageRepository implements MessageRepository {
  InMemoryMessageRepository(this.store, {this.subscriptions});

  final InMemorySeniorLinkRepository store;

  /// When given, 안심 케어 lifts the limit the way it does on the server.
  final InMemorySubscriptionRepository? subscriptions;

  final Map<String, List<FamilyMessage>> byProfile = {};

  /// Which side this fake is sending as. Tests flip it to stand on the
  /// parent's phone.
  bool sendingAsSenior = false;

  int _seq = 0;

  @override
  Future<List<FamilyMessage>> conversation(String seniorProfileId) async =>
      List.unmodifiable(byProfile[seniorProfileId] ?? const []);

  @override
  Future<FamilyMessage> send(String seniorProfileId, {String? body}) async {
    final text = body?.trim() ?? '';
    if (text.isEmpty) {
      throw const SeniorLinkException('보낼 내용이 없어요.');
    }
    if (!sendingAsSenior) {
      final current = await quota(seniorProfileId);
      if (!current.canSendText) {
        throw const MessageQuotaExceeded(
          '이번 달 무료 메시지를 다 쓰셨어요. 안심 케어를 시작하시면 제한 없이 보낼 수 있어요.',
        );
      }
    }
    _seq++;
    final message = FamilyMessage(
      id: 'message-$_seq',
      sentAt: DateTime(2026, 8, 1).add(Duration(minutes: _seq)),
      body: text,
      senderGuardianId: sendingAsSenior ? null : sendingGuardianId,
      senderDeviceId: sendingAsSenior ? 'device-1' : null,
    );
    (byProfile[seniorProfileId] ??= []).add(message);
    return message;
  }

  /// Which guardian this fake is sending as.
  ///
  /// It was hard-coded to `account-1`, which meant the twin could not express
  /// a family with two children writing into one thread - the exact case that
  /// left the parent unable to tell 영희 from 철수, because every test that
  /// could have caught it had only one possible sender.
  String sendingGuardianId = 'account-1';

  /// Which side this fake is reading as — the mirror of [sendingAsSenior].
  bool readingAsSenior = false;

  @override
  Future<void> markRead(String seniorProfileId) async {
    final now = DateTime(2026, 8, 2);
    final list = byProfile[seniorProfileId];
    if (list == null) return;
    for (var i = 0; i < list.length; i++) {
      final m = list[i];
      if (m.readAt != null) continue;
      // The parent marks what guardians sent; a guardian marks what the
      // parent sent. Neither marks their own.
      if (m.isFromSenior == readingAsSenior) continue;
      list[i] = FamilyMessage(
        id: m.id,
        sentAt: m.sentAt,
        body: m.body,
        imageUrl: m.imageUrl,
        senderGuardianId: m.senderGuardianId,
        senderDeviceId: m.senderDeviceId,
        readAt: now,
      );
    }
  }

  @override
  Future<MessageQuota> quota(String seniorProfileId) async {
    final sent = (byProfile[seniorProfileId] ?? const <FamilyMessage>[])
        .where((m) => !m.isFromSenior);
    final unlimited =
        await subscriptions?.careIsActive(seniorProfileId) ?? false;
    return MessageQuota(
      unlimited: unlimited,
      textUsed: sent.where((m) => m.imageUrl == null).length,
      textLimit: 50,
      imageUsed: sent.where((m) => m.imageUrl != null).length,
      imageLimit: 10,
    );
  }
}
