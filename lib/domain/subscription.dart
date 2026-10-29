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
    this.currentPeriodEnd,
  });

  final String id;
  final SubscriptionPlan plan;
  final SubscriptionStatus status;

  /// Null for [SubscriptionPlan.family]: that plan belongs to the guardian's
  /// account rather than to any one parent.
  final String? seniorProfileId;

  final DateTime? refundedAt;

  /// When the paid month runs out.
  ///
  /// It only matters after 해지: 해지하시면 다음 결제가 없고, 남은 기간까지는
  /// 계속 쓰실 수 있습니다, so the tab has to be able to say which day that
  /// is. Null while there is no Billing to supply one, and then the screen
  /// says 남은 기간 without a date rather than inventing one.
  final DateTime? currentPeriodEnd;

  bool get isWaitingOnSenior =>
      status == SubscriptionStatus.pendingSeniorConsent;
  bool get isRefunded => status == SubscriptionStatus.refunded;

  /// 해지했지만 남은 기간이 아직 있다.
  ///
  /// A cancelled row is **not** an inactive one until its month is up, which
  /// is the server's rule too - `care_is_active` accepts it while
  /// `current_period_end` is in the future. A null end is read as still
  /// running: the guardian paid for a month and nothing here knows when it
  /// ends, so stopping early would take away what they bought.
  bool stillRunningAt(DateTime now) =>
      status == SubscriptionStatus.canceled &&
      (currentPeriodEnd == null || currentPeriodEnd!.isAfter(now));

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
      currentPeriodEnd: switch (row['current_period_end']) {
        final String value => DateTime.tryParse(value)?.toLocal(),
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
      other.refundedAt == refundedAt &&
      other.currentPeriodEnd == currentPeriodEnd;

  @override
  int get hashCode => Object.hash(
    id,
    plan,
    status,
    seniorProfileId,
    refundedAt,
    currentPeriodEnd,
  );
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
