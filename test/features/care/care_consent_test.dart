import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/guardian/presentation/widgets/guardian_nav_bar.dart';
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
import 'package:app/features/care/data/care_capabilities.dart';
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
  await tester.tap(find.byKey(GuardianNavKeys.destination('안심 케어')));
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
  });

  testWidgets('the senior is not asked about anything unbuilt', (tester) async {
    // It asked for 5분마다 어디 계신지. Location is not built and will not be
    // until the 위치기반서비스사업 신고 is through — so a 허락합니다 pressed
    // today would have been the only thing ever asked before the feature
    // switched itself on months later. 권한은 필요한 순간에 요청한다.
    final h = await _family();
    await h.subs.startCare(h.profileId);
    await _pumpSeniorHome(tester, h);

    for (final c in plannedCareCapabilities) {
      expect(
        find.textContaining(c.title),
        findsNothing,
        reason: '${c.key} is not built and must not be consented to',
      );
    }
    expect(find.textContaining('어디 계신지'), findsNothing);
    expect(find.textContaining('위치'), findsNothing);
  });

  testWidgets('the senior is not asked about what happens anyway', (
    tester,
  ) async {
    // The battery and ringer reading rides on the free check-in. It said
    // 배터리와 소리, 인터넷 상태, which told the senior that 아니요 would stop
    // something 아니요 does not stop — and named 인터넷, which is never read.
    final h = await _family();
    await h.subs.startCare(h.profileId);
    await _pumpSeniorHome(tester, h);

    // Scoped to the card, not the screen. 인터넷 is a word on the senior's
    // home now - the button that opens the phone's own panel - and matching
    // it anywhere would make this pass or fail on a control that has nothing
    // to do with what is being consented to. The rule itself is unchanged:
    // the card may not name a reading it does not take.
    final card = find.byType(CareConsentPrompt);
    expect(
      find.descendant(of: card, matching: find.textContaining('인터넷')),
      findsNothing,
    );
    expect(
      find.descendant(of: card, matching: find.textContaining('배터리와 소리')),
      findsNothing,
    );
  });

  testWidgets('it lists exactly what it will do, from the one list', (
    tester,
  ) async {
    final h = await _family();
    await h.subs.startCare(h.profileId);
    await _pumpSeniorHome(tester, h);

    for (final c in consentedCareCapabilities) {
      expect(find.textContaining(c.seniorLine!), findsOneWidget, reason: c.key);
    }
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

  testWidgets('a feature that works is not listed under 준비 중', (tester) async {
    // The 준비 중 block is honest only about what is below it. Anything built
    // sits above it, and a working feature under a sentence saying it does
    // not work is the mirror of the defect the block exists to prevent.
    final h = await _family();
    await _pumpCareTab(tester, h);

    // Read off the list rather than typed here. Both halves of this test
    // were hard-coded titles and both went stale the day the paid tier was
    // repriced - which is the failure the one-list design exists to stop,
    // reproduced in the test that guards it.
    final notice = tester.getRect(find.textContaining('아직 준비 중입니다'));
    for (final built in builtCareCapabilities) {
      expect(
        tester.getRect(find.text(built.title)).top,
        lessThan(notice.top),
        reason: '${built.title} 가 준비 중 안내 아래에 있습니다',
      );
    }
    for (final unbuilt in plannedCareCapabilities) {
      expect(
        tester.getRect(find.text(unbuilt.title)).top,
        greaterThan(notice.bottom),
        reason: '${unbuilt.title} 가 준비 중 안내 위에 있습니다',
      );
    }
  });

  testWidgets('every paid capability is named on the tab', (tester) async {
    // The gap this replaced a test for. 가족 메시지 무제한 was enforced on
    // the server and named on no screen, so a guardian paying 5,900원 could
    // not see one of the things they were buying; 홈 화면 정리 무제한 was
    // the same once it existed. The old test here asserted the opposite
    // arrangement - that 폰 상태 was free and only the 5분 주기 was sold -
    // and that stopped being true when the line moved.
    final h = await _family();
    await _pumpCareTab(tester, h);

    for (final c in careCapabilities) {
      expect(find.text(c.title), findsOneWidget, reason: c.key);
    }
  });

  testWidgets('nothing paid is described as happening anyway', (tester) async {
    // 기기 상태 was free and said so, which is why it could not be sold.
    // Now that it is paid, a line telling the guardian it happens on every
    // check-in regardless would be the screen undercutting its own price.
    final h = await _family();
    await _pumpCareTab(tester, h);

    expect(find.textContaining('무료로 제공'), findsNothing);
    expect(find.textContaining('이미 받고 계십니다'), findsNothing);
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
    expect(find.textContaining('배터리 · 소리 · 인터넷을 5분 주기로'), findsNothing);
  });

  testWidgets('the care tab keeps the wording the policy fixes', (
    tester,
  ) async {
    final h = await _family();
    await _pumpCareTab(tester, h);

    expect(find.textContaining('실시간'), findsNothing);
    // 위치 확인 is gone from the product entirely (2026-10-26): the police and
    // 119 route is better and free, Play's stalkerware rule aims at exactly
    // this, and the 위치기반서비스사업 신고 applies however it is collected.
    expect(find.textContaining('위치'), findsNothing);
    expect(find.textContaining('어디 계신지'), findsNothing);
    // 앱 설치 감지 went with it — an adult's installed-app list is sensitive
    // data about them.
    expect(find.textContaining('앱 설치'), findsNothing);
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
