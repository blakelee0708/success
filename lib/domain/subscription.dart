/// What was bought.
enum SubscriptionPlan {
  /// 안심 케어 — bought for one parent, and inert until that parent agrees.
  care('care');

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

/// How much a refunded row gives back.
///
/// Decided by the server from whether the month was **used** - not from who
/// ended it, because a parent pressing 끊기 at their child's request looks
/// exactly like one pressing it on their own. See [careRefundRule].
enum RefundKind {
  /// 결제 7일 안에 쓰지 않았거나, 부모님이 허락하지 않으셨다.
  full('full'),

  /// 7일이 지났지만 쓰지 않았다. Google computes the amount.
  remaining('remaining');

  const RefundKind(this.wire);

  final String wire;
}

/// 환불 기준, said wherever 안심 케어 can end - 해지, 연결 끊기, 계정 삭제.
///
/// Worded by the owner, 2026-10-30, and the same three lines on all three
/// dialogs. The rule itself is the server's (`care_refund_due`): a day counts
/// as used when the guardian's phone was shown the paid readings, and the day
/// of the cancel never counts. **No amount is said**, because Google computes
/// it and a number written here could disagree with what arrives.
const careRefundRule =
    '$_careRefundBasis\n'
    '사용한 이력이 있으면 환불은 불가하며, 남은 기간까지 그대로 쓰실 수 있어요.';

/// The same rule on 연결 끊기 and 계정 삭제, whose third line stops at the
/// refund. **남은 기간까지 그대로 쓰실 수 있어요 is false there**: a cut
/// link reads nothing until it is reconnected, and a deleted account never
/// does - so on the delete dialog it sat right above 남은 기간은 쓰실 수 없게
/// 돼요, one screen saying both.
const careRefundRuleOnLeaving =
    '$_careRefundBasis\n'
    '사용한 이력이 있으면 환불은 불가합니다.';

const _careRefundBasis =
    '결제하신 지 7일 이내에 사용하지 않으셨다면 전액 환불됩니다.\n'
    '사용하지 않으셨지만 7일이 지났다면 남은 기간만큼 환불됩니다.';

class Subscription {
  const Subscription({
    required this.id,
    required this.plan,
    required this.status,
    this.seniorProfileId,
    this.refundedAt,
    this.refundKind,
    this.currentPeriodEnd,
  });

  final String id;
  final SubscriptionPlan plan;
  final SubscriptionStatus status;

  /// The parent it was bought for.
  final String? seniorProfileId;

  final DateTime? refundedAt;

  /// Null unless refunded.
  final RefundKind? refundKind;

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
  /// `current_period_end` is in the future.
  ///
  /// **A null end is not running**, because the server says so: `null >
  /// now()` is not true, so `care_is_active` stopped the readings the moment
  /// such a row was cancelled. Reading it as running forever left the tab
  /// promising 남은 기간까지는 지금처럼 쓰실 수 있어요 about days that had
  /// already ended.
  bool stillRunningAt(DateTime now) =>
      status == SubscriptionStatus.canceled &&
      currentPeriodEnd != null &&
      currentPeriodEnd!.isAfter(now);

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
      refundKind: _byWire(RefundKind.values, row['refund_kind'], (e) => e.wire),
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
      other.refundKind == refundKind &&
      other.currentPeriodEnd == currentPeriodEnd;

  @override
  int get hashCode => Object.hash(
    id,
    plan,
    status,
    seniorProfileId,
    refundedAt,
    refundKind,
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
