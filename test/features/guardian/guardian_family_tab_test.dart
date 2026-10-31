import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/app_config_repository.dart';
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
  bool storeListed = false,
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
      appConfigRepositoryProvider.overrideWithValue(
        InMemoryAppConfigRepository(AppConfig(storeListed: storeListed)),
      ),
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

    expect(find.text('설치 문자\n부모님께 보내드리기'), findsOneWidget);
    expect(find.text('부모님이 불러주신\n번호 넣기'), findsOneWidget);
  });

  testWidgets('the fields wait for 연결 번호 만들기, and 발송하기 sends', (tester) async {
    // 2026-10-31, from the owner's mockup: one line and one button first,
    // so the guardian is not met by three empty boxes; the boxes come when
    // they ask for them, and the button under them is 발송하기.
    await _pumpFamilyTab(tester, pendingConsent: true);

    expect(
      find.text('부모님 폰에 잘보이네를 쉽게 설치하고\n연결할 수 있게 문자를 보내드려요'),
      findsOneWidget,
    );
    expect(find.byKey(GuardianFamilyKeys.nameField), findsNothing);
    expect(find.byKey(GuardianFamilyKeys.invite), findsNothing);

    await tester.tap(find.byKey(GuardianFamilyKeys.openInviteForm));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianFamilyKeys.nameField), findsOneWidget);
    expect(find.byKey(GuardianFamilyKeys.phoneField), findsOneWidget);
    expect(find.byKey(GuardianFamilyKeys.myPhoneOnConnect), findsOneWidget);
    expect(find.text('발송하기'), findsOneWidget);
    expect(find.textContaining('비워 두셔도'), findsNothing);
    expect(find.byKey(GuardianFamilyKeys.openInviteForm), findsNothing);
  });

  testWidgets('after 발송하기: the number, three steps, then a second try', (
    tester,
  ) async {
    // 2026-10-31, design 2 of the owner's two: the number in a box of its
    // own, what to ask the parent as three numbered steps, the consent in
    // one green line, and resending last.
    final h = await _pumpFamilyTab(tester, pendingConsent: true);

    await tester.tap(find.byKey(GuardianFamilyKeys.openInviteForm));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(GuardianFamilyKeys.nameField), '엄마');
    await tester.tap(find.byKey(GuardianFamilyKeys.invite));
    await tester.pumpAndSettle();

    expect(find.text('부모님께 연결 번호 문자를 보내드리세요'), findsOneWidget);
    // The parent's name is not in the heading any more.
    expect(find.textContaining('엄마께'), findsNothing);
    final code = h.pairing.issued.last.code;
    expect(find.text(code), findsOneWidget);
    expect(find.text('7일 동안 쓸 수 있어요'), findsOneWidget);
    expect(find.text('부모님께 이렇게 부탁해 주세요'), findsOneWidget);
    for (final step in const ['잘보이네 앱 설치하기', '가족 연결 버튼 누르기', '이 번호 입력하기']) {
      expect(find.text(step), findsOneWidget, reason: step);
    }
    expect(
      find.text('부모님이 허락하시면 런처 화면과 연결되어 스마트폰 사용을 도와드릴 수 있어요'),
      findsOneWidget,
    );
    expect(find.text('문자를 못 보내셨나요?'), findsOneWidget);

    double y(Finder f) => tester.getTopLeft(f).dy;
    expect(y(find.text(code)), lessThan(y(find.text('잘보이네 앱 설치하기'))));
    expect(
      y(find.text('이 번호 입력하기')),
      lessThan(y(find.byKey(GuardianFamilyKeys.sendInviteCode))),
    );
    // The old paragraph above the number is gone.
    expect(find.textContaining('설치하고 번호를 넣으시면'), findsNothing);
  });

  testWidgets('the invite never claims the message was sent', (tester) async {
    // The app can only hand the text to the messaging app, and cannot see what
    // happens next. Same rule as SOS: never claim an action the user still has
    // to take themselves.
    // **With no parent yet**, because the app is 1대1 and a guardian who
    // already has one cannot invite a second. The form is the same one
    // either way - 연결 관리 and the empty state on 홈 both draw it.
    final h = await _pumpFamilyTab(tester, pendingConsent: true);

    await tester.tap(find.byKey(GuardianFamilyKeys.openInviteForm));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(GuardianFamilyKeys.nameField), '아버지');
    await tester.tap(find.byKey(GuardianFamilyKeys.invite));
    await tester.pumpAndSettle();

    // The button is called 발송하기 on the owner's word (2026-10-31), so the
    // line under it says who presses send, and nothing says it went.
    expect(find.textContaining('보내기를 눌러 주세요'), findsWidgets);
    expect(find.textContaining('문자를 보냈'), findsNothing);
    expect(find.textContaining('발송했'), findsNothing);
    expect(h.pairing.issued.last.code, isNotEmpty);
  });

  testWidgets('the invite also shows the code, for a link that did not survive', (
    tester,
  ) async {
    // Path A depends on the Play install referrer, which only survives a store
    // install — so the fallback has to be in front of the guardian, not buried.
    // With no parent yet, because the app is 1대1.
    await _pumpFamilyTab(tester, pendingConsent: true);

    await tester.tap(find.byKey(GuardianFamilyKeys.openInviteForm));
    await tester.pumpAndSettle();
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
    final h = await _pumpFamilyTab(
      tester,
      pendingConsent: true,
      storeListed: true,
    );

    await tester.tap(find.byKey(GuardianFamilyKeys.openInviteForm));
    await tester.pumpAndSettle();
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

  testWidgets('before the app is on Play there is one text, the number', (
    tester,
  ) async {
    // The store link would open a page that does not exist yet. The
    // parent's app is installed by hand until launch day turns it on.
    final h = await _pumpFamilyTab(tester, pendingConsent: true);

    await tester.tap(find.byKey(GuardianFamilyKeys.openInviteForm));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(GuardianFamilyKeys.nameField), '아버지');
    await tester.tap(find.byKey(GuardianFamilyKeys.invite));
    await tester.pumpAndSettle();

    expect(find.text(h.pairing.issued.last.code), findsOneWidget);
    expect(find.byKey(GuardianFamilyKeys.sendInstallLink), findsNothing);
    expect(find.byKey(GuardianFamilyKeys.sendInviteCode), findsOneWidget);
    expect(find.text('문자 다시 보내기'), findsOneWidget);
    expect(find.textContaining('두 문자'), findsNothing);
  });

  testWidgets('a parent with no name is refused before anything is created', (
    tester,
  ) async {
    final h = await _pumpFamilyTab(tester);

    await tester.tap(find.byKey(GuardianFamilyKeys.openInviteForm));
    await tester.pumpAndSettle();
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
    await tester.tap(find.text('부모님이 불러주신\n번호 넣기'));
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

    await tester.tap(find.text('부모님이 불러주신\n번호 넣기'));
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
    expect(find.text('설치 문자\n부모님께 보내드리기'), findsNothing);
    expect(find.byKey(GuardianFamilyKeys.invite), findsNothing);
    expect(find.byKey(GuardianFamilyKeys.nameField), findsNothing);
    expect(find.byKey(GuardianFamilyKeys.codeField), findsOneWidget);
    expect(find.text('가족 초대하기'), findsNothing);
    expect(find.textContaining('대표 보호자'), findsNothing);
  });
}
