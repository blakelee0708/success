import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
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
_pumpDashboard(WidgetTester tester, {bool withPendingParent = false}) async {
  final auth = InMemoryGuardianAuthRepository()
    ..seedSignedIn(const GuardianSession(userId: 'u1', email: 'g@example.com'));
  addTearDown(auth.dispose);

  final links = InMemorySeniorLinkRepository()..pendingLinkConsent = true;
  await links.ensureGuardianAccount(displayName: '영희');
  final pairing = InMemoryPairingRepository(links);
  if (withPendingParent) {
    await links.createSeniorProfile(displayName: '엄마');
  }

  await pumpApp(
    tester,
    overrides: [
      guardianAuthRepositoryProvider.overrideWithValue(auth),
      seniorLinkRepositoryProvider.overrideWithValue(links),
      pairingRepositoryProvider.overrideWithValue(pairing),
    ],
  );
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
    await tester.tap(find.text('불러주신 번호 넣기'));
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
}
