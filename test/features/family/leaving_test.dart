import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/core/support_contact.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/message_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/remote/subscription_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/domain/senior_profile.dart';
import 'package:app/domain/subscription.dart';
import 'package:app/features/family/application/senior_pairing_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/care/presentation/guardian_care_tab.dart';
import 'package:app/features/family/presentation/family_link_screen.dart';
import 'package:app/features/guardian/presentation/guardian_dashboard_screen.dart';
import 'package:app/features/guardian/presentation/guardian_family_tab.dart';
import 'package:app/features/guardian/presentation/widgets/guardian_nav_bar.dart';

import '../../support/pump_app.dart';

/// 끊기, 해지 and 계정 삭제 - the four doors out, and what each one promises
/// is still true on the other side of it.
///
/// **What these cannot prove is the part that matters most**, and that is
/// recorded rather than worked around: the in-memory twins have no RLS, so
/// here a removed guardian still reads everything. That a removal actually
/// stops the server answering is `tool/verify_supabase_leaving.py`'s job, 47
/// checks against the live project. What is tested here is the screen: that
/// the way out exists, that it says what is **not** lost before what is, and
/// that the app stops showing a family that has gone.
typedef Harness = ({
  InMemorySeniorLinkRepository store,
  InMemoryPairingRepository pairing,
  InMemorySubscriptionRepository subs,
  String profileId,
});

Future<Harness> _family({String guardianName = '영희'}) async {
  final store = InMemorySeniorLinkRepository();
  final pairing = InMemoryPairingRepository(store);
  final subs = InMemorySubscriptionRepository(store);
  await store.ensureGuardianAccount(displayName: guardianName);
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
  messageRepositoryProvider.overrideWithValue(
    InMemoryMessageRepository(h.store, subscriptions: h.subs),
  ),
];

