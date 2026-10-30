import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../domain/senior_profile.dart';
import '../../domain/subscription.dart';
import 'senior_link_repository.dart';

/// Buying 안심 케어 and the family plan, and the senior's answer.
///
/// Nothing here takes money. Google Play Billing is native, needs a store
/// listing, and cannot be built or verified from this environment — so
/// [startCare] is the seam where a verified purchase token will be checked, and
/// everything downstream of it is real.
abstract interface class SubscriptionRepository {
  /// Everything this guardian has bought.
  Future<List<Subscription>> forGuardian();

  /// Step 1 of the paid flow. Comes back
  /// [SubscriptionStatus.pendingSeniorConsent] — paying does not switch
  /// anything on.
  Future<Subscription> startCare(String seniorProfileId);

  /// 해지하기. The link, the messages and the parent's phone are untouched.
  ///
  /// What comes back says how it ended, and the server decides it from use
  /// (`care_refund_due`): a used month is `canceled` and runs to its end, an
  /// unused one is refunded - in full inside seven days of the payment, by
  /// the remaining days after them. Never answered by the parent is always
  /// a full refund.
  Future<Subscription> cancelCare(String seniorProfileId);

  /// Steps 3 and 4, and only from the senior's own phone. A refusal refunds.
  Future<SeniorProfile> resolveCareConsent(
    String seniorProfileId,
    bool approve,
  );

  /// True only when 안심 케어 is both paid for and consented to.
  Future<bool> careIsActive(String seniorProfileId);

  Future<List<CareAlert>> alertsFor(String seniorProfileId);
}

class SupabaseSubscriptionRepository implements SubscriptionRepository {
  SupabaseSubscriptionRepository(this._client);

  final sb.SupabaseClient _client;

  @override
  Future<List<Subscription>> forGuardian() async {
    try {
      final rows = await _client
          .from('subscriptions')
          .select()
          .order('created_at', ascending: false);
      return [for (final row in rows) ?Subscription.fromRow(row)];
    } on sb.PostgrestException catch (e) {
      throw SeniorLinkException(e.message);
    }
  }

  @override
  Future<Subscription> startCare(String seniorProfileId) async => _subscription(
    await _rpc('start_care_subscription', {
      'p_senior_profile_id': seniorProfileId,
    }),
  );

  @override
  Future<Subscription> cancelCare(String seniorProfileId) async =>
      _subscription(
        await _rpc('cancel_care_subscription', {
          'p_senior_profile_id': seniorProfileId,
        }),
      );

  @override
  Future<SeniorProfile> resolveCareConsent(
    String seniorProfileId,
    bool approve,
  ) async {
    final row = await _rpc('resolve_care_consent', {
      'p_senior_profile_id': seniorProfileId,
      'p_approve': approve,
    });
    final profile = SeniorProfile.fromRow(row);
    if (profile == null) {
      throw const SeniorLinkException('답을 저장하지 못했어요.');
    }
    return profile;
  }

  @override
  Future<bool> careIsActive(String seniorProfileId) async =>
      await _client.rpc(
        'care_is_active',
        params: {'p_senior_profile_id': seniorProfileId},
      ) ==
      true;

  @override
  Future<List<CareAlert>> alertsFor(String seniorProfileId) async {
    try {
      final rows = await _client
          .from('alerts')
          .select()
          .eq('senior_profile_id', seniorProfileId)
          .order('created_at', ascending: false)
          .limit(20);
      return [for (final row in rows) ?CareAlert.fromRow(row)];
    } on sb.PostgrestException catch (e) {
      throw SeniorLinkException(e.message);
    }
  }

  Future<Map<String, Object?>> _rpc(
    String name,
    Map<String, Object?> params,
  ) async {
    try {
      final result = await _client.rpc(name, params: params);
      if (result is Map<String, Object?>) return result;
      if (result is List && result.isNotEmpty && result.first is Map) {
        return (result.first as Map).cast<String, Object?>();
      }
      return const {};
    } on sb.PostgrestException catch (e) {
      throw SeniorLinkException(_readable(e.message));
    }
  }

