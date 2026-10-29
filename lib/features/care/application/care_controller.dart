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
enum CareStage { notBought, waitingOnSenior, refused, active, cancelling }

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
    return CareState(stage: CareStage.cancelling, subscription: care);
  }
  // 해지하고 기간까지 끝났다. Back to the beginning, which is right: they can
  // buy it again, and 해지됨 is not a state worth keeping a screen for.
  if (care.status == SubscriptionStatus.canceled) {
    return const CareState(stage: CareStage.notBought);
  }
  if (care.isWaitingOnSenior) {
    return CareState(stage: CareStage.waitingOnSenior, subscription: care);
  }
  if (care.isRefunded ||
      profile.paidConsentStatus == PaidConsentStatus.refused) {
    return CareState(stage: CareStage.refused, subscription: care);
  }
  // Both halves, and the consent one decides: a paid subscription whose senior
  // said nothing is not active.
  if (care.status == SubscriptionStatus.active &&
      profile.paidConsentStatus == PaidConsentStatus.granted) {
    return CareState(stage: CareStage.active, subscription: care);
  }
  return CareState(stage: CareStage.waitingOnSenior, subscription: care);
});

final hasFamilyPlanProvider = FutureProvider<bool>(
  (ref) => ref.watch(subscriptionRepositoryProvider).hasFamilyPlan(),
);

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

  /// 해지하기. The days already paid for are kept, so nothing is refunded -
  /// that is the one difference from 연결 끊기, which refunds because the
  /// guardian can no longer use what is left.
  Future<void> cancelCare() async {
    final profile = ref.read(selectedSeniorProfileProvider);
    if (profile == null) return;
    await ref.read(subscriptionRepositoryProvider).cancelCare(profile.id);
    ref.invalidate(careStateProvider);
    // The readings are what the subscription buys, so the dashboard has to
    // be asked again - on a null `current_period_end` they stop today.
    ref.invalidate(seniorReadingsProvider);
  }

  Future<void> buyFamilyPlan() async {
    await ref.read(subscriptionRepositoryProvider).startFamilyPlan();
    ref.invalidate(hasFamilyPlanProvider);
  }
}

final careControllerProvider = NotifierProvider<CareController, void>(
  CareController.new,
);