/// The parent's phone, on 설정 → 가족 연결 설정.
Future<void> _pumpSeniorFamilyScreen(WidgetTester tester, Harness h) async {
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
  // The route a senior actually walks. With a family attached the 가족 button
  // opens the conversation rather than this screen, so 설정 is the way in -
  // which is also the path 사용법 gives.
  await tester.tap(find.text('더 보기'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('가족 연결 설정'));
  await tester.pumpAndSettle();
}

/// The child's phone, on 홈 - which is where 연결 관리 lives now.
Future<InMemoryGuardianAuthRepository> _pumpGuardianHome(
  WidgetTester tester,
  Harness h, {
  bool care = false,
  bool used = false,
}) async {
  final auth = InMemoryGuardianAuthRepository()
    ..seedSignedIn(const GuardianSession(userId: 'u1'));
  addTearDown(auth.dispose);
  if (care) {
    await h.subs.startCare(h.profileId);
    await h.subs.resolveCareConsent(h.profileId, true);
    if (used) h.subs.used.add(h.subs.subscriptions.last.id);
  }
  await pumpApp(
    tester,
    overrides: [
      ..._overrides(h),
      guardianAuthRepositoryProvider.overrideWithValue(auth),
    ],
  );
  await tester.pumpAndSettle();
  // A `ListView` does not build what is far below the fold, and 연결 관리 is
  // the last block on the tab. Taller viewport rather than scrolling: what is
  // under test is the row, not the scrolling.
  tester.view.physicalSize = const Size(390, 6400);
  await tester.pumpAndSettle();
  return auth;
}

Future<void> _openCareTab(WidgetTester tester) async {
  await tester.tap(find.byKey(GuardianNavKeys.destination('안심 케어')));
  await tester.pumpAndSettle();
  tester.view.physicalSize = const Size(390, 3600);
  await tester.pumpAndSettle();
}

void main() {
  // ===========================================================
  // 어르신이 끊는다
  // ===========================================================
  testWidgets('the parent sees their children by name, each with its own 끊기', (
    tester,
  ) async {
    // One row per child. A single 가족 연결을 끊기 that took everybody off
    // was considered and refused: the person a mother is cross with is
    // usually one of them.
    final h = await _family();
    await _pumpSeniorFamilyScreen(tester, h);

    expect(find.byKey(FamilyLinkKeys.connected), findsOneWidget);
    expect(find.text('영희'), findsOneWidget);
    expect(find.text('연결 끊기'), findsOneWidget);
  });

  testWidgets('it says what is not lost before it asks', (tester) async {
    final h = await _family();
    await _pumpSeniorFamilyScreen(tester, h);

    await tester.tap(find.text('연결 끊기'));
    await tester.pumpAndSettle();

    expect(find.byKey(FamilyLinkKeys.removeConfirm), findsOneWidget);
    // 영희 ends in a vowel. The dialog used to say 영희과 and 영희이, and
    // the fallback 자녀분 ends in ㄴ, which is why no test caught it.
    expect(find.text('영희와 연결을 끊을까요?'), findsOneWidget);
    expect(find.textContaining('영희가 이 폰을 볼 수 없게'), findsOneWidget);
    expect(find.textContaining('버튼과 글씨 크기는 그대로 있어요'), findsOneWidget);
    expect(find.textContaining('나중에 다시 연결하실 수 있어요'), findsOneWidget);
    // Neither button may read as the other one. 그만두기 is the word the row
    // that opens the 사용하지 않기 dialog uses, so it reads as a confirm.
    expect(find.text('아니요, 그대로 둘게요'), findsOneWidget);
    expect(find.text('네'), findsOneWidget);
  });

  testWidgets('backing out keeps the family', (tester) async {
    final h = await _family();
    await _pumpSeniorFamilyScreen(tester, h);

    await tester.tap(find.text('연결 끊기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('아니요, 그대로 둘게요'));
    await tester.pumpAndSettle();

    expect(find.byKey(FamilyLinkKeys.connected), findsOneWidget);
    expect(h.store.rolesByProfile[h.profileId], isNotEmpty);
  });

  testWidgets('cutting the last child puts the screen back to the number', (
    tester,
  ) async {
    // 연결됨 means a guardian is attached, not that a profile exists - so
    // with the last one gone the screen goes back to offering the code,
    // which is also how the same child is connected again.
    final h = await _family();
    await _pumpSeniorFamilyScreen(tester, h);

    await tester.tap(find.text('연결 끊기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('네'));
    await tester.pumpAndSettle();

    expect(h.store.rolesByProfile[h.profileId] ?? const {}, isEmpty);
    expect(find.byKey(FamilyLinkKeys.connected), findsNothing);
    expect(find.byKey(FamilyLinkKeys.showCode), findsOneWidget);
  });

  // ===========================================================
  // 자녀가 끊는다
  // ===========================================================
  testWidgets('the child can leave, and is told what stays', (tester) async {
    final h = await _family();
    await _pumpGuardianHome(tester, h);

    await tester.ensureVisible(find.byKey(GuardianFamilyKeys.leave));
    await tester.tap(find.byKey(GuardianFamilyKeys.leave));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianFamilyKeys.leaveConfirm), findsOneWidget);
    expect(find.textContaining('어머니님 폰은 그대로입니다'), findsOneWidget);
    expect(find.textContaining('나중에 다시 연결하실 수 있어요'), findsOneWidget);
  });

  testWidgets('the refund line is said only when there is a subscription', (
    tester,
  ) async {
    final h = await _family();
    await _pumpGuardianHome(tester, h);

    await tester.ensureVisible(find.byKey(GuardianFamilyKeys.leave));
    await tester.tap(find.byKey(GuardianFamilyKeys.leave));
    await tester.pumpAndSettle();
    expect(find.textContaining('돌려드립니다'), findsNothing);
    expect(find.textContaining('환불'), findsNothing);
  });

  testWidgets('with 안심 케어 on, leaving says the refund rule, not a promise', (
    tester,
  ) async {
    // Who cut does not decide the money - use does. A child who asked their
    // mother to press 끊기 would otherwise be paid back for a month they used.
    final h = await _family();
    await _pumpGuardianHome(tester, h, care: true);

    await tester.ensureVisible(find.byKey(GuardianFamilyKeys.leave));
    await tester.tap(find.byKey(GuardianFamilyKeys.leave));
    await tester.pumpAndSettle();
    expect(find.textContaining(careRefundRule), findsOneWidget);
    expect(
      find.textContaining('남은 기간 안에 다시 연결한 뒤, 부모님이 다시 허락하시면'),
      findsOneWidget,
    );
    expect(find.textContaining('남은 기간에 해당하는 금액을 돌려드립니다'), findsNothing);
  });

  testWidgets('deleting the account says the refund rule too', (tester) async {
    final h = await _family();
    await _pumpGuardianHome(tester, h, care: true);

    await tester.ensureVisible(find.byKey(GuardianFamilyKeys.deleteAccount));
    await tester.tap(find.byKey(GuardianFamilyKeys.deleteAccount));
    await tester.pumpAndSettle();
    expect(find.byKey(GuardianFamilyKeys.deleteConfirm), findsOneWidget);
    expect(find.textContaining(careRefundRule), findsOneWidget);
    // There is no reconnecting after a delete, so it is not offered.
    expect(find.textContaining('남은 기간은 쓰실 수 없게 돼요'), findsOneWidget);
    expect(find.textContaining('다시 연결한 뒤'), findsNothing);
  });

  testWidgets('leaving takes the parent off this phone', (tester) async {
    final h = await _family();
    await _pumpGuardianHome(tester, h);

    await tester.ensureVisible(find.byKey(GuardianFamilyKeys.leave));
    await tester.tap(find.byKey(GuardianFamilyKeys.leave));
    await tester.pumpAndSettle();
    await tester.tap(find.text('네'));
    await tester.pumpAndSettle();

    expect(h.store.linkedProfileIds, isEmpty);
    expect(find.byKey(GuardianHomeKeys.noParent), findsOneWidget);
  });

  // ===========================================================
  // 계정 삭제
  // ===========================================================
  testWidgets('계정 삭제 is there, under 로그아웃', (tester) async {
    // Play requires it in the app as well as on the web, and says in as many
    // words that deactivating does not count. It sits **below** 로그아웃
    // because that is what almost everyone looking for a way out wants.
    final h = await _family();
    await _pumpGuardianHome(tester, h);

    await tester.ensureVisible(find.byKey(GuardianFamilyKeys.deleteAccount));
    final out = tester.getRect(find.byKey(GuardianFamilyKeys.signOut));
    final delete = tester.getRect(find.byKey(GuardianFamilyKeys.deleteAccount));
    expect(delete.top, greaterThan(out.top));
  });

  testWidgets('it is the one button whose dialog says 되돌릴 수 없어요', (
    tester,
  ) async {
    final h = await _family();
    final auth = await _pumpGuardianHome(tester, h);

    await tester.ensureVisible(find.byKey(GuardianFamilyKeys.deleteAccount));
    await tester.tap(find.byKey(GuardianFamilyKeys.deleteAccount));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianFamilyKeys.deleteConfirm), findsOneWidget);
    expect(find.textContaining('되돌릴 수 없어요'), findsOneWidget);
    // And what the parent keeps, which is what somebody about to press this
    // is most likely to be afraid of.
    expect(find.textContaining('부모님 폰은 그대로 쓰실 수 있어요'), findsOneWidget);
    expect(find.textContaining('메시지는 부모님 폰에 남습니다'), findsOneWidget);
    expect(auth.currentSession, isNotNull);
  });

  testWidgets('backing out keeps the account', (tester) async {
    final h = await _family();
    final auth = await _pumpGuardianHome(tester, h);

    await tester.ensureVisible(find.byKey(GuardianFamilyKeys.deleteAccount));
    await tester.tap(find.byKey(GuardianFamilyKeys.deleteAccount));
    await tester.pumpAndSettle();
    await tester.tap(find.text('아니요, 그대로 둘게요'));
    await tester.pumpAndSettle();

    expect(auth.currentSession, isNotNull);
    expect(h.store.linkedProfileIds, isNotEmpty);
  });

  testWidgets('confirming ends the session and leaves the dashboard', (
    tester,
  ) async {
    final h = await _family();
    final auth = await _pumpGuardianHome(tester, h);

    await tester.ensureVisible(find.byKey(GuardianFamilyKeys.deleteAccount));
    await tester.tap(find.byKey(GuardianFamilyKeys.deleteAccount));
    await tester.pumpAndSettle();
    await tester.tap(
      // Scoped to the dialog: the row behind it carries 계정 삭제, and the
      // confirm is the only 계정 지우기 on screen either way.
      find.descendant(
        of: find.byKey(GuardianFamilyKeys.deleteConfirm),
        matching: find.text('계정 지우기'),
      ),
    );
    // Pumped rather than settled: deleting lands on the launch gate, which
    // resolves to the splash, and the splash loops its tap prompt forever.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(auth.currentSession, isNull);
    // The parent's profile survives: they are still holding that phone.
    expect(h.store.profiles[h.profileId], isNotNull);
  });

  // ===========================================================
  // 내 전화번호
  // ===========================================================
  testWidgets('연결 관리 can change the number the parent dials', (tester) async {
    // It was the one number this app holds and the one it could not change.
    // A guardian who moves house and keeps the old number on file leaves
    // their mother's 보호자 button ringing a dead line.
    final h = await _family();
    await _pumpGuardianHome(tester, h);

    await tester.ensureVisible(find.byKey(GuardianFamilyKeys.myPhoneEdit));
    await tester.tap(find.byKey(GuardianFamilyKeys.myPhoneEdit));
    await tester.pumpAndSettle();

    // Why it is being asked for, on the dialog. A number with no reason
    // beside it is the field people leave blank. `findsWidgets`, not one:
    // the connect form above says the same sentence under its own 내 전화번호
    // field, and saying it in both places is the point.
    expect(find.textContaining('긴급 연락에서 이 번호로 전화가 갑니다'), findsWidgets);
    await tester.enterText(
      find.byKey(GuardianFamilyKeys.myPhoneField),
      '01099998888',
    );
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    final account = await h.store.ensureGuardianAccount();
    expect(account.phoneNumber, '01099998888');
  });

  // ===========================================================
  // 연결 폼의 두 전화번호
  // ===========================================================
  testWidgets('번호 입력 asks for the child\'s number, not the parent\'s', (
    tester,
  ) async {
    // **This was a real bug on the live project.** One field labelled
    // 부모님 전화번호 was written into `guardian_accounts.phone_number` -
    // the number the parent's 긴급 연락 dials - so connecting by code gave a
    // mother a 보호자 button that rang her own phone.
    final store = InMemorySeniorLinkRepository();
    final pairing = InMemoryPairingRepository(store);
    final subs = InMemorySubscriptionRepository(store);
    await store.ensureGuardianAccount(displayName: '영희');
    final h = (store: store, pairing: pairing, subs: subs, profileId: '');

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
    tester.view.physicalSize = const Size(390, 6400);
    await tester.pumpAndSettle();

    // 설치 문자 mode: the parent's number is the recipient, so both are asked.
    expect(find.byKey(GuardianFamilyKeys.phoneField), findsOneWidget);
    expect(find.byKey(GuardianFamilyKeys.myPhoneOnConnect), findsOneWidget);

    await tester.tap(find.text('불러주신 번호 넣기'));
    await tester.pumpAndSettle();

    // 번호 입력 mode: there is nothing to send, so there is no parent's
    // number to ask for - and the one field that remains is the child's.
    expect(find.byKey(GuardianFamilyKeys.phoneField), findsNothing);
    expect(find.byKey(GuardianFamilyKeys.myPhoneOnConnect), findsOneWidget);
    expect(find.textContaining('부모님 폰의 긴급 연락에서 이 번호로'), findsOneWidget);
  });

  testWidgets('the number typed on the connect form is the child\'s own', (
    tester,
  ) async {
    final store = InMemorySeniorLinkRepository();
    final pairing = InMemoryPairingRepository(store);
    final subs = InMemorySubscriptionRepository(store);
    await store.ensureGuardianAccount(displayName: '영희');
    // A parent's phone has already shown its number.
    final shown = await pairing.startSeniorPairing(installId: 'senior-phone');
    final h = (store: store, pairing: pairing, subs: subs, profileId: '');

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
    tester.view.physicalSize = const Size(390, 6400);
    await tester.pumpAndSettle();

    await tester.tap(find.text('불러주신 번호 넣기'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(GuardianFamilyKeys.codeField),
      shown.code,
    );
    await tester.enterText(find.byKey(GuardianFamilyKeys.nameField), '엄마');
    await tester.enterText(
      find.byKey(GuardianFamilyKeys.myPhoneOnConnect),
      '01011112222',
    );
    await tester.tap(find.byKey(GuardianFamilyKeys.enterCode));
    await tester.pumpAndSettle();

    final account = await store.ensureGuardianAccount();
    expect(account.phoneNumber, '01011112222');
  });

  // ===========================================================
  // 부모님이 폰을 바꾸셨을 때
  // ===========================================================
  testWidgets('the new phone\'s number moves the parent, in one step', (
    tester,
  ) async {
    // The parent does what they always do and presses 번호 보여주기 on the
    // new handset, which makes a second, empty profile. With a parent
    // already here the card asks for nothing else - 무조건 자녀 하나, 부모
    // 하나, so the number can only be that parent's new phone.
    final h = await _family();
    await _pumpGuardianHome(tester, h);

    final newPhone = await h.pairing.startSeniorPairing(
      installId: 'new-senior-phone',
    );
    expect(find.text('부모님이 폰을 바꾸셨나요?'), findsOneWidget);
    await tester.ensureVisible(find.byKey(GuardianFamilyKeys.codeField));
    await tester.enterText(
      find.byKey(GuardianFamilyKeys.codeField),
      newPhone.code,
    );
    await tester.tap(find.byKey(GuardianFamilyKeys.enterCode));
    await tester.pumpAndSettle();

    expect(h.store.linkedProfileIds, [h.profileId]);
    // And the new handset is the one the profile answers for.
    expect(
      h.store.activeDeviceByProfile[h.profileId]?.installId,
      'new-senior-phone',
    );
  });

  // ===========================================================
  // 안심 케어 해지하기, and 문의하기
  // ===========================================================
  testWidgets('해지하기 is on the tab that promises it', (tester) async {
    final h = await _family();
    await _pumpGuardianHome(tester, h, care: true);
    await _openCareTab(tester);

    expect(find.byKey(GuardianCareKeys.cancel), findsOneWidget);
    expect(find.byKey(GuardianCareKeys.contact), findsOneWidget);
    expect(find.textContaining(supportEmail), findsOneWidget);
  });

  testWidgets('there is nothing to cancel before anything is bought', (
    tester,
  ) async {
    final h = await _family();
    await _pumpGuardianHome(tester, h);
    await _openCareTab(tester);

    // A 해지하기 on a tab nobody has bought anything from is a button that
    // can only produce an error. 문의하기 is always there.
    expect(find.byKey(GuardianCareKeys.cancel), findsNothing);
    expect(find.byKey(GuardianCareKeys.contact), findsOneWidget);
  });

  testWidgets('it says what is kept before it asks', (tester) async {
    final h = await _family();
    await _pumpGuardianHome(tester, h, care: true);
    await _openCareTab(tester);

    await tester.ensureVisible(find.byKey(GuardianCareKeys.cancel));
    await tester.tap(find.byKey(GuardianCareKeys.cancel));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianCareKeys.cancelConfirm), findsOneWidget);
    // The rule, in the owner's words, on the ordinary 해지 too - not only
    // where money is certain to move.
    expect(find.textContaining(careRefundRule), findsOneWidget);
    expect(find.textContaining('다음 결제는 없습니다'), findsOneWidget);
    expect(find.textContaining('어머니님 폰은 그대로입니다'), findsOneWidget);
    expect(find.textContaining('언제든 다시 신청하실 수 있어요'), findsOneWidget);
  });

  testWidgets('after 해지 the tab says the days are still there', (tester) async {
    // **A cancelled row used to fall through to 허락을 기다리고 있어요**,
    // which told a guardian their parent had not answered about a
    // subscription that parent agreed to months ago.
    final h = await _family();
    await _pumpGuardianHome(tester, h, care: true, used: true);
    await _openCareTab(tester);

    await tester.ensureVisible(find.byKey(GuardianCareKeys.cancel));
    await tester.tap(find.byKey(GuardianCareKeys.cancel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('해지하기'));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianCareKeys.cancelling), findsOneWidget);
    expect(find.byKey(GuardianCareKeys.waiting), findsNothing);
    expect(find.text('남은 기간까지 쓰실 수 있어요'), findsOneWidget);
    // A used month gives nothing back, so nothing is said about money.
    expect(find.byKey(GuardianCareKeys.refunded), findsNothing);
  });

  testWidgets('an unused month inside seven days comes back in full', (
    tester,
  ) async {
    final h = await _family();
    await _pumpGuardianHome(tester, h, care: true);
    await _openCareTab(tester);

    await tester.ensureVisible(find.byKey(GuardianCareKeys.cancel));
    await tester.tap(find.byKey(GuardianCareKeys.cancel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('해지하기'));
    await tester.pump();

    expect(find.byKey(GuardianCareKeys.refunded), findsOneWidget);
    expect(find.text('전액 환불됩니다.'), findsOneWidget);
    expect(h.subs.subscriptions.single.refundKind, RefundKind.full);
    await tester.pumpAndSettle();
    // Refunded is off at once, so the tab is back to the offer.
    expect(find.byKey(GuardianCareKeys.cancelling), findsNothing);
  });

  testWidgets('an unused month after seven days comes back by its days', (
    tester,
  ) async {
    final h = await _family();
    await _pumpGuardianHome(tester, h, care: true);
    final paid = h.subs.subscriptions.single.id;
    h.subs.paidAt[paid] = DateTime.now().subtract(const Duration(days: 10));
    await _openCareTab(tester);

    await tester.ensureVisible(find.byKey(GuardianCareKeys.cancel));
    await tester.tap(find.byKey(GuardianCareKeys.cancel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('해지하기'));
    await tester.pump();

    expect(find.text('사용하지 않으셔서 남은 기간만큼 환불됩니다.'), findsOneWidget);
    expect(h.subs.subscriptions.single.refundKind, RefundKind.remaining);
  });

  testWidgets('a used month reconnected waits on the parent again', (
    tester,
  ) async {
    // Reconnecting is the parent agreeing to the link, not to being looked
    // at, so the tab must not say 남은 기간까지 쓰실 수 있어요 until they say
    // so - and there is no new payment for 해지하기 to act on.
    final h = await _family();
    await _pumpGuardianHome(tester, h, care: true, used: true);
    await h.subs.cancelCare(h.profileId);
    h.store.setConsent(h.profileId, PaidConsentStatus.pending);
    await _pumpGuardianHome(tester, h);
    await _openCareTab(tester);

    expect(find.byKey(GuardianCareKeys.askedAgain), findsOneWidget);
    expect(find.byKey(GuardianCareKeys.cancelling), findsNothing);
    expect(find.byKey(GuardianCareKeys.cancel), findsNothing);
  });

  testWidgets('a second 거절 says there is no refund', (tester) async {
    final h = await _family();
    await _pumpGuardianHome(tester, h, care: true, used: true);
    await h.subs.cancelCare(h.profileId);
    h.store.setConsent(h.profileId, PaidConsentStatus.pending);
    h.store.seniorInstallId =
        h.store.activeDeviceByProfile[h.profileId]!.installId;
    await h.subs.resolveCareConsent(h.profileId, false);
    await _pumpGuardianHome(tester, h);
    await _openCareTab(tester);

    expect(find.byKey(GuardianCareKeys.declinedAgain), findsOneWidget);
    // Once on the notice and once in the alert the server wrote.
    expect(find.textContaining('환불은 없습니다'), findsWidgets);
    expect(find.textContaining('환불 처리되었습니다'), findsNothing);
    expect(h.subs.subscriptions.single.status, SubscriptionStatus.canceled);
  });

  // ===========================================================
  // 검토에서 나온 것
  // ===========================================================

  testWidgets('a refund from leaving is not read as the parent refusing', (
    tester,
  ) async {
    // A row is refunded three ways now - the parent said no, the guardian
    // cancelled before they answered, or somebody left. Reading every refund
    // as the first told a guardian who reconnected that their mother had
    // turned them down, when she had agreed.
    final h = await _family();
    await h.subs.startCare(h.profileId);
    await h.subs.resolveCareConsent(h.profileId, true);
    final paid = h.subs.subscriptions.single;
    h.subs.subscriptions[0] = Subscription(
      id: paid.id,
      plan: paid.plan,
      status: SubscriptionStatus.refunded,
      seniorProfileId: paid.seniorProfileId,
      refundedAt: DateTime(2026, 10, 29),
    );
    await _pumpGuardianHome(tester, h);
    await _openCareTab(tester);

    expect(find.byKey(GuardianCareKeys.refused), findsNothing);
    expect(find.byKey(GuardianCareKeys.buyCare), findsOneWidget);
  });

  testWidgets('해지 before the parent answers says the money comes back', (
    tester,
  ) async {
    // Nothing ran, so there is no remaining period to keep - the server
    // refunds it. The dialog used to promise 남은 기간까지 쓰실 수 있어요.
    final h = await _family();
    await h.subs.startCare(h.profileId);
    await _pumpGuardianHome(tester, h);
    await _openCareTab(tester);

    await tester.ensureVisible(find.byKey(GuardianCareKeys.cancel));
    await tester.tap(find.byKey(GuardianCareKeys.cancel));
    await tester.pumpAndSettle();

    expect(find.textContaining('돌려드립니다'), findsOneWidget);
    expect(find.textContaining('남은 기간까지는'), findsNothing);
  });

  testWidgets('a phone moved onto its old profile follows it', (tester) async {
    // 어머니 폰을 바꿨어요, answered on the child's phone, moves this
    // handset onto the original profile and deletes the empty one it had
    // saved. Nothing else tells this phone, so it went on asking about a
    // profile that no longer existed.
    final h = await _family();
    final links = InMemorySeniorLinkStore(
      const SeniorLink(installId: 'senior-phone', seniorProfileId: 'gone'),
    );
    await pumpApp(
      tester,
      overrides: [
        ..._overrides(h),
        seniorLinkStoreProvider.overrideWithValue(links),
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

    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    await container
        .read(seniorPairingControllerProvider.notifier)
        .followMovedPhone();
    await tester.pumpAndSettle();

    expect((await links.load()).seniorProfileId, h.profileId);
  });
}
