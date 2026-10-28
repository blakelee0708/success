import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/remote/subscription_repository.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/features/guardian/application/home_edit_allowance.dart';
import 'package:app/features/guardian/presentation/guardian_launcher_tab.dart';
import 'package:app/features/guardian/presentation/widgets/guardian_nav_bar.dart';

import '../../support/pump_app.dart';

/// 자녀 폰에서 홈 화면 정리는 평생 2회.
///
/// The screen's job is to say the number **before** a save, not to report a
/// refusal after one. A guardian told only by an error has already arranged
/// their parent's screen and watched it snap back, and the app then has to
/// explain a failure where it could have made an offer.
///
/// **The senior's own phone is never limited**, and every line on this screen
/// says so. A guardian who reads only the number reads it as their mother's
/// home screen being frozen, which it is not.
typedef Harness = ({
  InMemorySeniorLinkRepository store,
  InMemoryPairingRepository pairing,
  InMemorySubscriptionRepository subs,
  InMemoryHomeAppsRepository apps,
  String profileId,
});

Future<Harness> _family({int used = 0, bool careOn = false}) async {
  final store = InMemorySeniorLinkRepository();
  final pairing = InMemoryPairingRepository(store);
  final subs = InMemorySubscriptionRepository(store);
  await store.ensureGuardianAccount(displayName: '영희');
  final started = await pairing.startSeniorPairing(installId: 'senior-phone');
  final profile = await pairing.claimSeniorPairingCode(
    code: started.code,
    displayName: '어머니',
  );
  store.setGuardianHomeEdits(profile.id, used);
  if (careOn) {
    await subs.startCare(profile.id);
    await subs.resolveCareConsent(profile.id, true);
  }
  return (
    store: store,
    pairing: pairing,
    subs: subs,
    apps: InMemoryHomeAppsRepository(),
    profileId: profile.id,
  );
}

Future<void> _pumpLauncherTab(WidgetTester tester, Harness h) async {
  final auth = InMemoryGuardianAuthRepository()
    ..seedSignedIn(const GuardianSession(userId: 'u1'));
  addTearDown(auth.dispose);
  await pumpApp(
    tester,
    overrides: [
      seniorLinkRepositoryProvider.overrideWithValue(h.store),
      pairingRepositoryProvider.overrideWithValue(h.pairing),
      subscriptionRepositoryProvider.overrideWithValue(h.subs),
      homeAppsRepositoryProvider.overrideWithValue(h.apps),
      guardianAuthRepositoryProvider.overrideWithValue(auth),
    ],
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(GuardianNavKeys.destination('홈 화면')));
  await tester.pumpAndSettle();
}

Future<void> _addAButton(WidgetTester tester) async {
  await tester.tap(find.byKey(GuardianLauncherKeys.add));
  await tester.pumpAndSettle();
  // 어떤 버튼인가요 first, then the name dialog it opens pre-filled.
  await tester.tap(find.text('전화').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('저장'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a fresh family is told how many they have', (tester) async {
    final h = await _family();
    await _pumpLauncherTab(tester, h);

    expect(find.byKey(GuardianLauncherTab.allowanceKey), findsOneWidget);
    expect(find.textContaining('무료로 2번 더'), findsOneWidget);
  });

  testWidgets('and that their parent is never limited', (tester) async {
    // The line that keeps the number from reading as a locked phone.
    final h = await _family();
    await _pumpLauncherTab(tester, h);

    expect(find.textContaining('부모님 폰에서는'), findsOneWidget);
  });

  testWidgets('the number goes down as they are spent', (tester) async {
    final h = await _family(used: 1);
    await _pumpLauncherTab(tester, h);

    expect(find.textContaining('무료로 1번 더'), findsOneWidget);
  });

  testWidgets('spent, it says so instead of counting down to nothing', (
    tester,
  ) async {
    final h = await _family(used: guardianHomeEditsFree);
    await _pumpLauncherTab(tester, h);

    expect(find.textContaining('다 쓰셨어요'), findsOneWidget);
    expect(find.textContaining('무료로 0번'), findsNothing);
  });

  testWidgets('a subscription hides the counter entirely', (tester) async {
    // A tally on a screen nobody can reach the end of is noise.
    final h = await _family(used: 5, careOn: true);
    await _pumpLauncherTab(tester, h);

    expect(find.byKey(GuardianLauncherTab.allowanceKey), findsNothing);
  });

  testWidgets('spent, an edit offers 안심 케어 rather than failing', (
    tester,
  ) async {
    // The whole point of the change. It was a snackbar reading
    // 바꾸지 못했어요. 인터넷 연결을 확인하고 - which is a fault, about the
    // wrong thing, and sends the guardian to check their wifi.
    final h = await _family(used: guardianHomeEditsFree);
    await _pumpLauncherTab(tester, h);
    await _addAButton(tester);

    expect(find.byKey(GuardianLauncherTab.upsellKey), findsOneWidget);
    expect(find.textContaining('인터넷 연결'), findsNothing);
    expect(find.byKey(GuardianLauncherTab.upsellCareKey), findsOneWidget);
  });

  testWidgets('and the refused edit never reaches the parent\'s phone', (
    tester,
  ) async {
    // Checked before the write rather than after it, so nothing was sent and
    // nothing has to be rolled back on the screen.
    final h = await _family(used: guardianHomeEditsFree);
    await _pumpLauncherTab(tester, h);
    await _addAButton(tester);

    expect(h.apps.replaceCount, 0);
  });

  testWidgets('the offer says what still works before what costs money', (
    tester,
  ) async {
    final h = await _family(used: guardianHomeEditsFree);
    await _pumpLauncherTab(tester, h);
    await _addAButton(tester);

    // Scoped to the sheet: the banner behind it says the same thing, which
    // is the point of both and makes an unscoped finder match twice.
    Finder inSheet(String text) => find.descendant(
      of: find.byKey(GuardianLauncherTab.upsellKey),
      matching: find.textContaining(text),
    );
    final free = tester.getRect(inSheet('부모님 폰에서는 언제든')).top;
    final paid = tester.getRect(inSheet('안심 케어를 시작하시면')).top;
    expect(free, lessThan(paid));
  });

  testWidgets('안심 케어 알아보기 lands on 돌봄', (tester) async {
    final h = await _family(used: guardianHomeEditsFree);
    await _pumpLauncherTab(tester, h);
    await _addAButton(tester);

    await tester.tap(find.byKey(GuardianLauncherTab.upsellCareKey));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianLauncherTab.upsellKey), findsNothing);
    expect(find.textContaining('안심 케어'), findsWidgets);
  });

  testWidgets('with an allowance left the edit goes through', (tester) async {
    final h = await _family(used: 1);
    await _pumpLauncherTab(tester, h);
    await _addAButton(tester);

    expect(find.byKey(GuardianLauncherTab.upsellKey), findsNothing);
    expect(h.apps.replaceCount, 1);
  });
}
