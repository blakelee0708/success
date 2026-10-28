/// One message in the family conversation.
class FamilyMessage {
  const FamilyMessage({
    required this.id,
    required this.sentAt,
    this.body,
    this.imageUrl,
    this.senderGuardianId,
    this.senderDeviceId,
    this.readAt,
  });

  final String id;
  final DateTime sentAt;
  final String? body;
  final String? imageUrl;

  /// Exactly one of these is set. Which one is what makes the message theirs,
  /// and it is decided by the server rather than claimed by the sender.
  final String? senderGuardianId;
  final String? senderDeviceId;

  /// When the other side opened the conversation after this arrived, or null.
  ///
  /// Shown to the guardian on their own messages and **never to the parent**.
  /// A senior watching an unread mark on a message to a busy adult child is
  /// the unkindest thing this app could put on a screen, and nobody asked
  /// for it.
  final DateTime? readAt;

  /// True when the parent wrote it.
  bool get isFromSenior => senderDeviceId != null;

  bool get isRead => readAt != null;

  static FamilyMessage? fromRow(Map<String, Object?> row) {
    final id = row['id'];
    final sentAt = row['created_at'];
    if (id is! String || sentAt is! String) return null;
    final parsed = DateTime.tryParse(sentAt);
    if (parsed == null) return null;
    return FamilyMessage(
      id: id,
      sentAt: parsed,
      body: row['body'] as String?,
      imageUrl: row['image_url'] as String?,
      senderGuardianId: row['sender_guardian_id'] as String?,
      senderDeviceId: row['sender_device_id'] as String?,
      readAt: switch (row['read_at']) {
        final String value => DateTime.tryParse(value),
        _ => null,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FamilyMessage &&
      other.id == id &&
      other.sentAt == sentAt &&
      other.body == body &&
      other.imageUrl == imageUrl &&
      other.senderGuardianId == senderGuardianId &&
      other.senderDeviceId == senderDeviceId &&
      other.readAt == readAt;

  @override
  int get hashCode => Object.hash(
    id,
    sentAt,
    body,
    imageUrl,
    senderGuardianId,
    senderDeviceId,
    readAt,
  );
}

/// What is left of this month's free allowance.
///
/// The PRD prices it at 월 30회 / 사진 5장, unlimited with 안심 케어. It
/// counts only what guardians send: a senior replying to their child is never
/// rationed, and the allowance exists to price the guardian's use.
class MessageQuota {
  const MessageQuota({
    required this.unlimited,
    required this.textUsed,
    required this.textLimit,
    required this.imageUsed,
    required this.imageLimit,
  });

  static const free = MessageQuota(
    unlimited: false,
    textUsed: 0,
    textLimit: 30,
    imageUsed: 0,
    imageLimit: 5,
  );

  final bool unlimited;
  final int textUsed;
  final int textLimit;
  final int imageUsed;
  final int imageLimit;

  int get textLeft => (textLimit - textUsed).clamp(0, textLimit);
  bool get canSendText => unlimited || textLeft > 0;

  /// Photos have their own allowance - 월 30회 / 사진 5장 in the PRD - and
  /// the server counts them in a separate column. Running out of one does not
  /// stop the other, which is the whole reason they are counted apart.
  int get imageLeft => (imageLimit - imageUsed).clamp(0, imageLimit);
  bool get canSendImage => unlimited || imageLeft > 0;

  /// Shown before the guardian runs out rather than after: a message they
  /// cannot send is worse than a number they saw coming.
  bool get isRunningLow => !unlimited && textLeft <= 5;

  static MessageQuota fromJson(Map<String, Object?> json) => MessageQuota(
    unlimited: json['unlimited'] == true,
    textUsed: _int(json['text_used']),
    textLimit: _int(json['text_limit'], fallback: 30),
    imageUsed: _int(json['image_used']),
    imageLimit: _int(json['image_limit'], fallback: 5),
  );

  static int _int(Object? value, {int fallback = 0}) =>
      value is int ? value : (value is num ? value.toInt() : fallback);

  @override
  bool operator ==(Object other) =>
      other is MessageQuota &&
      other.unlimited == unlimited &&
      other.textUsed == textUsed &&
      other.textLimit == textLimit &&
      other.imageUsed == imageUsed &&
      other.imageLimit == imageLimit;

  @override
  int get hashCode =>
      Object.hash(unlimited, textUsed, textLimit, imageUsed, imageLimit);
}
