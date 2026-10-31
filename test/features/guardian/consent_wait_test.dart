import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/app_config_repository.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/features/guardian/presentation/guardian_dashboard_screen.dart';
import 'package:app/features/guardian/presentation/guardian_family_tab.dart';

import '../../support/pump_app.dart';

/// The guardian's half of 가족 연결 동의, which is waiting.
///
/// **Neither end of this handshake is produced by anything the guardian
/// does.** They type the number their parent read out and then the answer
/// arrives on somebody else's phone, so there is no tap to hang a refresh on
/// and this half of the app has no equivalent of the launcher's check-in.
/// Both tests here are about learning that something happened elsewhere.
Future<
  ({InMemorySeniorLinkRepository links, InMemoryPairingRepository pairing})
>
_pumpDashboard(
  WidgetTester tester, {
  bool withPendingParent = false,
  bool withInvite = false,
  DateTime Function()? now,
  bool storeListed = false,
}) async {
  final auth = InMemoryGuardianAuthRepository()
    ..seedSignedIn(const GuardianSession(userId: 'u1', email: 'g@example.com'));
  addTearDown(auth.dispose);

  final links = InMemorySeniorLinkRepository()..pendingLinkConsent = true;
  await links.ensureGuardianAccount(displayName: '영희');
  final pairing = InMemoryPairingRepository(links, now: now ?? DateTime.now);
  if (withPendingParent) {
    await links.createSeniorProfile(displayName: '엄마');
  }
  if (withInvite) {
    // Issued in an earlier run of the app, so nothing on this phone holds
    // it any more - only the server does.
    await pairing.createSeniorInvite(displayName: '엄마');
  }

  await pumpApp(
    tester,
    overrides: [
      guardianAuthRepositoryProvider.overrideWithValue(auth),
      appConfigRepositoryProvider.overrideWithValue(
        InMemoryAppConfigRepository(AppConfig(storeListed: storeListed)),
      ),
      seniorLinkRepositoryProvider.overrideWithValue(links),
      pairingRepositoryProvider.overrideWithValue(pairing),
    ],
  );
  await tester.pumpAndSettle();
  // Tall enough that 내 계정 at the bottom is built rather than lazily left
  // out of the tree: what is tested is the content, not the scrolling.
  tester.view.physicalSize = const Size(390, 6400);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpAndSettle();
  return (links: links, pairing: pairing);
}

