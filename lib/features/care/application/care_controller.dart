import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../domain/senior_profile.dart';
import '../../../domain/subscription.dart';
import '../../guardian/application/guardian_home_apps_controller.dart';
import '../../guardian/application/guardian_session_controller.dart';

/// Where 안심 케어 stands for the selected parent.
///
/// [waitingOnSenior] exists because `06_PERMISSION_AND_POLICY` puts the
/// senior's agreement after the payment. Collapsing it into "not active" would
/// hide the one state the guardian most needs explained: they have paid and
/// nothing is on.
///
/// [cancelling] is 해지했지만 아직 쓰고 있다, and leaving it out was a real
/// defect rather than a missing nicety: a cancelled row fell through to
/// [waitingOnSenior], so a guardian who pressed 해지하기 was told
/// 부모님의 허락을 기다리고 있어요 about a parent who had agreed months ago.
///
/// [askedAgain] and [declinedAgain] are a used month whose family was cut and
/// reconnected inside it. Reconnecting is the parent agreeing to the link,
/// not to being looked at, so 안심 케어 is put to them again. Neither is
/// [waitingOnSenior] or [refused]: there is no new payment to cancel, and a
/// second 거절 refunds nothing, because the month was already used.
enum CareStage {
  notBought,
  waitingOnSenior,
  refused,
  active,
  cancelling,
  askedAgain,
  declinedAgain,
}

class CareState {
  const CareState({required this.stage, this.subscription});

  final CareStage stage;
  final Subscription? subscription;
}

final careStateProvider = FutureProvider<CareState>((ref) async {
  final profile = ref.watch(selectedSeniorProfileProvider);
  if (profile == null) return const CareState(stage: CareStage.notBought);

  final subscriptions = await ref
      .watch(subscriptionRepositoryProvider)
      .forGuardian();
  final care = subscriptions
      .where(
        (s) =>
            s.plan == SubscriptionPlan.care && s.seniorProfileId == profile.id,
      )
      .firstOrNull;

  if (care == null) return const CareState(stage: CareStage.notBought);

  // 해지했고 남은 기간이 있다. Checked before the refusal and the active
  // cases: the row is still `granted` and still usable, and what changed is
  // only that there will be no next month.
  if (care.stillRunningAt(ref.watch(nowProvider)())) {
    return CareState(
      stage: switch (profile.paidConsentStatus) {
        PaidConsentStatus.pending => CareStage.askedAgain,
        PaidConsentStatus.refused => CareStage.declinedAgain,
        _ => CareStage.cancelling,
      },
      subscription: care,
    );
  }
  // 해지하고 기간까지 끝났다. Back to the beginning, which is right: they can
  // buy it again, and 해지됨 is not a state worth keeping a screen for.
  if (care.status == SubscriptionStatus.canceled) {
    return const CareState(stage: CareStage.notBought);
  }
  if (care.isWaitingOnSenior) {
    return CareState(stage: CareStage.waitingOnSenior, subscription: care);
  }
  // **Only the parent's 아니요 is a refusal.** A row is refunded three ways
  // now - the parent said no, the guardian cancelled before they answered,
  // or somebody left - and reading every refund as the first one told a
  // guardian who reconnected that their mother had turned them down.
  if (profile.paidConsentStatus == PaidConsentStatus.refused) {
    return CareState(stage: CareStage.refused, subscription: care);
  }
  if (care.isRefunded) {
    return const CareState(stage: CareStage.notBought);
  }
  // Both halves, and the consent one decides: a paid subscription whose senior
  // said nothing is not active.
  if (care.status == SubscriptionStatus.active &&
      profile.paidConsentStatus == PaidConsentStatus.granted) {
    return CareState(stage: CareStage.active, subscription: care);
  }
  return CareState(stage: CareStage.waitingOnSenior, subscription: care);
});

/// What 연결 끊기 and 계정 삭제 say about 안심 케어, or null when there is
/// nothing to say.
///
/// Both end the subscription through the server's `care_refund_due`, which
/// decides by use rather than by who left. So a running month gets the rule
/// and not a promise; a month never answered by the parent is always given
/// back; and one already cancelled was cancelled used, so nothing more is.
///
/// [reconnect] is 연결 끊기: a used month stays on the subscription with its
/// end date, and connecting the same parent again inside it brings it back.
/// 계정 삭제 has no such way back.
String? careLeavingLine(CareStage? stage, {required bool reconnect}) {
  final after = reconnect
      ? '사용한 적이 있으면, 남은 기간 안에 다시 연결한 뒤, 부모님이 다시 허락하시면 이어서 쓰실 수 있어요'
      : '사용한 적이 있으면 남은 기간은 쓰실 수 없게 돼요';
  return switch (stage) {
    CareStage.waitingOnSenior => '안심 케어 신청도 취소되고, 결제한 금액은 모두 돌려드립니다.',
    CareStage.active => '안심 케어도 함께 해지됩니다.\n$careRefundRule\n$after',
    // Cancelled while used, so the money was settled then.
    CareStage.cancelling ||
    CareStage.askedAgain ||
    CareStage.declinedAgain => '이미 해지하신 안심 케어는 더 돌려드릴 금액이 없어요.\n$after',
    _ => null,
  };
}

final careAlertsProvider = FutureProvider<List<CareAlert>>((ref) async {
  final profile = ref.watch(selectedSeniorProfileProvider);
  if (profile == null) return const [];
  return ref.watch(subscriptionRepositoryProvider).alertsFor(profile.id);
});

class CareController extends Notifier<void> {
  @override
  void build() {}

  /// Step 1. Comes back waiting on the senior — nothing is switched on here.
  Future<void> buyCare() async {
    final profile = ref.read(selectedSeniorProfileProvider);
    if (profile == null) return;
    await ref.read(subscriptionRepositoryProvider).startCare(profile.id);
    ref.invalidate(linkedSeniorProfilesProvider);
    ref.invalidate(careStateProvider);
  }

  /// 해지하기. Returns the row as it ended, so the screen can say whether
  /// money is coming back - the server decides that from use, not the app.
  Future<Subscription?> cancelCare() async {
    final profile = ref.read(selectedSeniorProfileProvider);
    if (profile == null) return null;
    final ended = await ref
        .read(subscriptionRepositoryProvider)
        .cancelCare(profile.id);
    ref.invalidate(careStateProvider);
    // The readings are what the subscription buys, so the dashboard has to
    // be asked again - on a null `current_period_end` they stop today.
    ref.invalidate(seniorReadingsProvider);
    return ended;
  }
}

final careControllerProvider = NotifierProvider<CareController, void>(
  CareController.new,
);
