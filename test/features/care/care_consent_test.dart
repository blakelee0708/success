import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/remote/subscription_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_profile.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/care/presentation/care_consent_prompt.dart';
import 'package:app/features/care/presentation/guardian_care_tab.dart';

import '../../support/pump_app.dart';

typedef Harness = ({
  InMemorySeniorLinkRepository store,
  InMemoryPairingRepository pairing,
  InMemorySubscriptionRepository subs,
  String profileId,
});

Future<Harness> _family() async {
  final store = InMemorySeniorLinkRepository();
  final pairing = InMemoryPairingRepository(store);
  final subs = InMemorySubscriptionRepository(store);
  await store.ensureGuardianAccount(displayName: '김보호');
  final started = await pairing.startSeniorPairing(installId: 'senior-phone');
  final profile = await pairing.claimSeniorPairingCode(
    code: started.code,
    displayName: '어머니',
  );
  return (store: store, pairing: pairing, subs: subs, profileId: profile.id);
}

List<Object> _overrides(Harness h) => [
  seniorLinkRepositoryProvider.overrideWithValue(h.store),
  pairingRepositoryProvider.overrideWithValue(h.pairing),
  subscriptionRepositoryProvider.overrideWithValue(h.subs),
  homeAppsRepositoryProvider.overrideWithValue(InMemoryHomeAppsRepository()),
];

/// The senior's own phone, on their home screen.
Future<void> _pumpSeniorHome(WidgetTester tester, Harness h) async {
  await pumpApp(
    tester,
    overrides: [
      ..._overrides(h),
      seniorLinkStoreProvider.overrideWithValue(
        InMemorySeniorLinkStore(
          SeniorLink(installId: 'senior-phone', seniorProfileId: h.profileId),
        ),
      ),
    ],
    prefs: {
      SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
        const SeniorSettings(
          screenMode: ScreenMode.easy,
          apps: defaultEasyApps,
        ).toJson(),
      ),
    },
  );
  await tester.pumpAndSettle();
}

