import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/features/guardian/presentation/guardian_family_tab.dart';

import '../../support/pump_app.dart';

typedef Harness = ({
  InMemorySeniorLinkRepository store,
  InMemoryPairingRepository pairing,
});

/// A signed-in guardian on the 가족 tab.
Future<Harness> _pumpFamilyTab(
  WidgetTester tester, {
  bool withParent = false,
  bool withSibling = false,
}) async {
  final auth = InMemoryGuardianAuthRepository()
    ..seedSignedIn(const GuardianSession(userId: 'u1', email: 'g@example.com'));
  addTearDown(auth.dispose);

  final store = InMemorySeniorLinkRepository();
  final pairing = InMemoryPairingRepository(store);
  await store.ensureGuardianAccount(displayName: '김보호');
  if (withParent) {
    final started = await pairing.startSeniorPairing(installId: 'senior-phone');
    final profile = await pairing.claimSeniorPairingCode(
      code: started.code,
      displayName: '어머니',
    );
    if (withSibling) {
      final invite = await pairing.createFamilyInvite(profile.id);
      pairing.actingGuardianId = 'sibling';
      await pairing.redeemFamilyInvite(invite.code);
      pairing.actingGuardianId = 'account-1';
    }
  }

  await pumpApp(
    tester,
    overrides: [
      guardianAuthRepositoryProvider.overrideWithValue(auth),
      seniorLinkRepositoryProvider.overrideWithValue(store),
      pairingRepositoryProvider.overrideWithValue(pairing),
    ],
  );
  await tester.pumpAndSettle();
  // **연결 관리 is at the bottom of 홈 now**, not of 안심 케어 - nothing in
  // it is about the paid tier, and a guardian who has not bought it had no
  // reason to open that tab. So there is no tab to switch to: 부모님
  // 연결하기 and everything about a connection are on the one page.
  //
  // The tab is a ListView and its cards are lazily built, so a phone-sized
  // viewport would leave the ones below the fold out of the tree entirely.
  // Taller viewport rather than scrolling in each case: what is being tested
  // is the content, not the scrolling.
  tester.view.physicalSize = const Size(390, 6400);
  await tester.pumpAndSettle();

  return (store: store, pairing: pairing);
}