void main() {
  testWidgets('connecting a parent says 기다리고 있어요, not 없어요', (tester) async {
    // `linkedSeniorProfilesProvider` is active-only, so invalidating it alone
    // leaves the dashboard exactly as it was: 아직 연결된 부모님이 없어요, to
    // a guardian who has just connected one. The first thing they would do is
    // do it again - and the second attempt meets the family-plan gate, which
    // counts pending links, so they are told 가족 플랜이 필요해요 about their
    // first parent.
    final h = await _pumpDashboard(tester);
    expect(find.byKey(GuardianHomeKeys.noParent), findsOneWidget);

    // The code the parent read out, typed on the form the 홈 tab now carries.
    final started = await h.pairing.startSeniorPairing(
      installId: 'senior-phone',
    );
    await tester.tap(find.text('부모님이 불러주신\n번호 넣기'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(GuardianFamilyKeys.codeField),
      started.code,
    );
    await tester.enterText(find.byKey(GuardianFamilyKeys.nameField), '엄마');
    await tester.tap(find.byKey(GuardianFamilyKeys.enterCode));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianHomeKeys.waitingForConsent), findsOneWidget);
    expect(find.byKey(GuardianHomeKeys.noParent), findsNothing);
    expect(find.textContaining('엄마님 폰에 여쭤봤어요'), findsOneWidget);
  });

  testWidgets(
    'the card goes when the parent agrees, with nothing pressed here',
    (tester) async {
      // 허락하시면 바로 이어집니다 is the whole content of that card, and until
      // this poll existed it stayed up until the app was relaunched.
      final h = await _pumpDashboard(tester, withPendingParent: true);
      expect(find.byKey(GuardianHomeKeys.waitingForConsent), findsOneWidget);

      // The parent presses 허락합니다 on their own phone.
      final linkId = h.links.pendingLinks.values.single;
      await h.pairing.answerGuardianLink(linkId, approve: true);

      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      expect(find.byKey(GuardianHomeKeys.waitingForConsent), findsNothing);
      expect(find.byKey(GuardianHomeKeys.noParent), findsNothing);
    },
  );

  testWidgets('making the install number keeps it on screen, with both texts', (
    tester,
  ) async {
    // **The real-phone bug.** On the server issuing the invite writes a
    // waiting link, which moves 홈 onto this page - and this page had no
    // number on it, so the guardian came back from the messaging app to
    // nothing they could read out.
    final h = await _pumpDashboard(tester, storeListed: true);

    await tester.tap(find.byKey(GuardianFamilyKeys.openInviteForm));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(GuardianFamilyKeys.nameField), '엄마');
    await tester.tap(find.byKey(GuardianFamilyKeys.invite));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianHomeKeys.waitingForConsent), findsOneWidget);
    expect(find.text(h.pairing.issued.last.code), findsOneWidget);
    expect(find.byKey(GuardianFamilyKeys.sendInstallLink), findsOneWidget);
    expect(find.byKey(GuardianFamilyKeys.sendInviteCode), findsOneWidget);
    // Nothing is on the parent's screen yet, so the page may not say there is.
    expect(find.textContaining('화면이 떠 있어요'), findsNothing);
  });

  testWidgets('the number is still there after the app is reopened', (
    tester,
  ) async {
    final h = await _pumpDashboard(tester, withInvite: true);

    expect(find.text(h.pairing.issued.single.code), findsOneWidget);
    expect(find.byKey(GuardianFamilyKeys.sendInviteCode), findsOneWidget);
  });

  testWidgets('once the parent uses the number, the page asks about consent', (
    tester,
  ) async {
    final h = await _pumpDashboard(tester, withInvite: true);
    final code = h.pairing.issued.single.code;

    await h.pairing.redeemSeniorInvite(installId: 'senior-phone', code: code);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianHomeKeys.waitingForConsent), findsOneWidget);
    expect(find.text(code), findsNothing);
    expect(find.textContaining('엄마님 폰에 여쭤봤어요'), findsOneWidget);
  });

  testWidgets('a number that ran out says so, and makes a new one', (
    tester,
  ) async {
    // A week and nobody installed. This used to fall through to
    // 여쭤보는 화면이 떠 있어요 - about a parent with no app, so no screen -
    // and the waiting request held the one seat 1대1 allows.
    var clock = DateTime(2026, 10, 1);
    final h = await _pumpDashboard(tester, withInvite: true, now: () => clock);
    expect(find.text(h.pairing.issued.single.code), findsOneWidget);

    clock = clock.add(const Duration(days: 8));
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(find.text('설치 번호가 만료됐어요'), findsOneWidget);
    expect(find.textContaining('화면이 떠 있어요'), findsNothing);
    expect(find.byKey(GuardianFamilyKeys.sendInviteCode), findsNothing);

    await tester.tap(find.byKey(GuardianHomeKeys.reissueInvite));
    await tester.pumpAndSettle();

    expect(h.pairing.issued, hasLength(2));
    expect(find.text(h.pairing.issued.last.code), findsOneWidget);
    expect(find.text('설치 번호가 만료됐어요'), findsNothing);
    expect(h.links.pendingLinks, hasLength(1));
  });

  testWidgets('a waiting request can be taken back', (tester) async {
    // A wrong name or a change of mind: before this, 계정 삭제 was the only
    // way out, because the request held the guardian's one seat.
    final h = await _pumpDashboard(tester, withInvite: true);
    final profileId = h.pairing.issued.single.seniorProfileId!;

    await tester.tap(find.byKey(GuardianHomeKeys.withdrawRequest));
    await tester.pumpAndSettle();
    expect(find.byKey(GuardianHomeKeys.withdrawConfirm), findsOneWidget);
    await tester.tap(find.text('요청 취소하기'));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianHomeKeys.waitingForConsent), findsNothing);
    expect(find.byKey(GuardianHomeKeys.noParent), findsOneWidget);
    expect(h.links.pendingLinks, isEmpty);
    // The number cannot be spent later, and the profile that was only ever
    // this request is gone with it.
    expect(await h.pairing.openSeniorInvite(profileId), isNull);
    expect(h.links.profiles.containsKey(profileId), isFalse);
  });

  testWidgets('아니요, 기다릴게요 keeps the request', (tester) async {
    final h = await _pumpDashboard(tester, withInvite: true);

    await tester.tap(find.byKey(GuardianHomeKeys.withdrawRequest));
    await tester.pumpAndSettle();
    await tester.tap(find.text('아니요, 기다릴게요'));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianHomeKeys.waitingForConsent), findsOneWidget);
    expect(h.links.pendingLinks, hasLength(1));
  });

  testWidgets('a parent saying no is said, not silent', (tester) async {
    // The waiting page used to turn into 부모님 연결하기 with nothing on it
    // saying why, which reads as the app failing - and the first thing a
    // guardian does about that is try again.
    final h = await _pumpDashboard(tester);
    final started = await h.pairing.startSeniorPairing(
      installId: 'senior-phone',
    );
    await tester.tap(find.text('부모님이 불러주신\n번호 넣기'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(GuardianFamilyKeys.codeField),
      started.code,
    );
    await tester.enterText(find.byKey(GuardianFamilyKeys.nameField), '엄마');
    await tester.tap(find.byKey(GuardianFamilyKeys.enterCode));
    await tester.pumpAndSettle();
    expect(find.byKey(GuardianHomeKeys.waitingForConsent), findsOneWidget);

    await h.pairing.answerGuardianLink(
      h.links.pendingLinks.values.single,
      approve: false,
    );
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianHomeKeys.noParent), findsOneWidget);
    expect(find.textContaining('엄마님 · 연결되지 않았어요.'), findsOneWidget);
  });

  testWidgets('waiting still has 로그아웃 and 계정 삭제', (tester) async {
    // This page used to end at the card, found on a real phone.
    await _pumpDashboard(tester, withPendingParent: true);

    expect(find.byKey(GuardianHomeKeys.waitingForConsent), findsOneWidget);
    expect(find.byKey(GuardianFamilyKeys.signOut), findsOneWidget);
    expect(find.byKey(GuardianFamilyKeys.deleteAccount), findsOneWidget);
  });

  testWidgets('with no parent the page says what connecting is for', (
    tester,
  ) async {
    await _pumpDashboard(tester);

    expect(find.byKey(GuardianHomeKeys.noParent), findsOneWidget);
    expect(find.byKey(GuardianHomeKeys.promise), findsOneWidget);
    expect(find.text('연결하면 이렇게 도와드릴 수 있어요.'), findsOneWidget);
    expect(find.byKey(GuardianFamilyKeys.signOut), findsOneWidget);
    expect(find.byKey(GuardianFamilyKeys.deleteAccount), findsOneWidget);
    // Why connecting first, then the form, then the account.
    final promise = tester.getTopLeft(find.byKey(GuardianHomeKeys.promise));
    final form = tester.getTopLeft(
      find.byKey(GuardianFamilyKeys.openInviteForm),
    );
    final signOut = tester.getTopLeft(find.byKey(GuardianFamilyKeys.signOut));
    expect(promise.dy, lessThan(form.dy));
    expect(form.dy, lessThan(signOut.dy));
  });

  testWidgets('a parent cutting the link reaches an open dashboard', (
    tester,
  ) async {
    // **Resume alone was not enough**, found on two real phones: the parent
    // pressed 끊기 while their child had the dashboard open, and the child's
    // screen went on saying 연결됨 while every message was refused.
    final h = await _pumpDashboard(tester);
    final started = await h.pairing.startSeniorPairing(
      installId: 'senior-phone',
    );
    h.links.pendingLinkConsent = false;
    await tester.tap(find.text('부모님이 불러주신\n번호 넣기'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(GuardianFamilyKeys.codeField),
      started.code,
    );
    await tester.enterText(find.byKey(GuardianFamilyKeys.nameField), '엄마');
    await tester.tap(find.byKey(GuardianFamilyKeys.enterCode));
    await tester.pumpAndSettle();
    expect(find.byKey(GuardianHomeKeys.noParent), findsNothing);

    // The parent presses 끊기 on their own phone. Nothing is pressed here.
    await h.pairing.removeGuardianLink(h.links.guardianAccountId);
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianHomeKeys.noParent), findsOneWidget);
    expect(find.byKey(GuardianFamilyKeys.notice), findsOneWidget);
  });
}