  static String _readable(String message) {
    // 가족 플랜 raised the limit until the app went 1대1 on 2026-10-29. The
    // old message is kept for a server that has not been migrated yet;
    // nothing raises it now.
    if (message.contains('family plan required') ||
        message.contains('one senior per guardian')) {
      return '지금은 부모님 한 분만 연결할 수 있어요.';
    }
    if (message.contains('one guardian per senior')) {
      return '부모님 한 분에 자녀 한 명만 연결할 수 있어요.';
    }
    if (message.contains('only the senior device')) {
      return '부모님 폰에서만 답할 수 있어요.';
    }
    if (message.contains('nothing to answer')) {
      return '답할 요청이 없어요.';
    }
    if (message.contains('not allowed to manage')) {
      return '이 부모님을 관리할 권한이 없어요.';
    }
    if (message.contains('duplicate key') ||
        message.contains('unique constraint')) {
      return '이미 신청되어 있어요.';
    }
    return message;
  }

  static Subscription _subscription(Map<String, Object?> row) {
    final subscription = Subscription.fromRow(row);
    if (subscription == null) {
      throw const SeniorLinkException('결제 상태를 읽지 못했어요.');
    }
    return subscription;
  }
}

/// Stand-in used when the build carries no Supabase keys, and by tests.
///
/// Enforces the three rules the screens depend on: paying does not activate,
/// only the senior's phone answers, and a refusal refunds and leaves the free
/// features alone.
class InMemorySubscriptionRepository implements SubscriptionRepository {
  InMemorySubscriptionRepository(this.store);

  final InMemorySeniorLinkRepository store;

  final List<Subscription> subscriptions = [];
  final Map<String, List<CareAlert>> alerts = {};

  /// Which guardian this fake is acting as, so a sibling can be stood in for.
  String actingGuardianId = 'account-1';

  /// What the twin calls now, for the month an approval starts.
  DateTime Function() now = DateTime.now;

  /// When each subscription was paid for, which starts the seven days.
  final Map<String, DateTime> paidAt = {};

  /// Subscriptions the guardian used on a day before today. The server
  /// counts days; the twin only needs the answer, so a test says it.
  final Set<String> used = {};

  int _seq = 0;

  @override
  Future<List<Subscription>> forGuardian() async =>
      List.unmodifiable(subscriptions);

  @override
  Future<Subscription> startCare(String seniorProfileId) async {
    if (subscriptions.any(
      (s) =>
          s.seniorProfileId == seniorProfileId &&
          s.plan == SubscriptionPlan.care &&
          (s.status == SubscriptionStatus.active || s.isWaitingOnSenior),
    )) {
      throw const SeniorLinkException('이미 신청되어 있어요.');
    }
    // Paying does not switch anything on.
    final subscription = _add(
      SubscriptionPlan.care,
      SubscriptionStatus.pendingSeniorConsent,
      seniorProfileId,
    );
    store.setConsent(seniorProfileId, PaidConsentStatus.pending);
    return subscription;
  }

  @override
  Future<Subscription> cancelCare(String seniorProfileId) async {
    final index = subscriptions.indexWhere(
      (s) =>
          s.seniorProfileId == seniorProfileId &&
          s.plan == SubscriptionPlan.care &&
          (s.status == SubscriptionStatus.active || s.isWaitingOnSenior),
    );
    if (index < 0) throw const SeniorLinkException('해지할 것이 없어요.');
    final live = subscriptions[index];
    // The server's `care_refund_due`. An unanswered question is withdrawn
    // rather than left on the parent's home screen; a used month keeps its
    // remaining days and gives nothing back.
    final paid = paidAt[live.id] ?? now();
    final RefundKind? refund = live.isWaitingOnSenior
        ? RefundKind.full
        : used.contains(live.id)
        ? null
        : now().difference(paid) < const Duration(days: 7)
        ? RefundKind.full
        : RefundKind.remaining;
    subscriptions[index] = Subscription(
      id: live.id,
      plan: live.plan,
      status: refund == null
          ? SubscriptionStatus.canceled
          : SubscriptionStatus.refunded,
      seniorProfileId: seniorProfileId,
      refundedAt: refund == null ? null : now(),
      refundKind: refund,
      currentPeriodEnd: live.currentPeriodEnd,
    );
    if (live.isWaitingOnSenior) {
      store.setConsent(seniorProfileId, PaidConsentStatus.none);
    }
    return subscriptions[index];
  }