/// The guardian's phone, on the 돌봄 tab.
Future<void> _pumpCareTab(WidgetTester tester, Harness h) async {
  final auth = InMemoryGuardianAuthRepository()
    ..seedSignedIn(const GuardianSession(userId: 'u1'));
  addTearDown(auth.dispose);
  await pumpApp(
    tester,
    overrides: [
      ..._overrides(h),
      guardianAuthRepositoryProvider.overrideWithValue(auth),
    ],
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('돌봄'));
  await tester.pumpAndSettle();
  // Lazily built cards need room, or the ones below the fold never enter the
  // tree at all.
  tester.view.physicalSize = const Size(390, 2600);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the senior is asked on their own phone after payment', (
    tester,
  ) async {
    final h = await _family();
    await h.subs.startCare(h.profileId);
    await _pumpSeniorHome(tester, h);

    expect(find.byKey(CareConsentPrompt.promptKey), findsOneWidget);
    expect(find.text('자녀분이 안심 케어를\n신청하셨어요'), findsOneWidget);
  });

  testWidgets('nothing is asked when nothing was bought', (tester) async {
    final h = await _family();
    await _pumpSeniorHome(tester, h);

    expect(find.byKey(CareConsentPrompt.promptKey), findsNothing);
  });

  testWidgets('the consent screen never calls it tracking', (tester) async {
    // 06_PERMISSION_AND_POLICY forbids the phrasing, and this is the screen
    // where it matters most: what is described here is what is consented to.
    final h = await _family();
    await h.subs.startCare(h.profileId);
    await _pumpSeniorHome(tester, h);

    expect(find.textContaining('실시간'), findsNothing);
    expect(find.textContaining('추적'), findsNothing);
    expect(find.textContaining('5분마다'), findsOneWidget);
  });

  testWidgets('refusing is offered as plainly as agreeing', (tester) async {
    final h = await _family();
    await h.subs.startCare(h.profileId);
    await _pumpSeniorHome(tester, h);

    expect(find.byKey(CareConsentPrompt.declineKey), findsOneWidget);
    expect(find.byKey(CareConsentPrompt.approveKey), findsOneWidget);
  });

  testWidgets('agreeing turns it on', (tester) async {
    final h = await _family();
    await h.subs.startCare(h.profileId);
    await _pumpSeniorHome(tester, h);

    await tester.tap(find.byKey(CareConsentPrompt.approveKey));
    await tester.pumpAndSettle();

    expect(await h.subs.careIsActive(h.profileId), isTrue);
    expect(find.byKey(CareConsentPrompt.promptKey), findsNothing);
  });

  testWidgets('refusing refunds and leaves the launcher alone', (tester) async {
    final h = await _family();
    await h.subs.startCare(h.profileId);
    await _pumpSeniorHome(tester, h);

    await tester.tap(find.byKey(CareConsentPrompt.declineKey));
    await tester.pumpAndSettle();

    expect(h.subs.subscriptions.single.isRefunded, isTrue);
    expect(await h.subs.careIsActive(h.profileId), isFalse);
    // 무료 기능은 유지: the home screen is exactly as it was.
    expect(find.text('전화'), findsOneWidget);
    expect(find.text('긴급 구조 요청'), findsOneWidget);
  });

  testWidgets('the guardian is shown the waiting state, not a working one', (
    tester,
  ) async {
    final h = await _family();
    await h.subs.startCare(h.profileId);
    await _pumpCareTab(tester, h);

    expect(find.byKey(GuardianCareKeys.waiting), findsOneWidget);
    expect(find.textContaining('아직은 아무 기능도 동작하지 않아요'), findsOneWidget);
  });

  testWidgets('the guardian sees the refusal and the refund', (tester) async {
    final h = await _family();
    await h.subs.startCare(h.profileId);
    await h.subs.resolveCareConsent(h.profileId, false);
    await _pumpCareTab(tester, h);

    expect(find.byKey(GuardianCareKeys.refused), findsOneWidget);
    expect(find.textContaining('환불'), findsWidgets);
  });

  testWidgets('the paid screen says the features are not built yet', (
    tester,
  ) async {
    // A paid screen that looks ready is a promise. None of these four is
    // implemented — they are interfaces, per the phase plan.
    final h = await _family();
    await _pumpCareTab(tester, h);

    expect(find.textContaining('아직 준비 중입니다'), findsOneWidget);
  });

  testWidgets('a feature that works is not listed under 준비 중', (
    tester,
  ) async {
    // The 준비 중 block is honest only about what is below it. 기기 상태 is
    // built — it rides on the parent's check-in — and leaving it under that
    // block is the same defect as a working-looking screen over an unbuilt
    // feature, read the other way round.
    final h = await _family();
    await _pumpCareTab(tester, h);

    final notice = tester.getRect(find.textContaining('아직 준비 중입니다'));
    expect(
      tester.getRect(find.text('기기 상태 확인')).top,
      lessThan(notice.top),
      reason: '기기 상태가 준비 중 안내 아래에 있습니다',
    );
    expect(
      tester.getRect(find.text('위치 확인')).top,
      greaterThan(notice.bottom),
    );
  });

  testWidgets('the care tab does not promise what 기기 상태 does not do', (
    tester,
  ) async {
    // It never reads the network, and it has no 5-minute schedule — the
    // reading rides on the check-in. Both were in the sketch and neither
    // shipped.
    final h = await _family();
    await _pumpCareTab(tester, h);

    expect(find.textContaining('인터넷'), findsNothing);
    expect(
      find.textContaining('배터리 · 소리 · 인터넷을 5분 주기로'),
      findsNothing,
    );
  });

  testWidgets('the care tab keeps the wording the policy fixes', (
    tester,
  ) async {
    final h = await _family();
    await _pumpCareTab(tester, h);

    expect(find.textContaining('실시간'), findsNothing);
    expect(find.text('위치 확인'), findsOneWidget);
    // 모르는 번호 통화 알림 is gone, and so is the 보이스피싱 framing the PRD
    // never allowed: Play grants READ_CALL_LOG to default phone and messaging
    // apps, and this is a launcher.
    expect(find.textContaining('통화'), findsNothing);
    expect(find.textContaining('보이스피싱'), findsNothing);
  });

  testWidgets('the family plan is distinguished from inviting a sibling', (
    tester,
  ) async {
    final h = await _family();
    await _pumpCareTab(tester, h);

    expect(find.byKey(GuardianCareKeys.familyPlan), findsOneWidget);
    expect(find.textContaining('형제자매를 초대하는 것은'), findsOneWidget);
    expect(find.textContaining('무료'), findsWidgets);
  });

  testWidgets('buying the family plan needs no senior involvement', (
    tester,
  ) async {
    final h = await _family();
    await _pumpCareTab(tester, h);

    await tester.tap(find.text('가족 플랜 신청하기'));
    await tester.pumpAndSettle();

    expect(await h.subs.hasFamilyPlan(), isTrue);
    expect(
      h.store.profiles[h.profileId]!.paidConsentStatus,
      isNot(PaidConsentStatus.pending),
    );
  });
}
