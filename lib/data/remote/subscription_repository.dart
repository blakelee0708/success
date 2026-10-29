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

  /// Whether this guardian may take on another parent.
  Future<bool> hasFamilyPlan();

  Future<Subscription> startFamilyPlan();

  /// Step 1 of the paid flow. Comes back
  /// [SubscriptionStatus.pendingSeniorConsent] — paying does not switch
  /// anything on.
  Future<Subscription> startCare(String seniorProfileId);

  /// 해지하기, which is **not** 연결 끊기 and differs in exactly one way:
  /// the days already paid for are kept, so nothing is refunded. The link,
  /// the messages and the parent's phone are untouched.
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
  Future<bool> hasFamilyPlan() async =>
      await _client.rpc('has_family_plan') == true;

  @override
  Future<Subscription> startFamilyPlan() async =>
      _subscription(await _rpc('start_family_plan', const {}));

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

  int _seq = 0;

  @override
  Future<List<Subscription>> forGuardian() async =>
      List.unmodifiable(subscriptions);

  @override
  Future<bool> hasFamilyPlan() async => subscriptions.any(
    (s) =>
        s.plan == SubscriptionPlan.family &&
        s.status == SubscriptionStatus.active,
  );

  @override
  Future<Subscription> startFamilyPlan() async {
    if (await hasFamilyPlan()) {
      throw const SeniorLinkException('이미 신청되어 있어요.');
    }
    // No senior consent: this plan changes how many parents the guardian may
    // manage, and each of those parents still pairs with them separately.
    return _add(SubscriptionPlan.family, SubscriptionStatus.active, null);
  }

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
    // An unanswered question is withdrawn rather than left on the parent's
    // home screen pointing at a family that has changed its mind; one that
    // was answered keeps its remaining days.
    final refunding = live.isWaitingOnSenior;
    subscriptions[index] = Subscription(
      id: live.id,
      plan: live.plan,
      status: refunding
          ? SubscriptionStatus.refunded
          : SubscriptionStatus.canceled,
      seniorProfileId: seniorProfileId,
      refundedAt: refunding ? DateTime(2026, 10, 29) : null,
      currentPeriodEnd: live.currentPeriodEnd,
    );
    if (refunding) store.setConsent(seniorProfileId, PaidConsentStatus.none);
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
    if (index < 0) throw const SeniorLinkException('답할 요청이 없어요.');

    final pending = subscriptions[index];
    subscriptions[index] = Subscription(
      id: pending.id,
      plan: pending.plan,
      status: approve ? SubscriptionStatus.active : SubscriptionStatus.refunded,
      seniorProfileId: seniorProfileId,
      refundedAt: approve ? null : DateTime(2026, 7, 31),
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
            ? '이제 기기 상태와 위치 확인을 켤 수 있어요.'
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
          (s) =>
              s.seniorProfileId == seniorProfileId &&
              s.plan == SubscriptionPlan.care &&
              s.status == SubscriptionStatus.active,
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
    return subscription;
  }
}