  @override
  Future<SeniorProfile> resolveCareConsent(
    String seniorProfileId,
    bool approve,
  ) async {
    if (store.activeDeviceByProfile[seniorProfileId]?.installId !=
        store.seniorInstallId) {
      throw const SeniorLinkException('부모님 폰에서만 답할 수 있어요.');
    }
    final index = subscriptions.indexWhere(
      (s) => s.seniorProfileId == seniorProfileId && s.isWaitingOnSenior,
    );
    if (index < 0) {
      // The second question: a used month, cut and reconnected inside it.
      // The month keeps its row either way, and a 거절 refunds nothing.
      final askedAgain =
          store.profiles[seniorProfileId]?.paidConsentStatus ==
              PaidConsentStatus.pending &&
          subscriptions.any(
            (s) =>
                s.seniorProfileId == seniorProfileId && s.stillRunningAt(now()),
          );
      if (!askedAgain) throw const SeniorLinkException('답할 요청이 없어요.');
      store.setConsent(
        seniorProfileId,
        approve ? PaidConsentStatus.granted : PaidConsentStatus.refused,
      );
      _seq++;
      (alerts[seniorProfileId] ??= []).insert(
        0,
        CareAlert(
          id: 'alert-$_seq',
          type: approve ? 'care_consent_granted' : 'care_consent_refused',
          title: approve ? '안심 케어를 다시 허락하셨어요' : '안심 케어를 원하지 않으셨어요',
          body: approve
              ? '남은 기간 동안 다시 보실 수 있어요.'
              : '이미 사용하신 기간이라 환불은 없습니다. 무료 기능은 그대로 쓰실 수 있어요.',
        ),
      );
      return store.fetchProfile(seniorProfileId);
    }

    final pending = subscriptions[index];
    subscriptions[index] = Subscription(
      id: pending.id,
      plan: pending.plan,
      status: approve ? SubscriptionStatus.active : SubscriptionStatus.refunded,
      seniorProfileId: seniorProfileId,
      refundedAt: approve ? null : DateTime(2026, 7, 31),
      refundKind: approve ? null : RefundKind.full,
      // The server starts the month on approval (`one_month_after`). Left
      // null here, a cancelled row read as running forever on the screen
      // while the server had already stopped it.
      currentPeriodEnd: approve ? now().add(const Duration(days: 30)) : null,
    );
    store.setConsent(
      seniorProfileId,
      approve ? PaidConsentStatus.granted : PaidConsentStatus.refused,
    );

    _seq++;
    (alerts[seniorProfileId] ??= []).insert(
      0,
      CareAlert(
        id: 'alert-$_seq',
        type: approve ? 'care_consent_granted' : 'care_consent_refused',
        title: approve ? '안심 케어를 허락하셨어요' : '안심 케어를 원하지 않으셨어요',
        body: approve
            ? '이제 부모님이 어떻게 지내시는지 보실 수 있어요.'
            : '결제는 환불 처리되었습니다. 무료 기능은 그대로 쓰실 수 있어요.',
      ),
    );
    return store.fetchProfile(seniorProfileId);
  }

  @override
  Future<bool> careIsActive(String seniorProfileId) async {
    final profile = store.profiles[seniorProfileId];
    if (profile == null) return false;
    return subscriptions.any(
          // The server's `care_is_active`: a cancelled month is on until
          // it runs out.
          (s) =>
              s.seniorProfileId == seniorProfileId &&
              s.plan == SubscriptionPlan.care &&
              (s.status == SubscriptionStatus.active ||
                  s.stillRunningAt(now())),
        ) &&
        profile.paidConsentStatus == PaidConsentStatus.granted;
  }

  @override
  Future<List<CareAlert>> alertsFor(String seniorProfileId) async =>
      List.unmodifiable(alerts[seniorProfileId] ?? const []);

  Subscription _add(
    SubscriptionPlan plan,
    SubscriptionStatus status,
    String? seniorProfileId,
  ) {
    _seq++;
    final subscription = Subscription(
      id: 'sub-$_seq',
      plan: plan,
      status: status,
      seniorProfileId: seniorProfileId,
    );
    subscriptions.add(subscription);
    paidAt[subscription.id] = now();
    return subscription;
  }
}
