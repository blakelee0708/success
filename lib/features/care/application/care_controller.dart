import 'package:flutter_riverpod/flutter_riverpod.dart';

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
enum CareStage { notBought, waitingOnSenior, refused, active }

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

  Future<void> buyFamilyPlan() async {
    await ref.read(subscriptionRepositoryProvider).startFamilyPlan();
    ref.invalidate(hasFamilyPlanProvider);
  }
}

final careControllerProvider = NotifierProvider<CareController, void>(
  CareController.new,
);
