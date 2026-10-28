import 'dart:typed_data';

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
  Future<FamilyMessage> send(
    String seniorProfileId, {
    String? body,
    String? imagePath,
  });

  /// Puts a photo in the family's folder and returns the path it went to.
  ///
  /// The path, not a URL. The bucket is private, so what is stored on the
  /// message row has to be something that can be turned into a fresh signed
  /// link each time somebody looks - a URL saved today would be a dead link
  /// by the time the parent scrolls back to it.
  Future<String> uploadImage(
    String seniorProfileId,
    Uint8List bytes, {
    required String contentType,
  });

  /// A link to [imagePath] that works for a while, or null if it cannot be
  /// made. Null is *we could not fetch it*, never *there is no photo*.
  Future<String?> imageUrl(String imagePath);

  Future<MessageQuota> quota(String seniorProfileId);

  /// Marks everything the *other* side sent as read.
  ///
  /// Takes no message ids on purpose: the caller marks the conversation, not
  /// a message, so nothing can claim a read on something it never showed.
  /// Fails quietly — a receipt that did not land is not worth an error on
  /// either person's screen.
  Future<void> markRead(String seniorProfileId);

  /// Asks the server to put this message on the family's phones as a
  /// notification.
  ///
  /// **Only for a message the senior sent.** The server refuses any other
  /// caller, and the app does not try: a guardian's own message is already on
  /// their parent's screen the moment they pick the phone up, and buzzing a
  /// sibling about what you just typed is noise.
  ///
  /// Takes an id and never the text, so nothing can push a line the
  /// conversation does not contain. Fails quietly for the same reason
  /// [markRead] does, and a stronger one: the message is already sent, and a
  /// senior shown a failure for something that did not fail would send it
  /// again.
  Future<void> notifyFamily(String messageId);
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

  /// The private bucket the photos live in. Its policies read the senior's
  /// profile id out of the first path segment, so the layout is not cosmetic.
  static const bucket = 'message-images';

  @override
  Future<String> uploadImage(
    String seniorProfileId,
    Uint8List bytes, {
    required String contentType,
  }) async {
    final ext = switch (contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/heic' => 'heic',
      _ => 'jpg',
    };
    final path =
        '$seniorProfileId/${DateTime.now().microsecondsSinceEpoch}.$ext';
    try {
      await _client.storage
          .from(bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: sb.FileOptions(contentType: contentType),
          );
      return path;
    } on sb.StorageException catch (e) {
      throw SeniorLinkException(e.message);
    }
  }

  @override
  Future<String?> imageUrl(String imagePath) async {
    try {
      // An hour is long enough to read a conversation and short enough that
      // a link copied out of the app stops working the same afternoon.
      return await _client.storage
          .from(bucket)
          .createSignedUrl(imagePath, 3600);
    } on sb.StorageException {
      return null;
    }
  }

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
  Future<FamilyMessage> send(
    String seniorProfileId, {
    String? body,
    String? imagePath,
  }) async {
    try {
      final row = await _client.rpc(
        'send_family_message',
        params: {
          'p_senior_profile_id': seniorProfileId,
          'p_body': body,
          'p_image_url': imagePath,
        },
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
  Future<void> notifyFamily(String messageId) async {
    try {
      await _client.functions.invoke(
        'notify-message',
        body: {'message_id': messageId},
      );
    } on Object {
      // The message is in the conversation either way, and the guardian's
      // tab carries the count. What is lost is the buzz.
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
  Future<FamilyMessage> send(
    String seniorProfileId, {
    String? body,
    String? imagePath,
  }) async {
    final text = body?.trim() ?? '';
    if (text.isEmpty && imagePath == null) {
      throw const SeniorLinkException('보낼 내용이 없어요.');
    }
    if (!sendingAsSenior) {
      final current = await quota(seniorProfileId);
      // A photo is counted against the image allowance, not the text one -
      // the server counts them in separate columns and so does this.
      final allowed = imagePath != null
          ? current.canSendImage
          : current.canSendText;
      if (!allowed) {
        throw const MessageQuotaExceeded(
          '이번 달 무료 메시지를 다 쓰셨어요. 안심 케어를 시작하시면 제한 없이 보낼 수 있어요.',
        );
      }
    }
    _seq++;
    final message = FamilyMessage(
      id: 'message-$_seq',
      sentAt: DateTime(2026, 8, 1).add(Duration(minutes: _seq)),
      body: text.isEmpty ? null : text,
      imageUrl: imagePath,
      senderGuardianId: sendingAsSenior ? null : sendingGuardianId,
      senderDeviceId: sendingAsSenior ? 'device-1' : null,
    );
    (byProfile[seniorProfileId] ??= []).add(message);
    return message;
  }

  /// Photos the fake was handed, newest last. The bytes are not kept - what
  /// the tests care about is that one went up and what path came back.
  final uploaded = <String>[];

  @override
  Future<String> uploadImage(
    String seniorProfileId,
    Uint8List bytes, {
    required String contentType,
  }) async {
    final path = '$seniorProfileId/${uploaded.length + 1}.jpg';
    uploaded.add(path);
    return path;
  }

  @override
  Future<String?> imageUrl(String imagePath) async =>
      'https://example.test/$imagePath';

  /// Which guardian this fake is sending as.
  ///
  /// It was hard-coded to `account-1`, which meant the twin could not express
  /// a family with two children writing into one thread - the exact case that
  /// left the parent unable to tell 영희 from 철수, because every test that
  /// could have caught it had only one possible sender.
  String sendingGuardianId = 'account-1';

  /// Which side this fake is reading as — the mirror of [sendingAsSenior].
  bool readingAsSenior = false;

  /// Message ids the family was told about, in order.
  final notified = <String>[];

  @override
  Future<void> notifyFamily(String messageId) async => notified.add(messageId);

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
      textLimit: 30,
      imageUsed: sent.where((m) => m.imageUrl != null).length,
      imageLimit: 5,
    );
  }
}
