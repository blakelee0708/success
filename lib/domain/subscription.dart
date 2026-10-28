/// What was bought.
enum SubscriptionPlan {
  /// 안심 케어 — bought for one parent, and inert until that parent agrees.
  care('care'),

  /// Lets one guardian look after more than one parent.
  family('family');

  const SubscriptionPlan(this.wire);

  final String wire;
}

/// Where a purchase stands.
///
/// [pendingSeniorConsent] is the state that makes the whole flow honest:
/// `06_PERMISSION_AND_POLICY` puts the senior's agreement *after* the payment,
/// so there has to be a state where money has been taken and nothing is on.
enum SubscriptionStatus {
  active('active'),
  pendingSeniorConsent('pending_senior_consent'),
  refunded('refunded'),
  canceled('canceled');

  const SubscriptionStatus(this.wire);

  final String wire;
}

class Subscription {
  const Subscription({
    required this.id,
    required this.plan,
    required this.status,
    this.seniorProfileId,
    this.refundedAt,
  });

  final String id;
  final SubscriptionPlan plan;
  final SubscriptionStatus status;

  /// Null for [SubscriptionPlan.family]: that plan belongs to the guardian's
  /// account rather than to any one parent.
  final String? seniorProfileId;

  final DateTime? refundedAt;

  bool get isWaitingOnSenior =>
      status == SubscriptionStatus.pendingSeniorConsent;
  bool get isRefunded => status == SubscriptionStatus.refunded;

  static Subscription? fromRow(Map<String, Object?> row) {
    final id = row['id'];
    if (id is! String) return null;
    final plan = _byWire(SubscriptionPlan.values, row['plan'], (e) => e.wire);
    final status = _byWire(
      SubscriptionStatus.values,
      row['status'],
      (e) => e.wire,
    );
    if (plan == null || status == null) return null;
    return Subscription(
      id: id,
      plan: plan,
      status: status,
      seniorProfileId: row['senior_profile_id'] as String?,
      refundedAt: switch (row['refunded_at']) {
        final String value => DateTime.tryParse(value),
        _ => null,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Subscription &&
      other.id == id &&
      other.plan == plan &&
      other.status == status &&
      other.seniorProfileId == seniorProfileId &&
      other.refundedAt == refundedAt;

  @override
  int get hashCode =>
      Object.hash(id, plan, status, seniorProfileId, refundedAt);
}

/// Something that happened while the guardian was not looking.
class CareAlert {
  const CareAlert({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.readAt,
  });

  final String id;
  final String type;
  final String title;
  final String? body;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  static CareAlert? fromRow(Map<String, Object?> row) {
    final id = row['id'];
    final type = row['type'];
    final title = row['title'];
    if (id is! String || type is! String || title is! String) return null;
    return CareAlert(
      id: id,
      type: type,
      title: title,
      body: row['body'] as String?,
      readAt: switch (row['read_at']) {
        final String value => DateTime.tryParse(value),
        _ => null,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CareAlert &&
      other.id == id &&
      other.type == type &&
      other.title == title &&
      other.body == body &&
      other.readAt == readAt;

  @override
  int get hashCode => Object.hash(id, type, title, body, readAt);
}

T? _byWire<T extends Enum>(
  List<T> values,
  Object? wire,
  String Function(T) toWire,
) {
  for (final value in values) {
    if (toWire(value) == wire) return value;
  }
  return null;
}