void main() {
  testWidgets('both paths from the plan are offered side by side', (
    tester,
  ) async {
    await _pumpFamilyTab(tester);

    expect(find.text('설치 문자 보내기'), findsOneWidget);
    expect(find.text('불러주신 번호 넣기'), findsOneWidget);
  });

  testWidgets('the invite never claims the message was sent', (tester) async {
    // The app can only hand the text to the messaging app, and cannot see what
    // happens next. Same rule as SOS: never claim an action the user still has
    // to take themselves.
    // With a parent already linked, so the form under test is 연결 관리's.
    // On 홈 the first invite creates the profile, which takes that tab out of
    // its empty state and the card with it - the code is re-shown from
    // 연결 관리 instead.
    final h = await _pumpFamilyTab(tester, withParent: true);

    await tester.enterText(find.byKey(GuardianFamilyKeys.nameField), '아버지');
    await tester.tap(find.byKey(GuardianFamilyKeys.invite));
    await tester.pumpAndSettle();

    expect(find.text('문자 앱에 내용을 채워 두었어요. 보내기는 직접 눌러 주세요.'), findsOneWidget);
    expect(find.textContaining('문자를 보냈'), findsNothing);
    expect(find.textContaining('발송'), findsNothing);
    // Not `single`: the parent this test starts with was linked by a code
    // of their own, so this is the second one issued.
    expect(h.pairing.issued.last.code, isNotEmpty);
  });

  testWidgets('the invite also shows the code, for a link that did not survive', (
    tester,
  ) async {
    // Path A depends on the Play install referrer, which only survives a store
    // install — so the fallback has to be in front of the guardian, not buried.
    await _pumpFamilyTab(tester, withParent: true);

    await tester.enterText(find.byKey(GuardianFamilyKeys.nameField), '아버지');
    await tester.tap(find.byKey(GuardianFamilyKeys.invite));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianFamilyKeys.issuedCode), findsOneWidget);
  });

  testWidgets('a parent with no name is refused before anything is created', (
    tester,
  ) async {
    final h = await _pumpFamilyTab(tester);

    await tester.tap(find.byKey(GuardianFamilyKeys.invite));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianFamilyKeys.message), findsOneWidget);
    expect(h.store.profiles, isEmpty);
  });

  testWidgets('typing the code the parent read out connects them', (
    tester,
  ) async {
    final store = InMemorySeniorLinkRepository();
    final pairing = InMemoryPairingRepository(store);
    await store.ensureGuardianAccount(displayName: '김보호');
    final shown = await pairing.startSeniorPairing(installId: 'senior-phone');

    final auth = InMemoryGuardianAuthRepository()
      ..seedSignedIn(const GuardianSession(userId: 'u1'));
    addTearDown(auth.dispose);
    await pumpApp(
      tester,
      overrides: [
        guardianAuthRepositoryProvider.overrideWithValue(auth),
        seniorLinkRepositoryProvider.overrideWithValue(store),
        pairingRepositoryProvider.overrideWithValue(pairing),
      ],
    );
    await tester.pumpAndSettle();

    // No parent yet, so the form is the one on 홈.
    await tester.tap(find.text('불러주신 번호 넣기'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(GuardianFamilyKeys.codeField),
      shown.code,
    );
    await tester.enterText(find.byKey(GuardianFamilyKeys.nameField), '어머니');
    await tester.tap(find.byKey(GuardianFamilyKeys.enterCode));
    await tester.pumpAndSettle();

    // The code could not carry either of these, which is why the form asks.
    expect(store.profiles.values.single.displayName, '어머니');
    expect(store.linkedProfileIds, hasLength(1));
  });

  testWidgets('a wrong code says so', (tester) async {
    await _pumpFamilyTab(tester);

    await tester.tap(find.text('불러주신 번호 넣기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(GuardianFamilyKeys.codeField), '9999');
    await tester.enterText(find.byKey(GuardianFamilyKeys.nameField), '어머니');
    await tester.tap(find.byKey(GuardianFamilyKeys.enterCode));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(GuardianFamilyKeys.message)).data,
      contains('연결 번호가 맞지 않'),
    );
  });

  testWidgets('recovery is offered once a parent exists', (tester) async {
    await _pumpFamilyTab(tester, withParent: true);

    expect(find.byKey(GuardianFamilyKeys.recovery), findsOneWidget);
    expect(find.text('부모님 폰 다시 연결하기'), findsOneWidget);
  });

  testWidgets(
    'a recovery code is issued on demand and says how long it lasts',
    (tester) async {
      await _pumpFamilyTab(tester, withParent: true);

      await tester.tap(find.text('연결 번호 만들기'));
      await tester.pumpAndSettle();

      expect(find.byKey(GuardianFamilyKeys.issuedCode), findsOneWidget);
      expect(find.textContaining('24시간'), findsOneWidget);
    },
  );

  testWidgets('inviting family is shown as free', (tester) async {
    // The PRD lists 가족 보호자 초대 among the free features; the uploaded
    // design had moved it behind 안심 케어.
    await _pumpFamilyTab(tester, withParent: true);

    expect(find.text('가족 초대하기'), findsOneWidget);
    expect(find.textContaining('무료'), findsWidgets);
  });

  testWidgets('the guardians looking after the parent are listed', (
    tester,
  ) async {
    // Phase 4 let a guardian read only their own link row. A guardian who
    // cannot see who else is looking after their parent cannot tell whether
    // the invite they sent was taken up.
    await _pumpFamilyTab(tester, withParent: true);

    expect(find.byKey(GuardianFamilyKeys.guardians), findsOneWidget);
    expect(find.textContaining('대표 보호자'), findsWidgets);
  });

  testWidgets('taking over as primary says the senior has to allow it', (
    tester,
  ) async {
    // A sibling who joined by invitation, so a handover is possible at all.
    await _pumpFamilyTab(tester, withParent: true, withSibling: true);

    expect(find.text('부모님 폰에서 허락하셔야 바뀝니다.'), findsOneWidget);
    expect(find.byKey(GuardianFamilyKeys.requestPrimary), findsOneWidget);
  });
}
