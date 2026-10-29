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
  bool pendingConsent = false,
}) async {
  final auth = InMemoryGuardianAuthRepository()
    ..seedSignedIn(const GuardianSession(userId: 'u1', email: 'g@example.com'));
  addTearDown(auth.dispose);

  final store = InMemorySeniorLinkRepository();
  final pairing = InMemoryPairingRepository(store);
  await store.ensureGuardianAccount(displayName: '김보호');
  if (withParent) {
    final started = await pairing.startSeniorPairing(installId: 'senior-phone');
    await pairing.claimSeniorPairingCode(
      code: started.code,
      displayName: '어머니',
    );
  }

  // As the server does it: a new link waits for the parent's answer, so
  // issuing an install number moves 홈 onto its waiting page. Off by default
  // because most of these tests are about the form, not the wait.
  store.pendingLinkConsent = pendingConsent;
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
    // **With no parent yet**, because the app is 1대1 and a guardian who
    // already has one cannot invite a second. The form is the same one
    // either way - 연결 관리 and the empty state on 홈 both draw it.
    final h = await _pumpFamilyTab(tester, pendingConsent: true);

    await tester.enterText(find.byKey(GuardianFamilyKeys.nameField), '아버지');
    await tester.tap(find.byKey(GuardianFamilyKeys.invite));
    await tester.pumpAndSettle();

    expect(
      find.text('아래 두 문자를 차례로 보내 주세요. 문자 앱이 열리면 보내기는 직접 눌러 주세요.'),
      findsOneWidget,
    );
    expect(find.textContaining('문자를 보냈'), findsNothing);
    expect(find.textContaining('발송'), findsNothing);
    expect(h.pairing.issued.last.code, isNotEmpty);
  });

  testWidgets('the invite also shows the code, for a link that did not survive', (
    tester,
  ) async {
    // Path A depends on the Play install referrer, which only survives a store
    // install — so the fallback has to be in front of the guardian, not buried.
    // With no parent yet, because the app is 1대1.
    await _pumpFamilyTab(tester, pendingConsent: true);

    await tester.enterText(find.byKey(GuardianFamilyKeys.nameField), '아버지');
    await tester.tap(find.byKey(GuardianFamilyKeys.invite));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianFamilyKeys.issuedCode), findsOneWidget);
  });

  testWidgets('the number comes first, and each text is its own button', (
    tester,
  ) async {
    // **Found on real phones.** The button used to open the messaging app
    // at once with one text carrying both the link and the number, so the
    // guardian never saw the number here - and the parent could not find it
    // in the third line of a message under a two-line link.
    final h = await _pumpFamilyTab(tester, pendingConsent: true);

    await tester.enterText(find.byKey(GuardianFamilyKeys.nameField), '아버지');
    await tester.tap(find.byKey(GuardianFamilyKeys.invite));
    await tester.pumpAndSettle();

    final code = h.pairing.issued.last.code;
    expect(find.text(code), findsOneWidget);
    expect(find.byKey(GuardianFamilyKeys.sendInstallLink), findsOneWidget);
    expect(find.byKey(GuardianFamilyKeys.sendInviteCode), findsOneWidget);
    // The button that made it gives way, so a second press cannot make a
    // second parent.
    expect(find.byKey(GuardianFamilyKeys.invite), findsNothing);
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
    // The form sits under 연결하면 이렇게 도와드릴 수 있어요 now, below the
    // fold of a phone-sized viewport.
    tester.view.physicalSize = const Size(390, 6400);
    addTearDown(tester.view.resetPhysicalSize);
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

      // Inside the recovery card: the connect form's own button says the
      // same words, because it makes the same kind of thing.
      await tester.tap(
        find.descendant(
          of: find.byKey(GuardianFamilyKeys.recovery),
          matching: find.text('연결 번호 만들기'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GuardianFamilyKeys.issuedCode), findsOneWidget);
      expect(find.textContaining('24시간'), findsOneWidget);
    },
  );

  testWidgets('with a parent, the form only takes their new phone\'s number', (
    tester,
  ) async {
    // 무조건 자녀 하나, 부모 하나. Once a parent is connected there is no
    // install text to send and no second parent to name - the card is the
    // phone-change question and nothing else.
    await _pumpFamilyTab(tester, withParent: true);

    expect(find.text('부모님이 폰을 바꾸셨나요?'), findsOneWidget);
    expect(find.text('설치 문자 보내기'), findsNothing);
    expect(find.byKey(GuardianFamilyKeys.invite), findsNothing);
    expect(find.byKey(GuardianFamilyKeys.nameField), findsNothing);
    expect(find.byKey(GuardianFamilyKeys.codeField), findsOneWidget);
    expect(find.text('가족 초대하기'), findsNothing);
    expect(find.textContaining('대표 보호자'), findsNothing);
  });
}
