import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/ring_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/remote/subscription_repository.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/features/care/presentation/ring_sheet.dart';
import 'package:app/features/guardian/presentation/guardian_dashboard_screen.dart';

import '../../support/pump_app.dart';

/// 소리 울리기 from the side that presses the button.
///
/// It is a paid capability, so the card is not on the guardian's home until
/// there is a subscription **and** the senior has agreed. The gate would
/// refuse the ring either way; what is worth avoiding is a button that looks
/// pressable and cannot work.
typedef Harness = ({
  InMemorySeniorLinkRepository store,
  InMemoryPairingRepository pairing,
  InMemorySubscriptionRepository subs,
  InMemoryRingRepository ring,
  String profileId,
});

Future<Harness> _family({bool careOn = false}) async {
  final store = InMemorySeniorLinkRepository();
  final pairing = InMemoryPairingRepository(store);
  final subs = InMemorySubscriptionRepository(store);
  await store.ensureGuardianAccount(displayName: '김보호');
  final started = await pairing.startSeniorPairing(installId: 'senior-phone');
  final profile = await pairing.claimSeniorPairingCode(
    code: started.code,
    displayName: '어머니',
  );
  if (careOn) {
    await subs.startCare(profile.id);
    // Paying is not enough, and that is the point of the second call: a paid
    // subscription with no consent has to behave exactly like no
    // subscription.
    await subs.resolveCareConsent(profile.id, true);
  }
  return (
    store: store,
    pairing: pairing,
    subs: subs,
    ring: InMemoryRingRepository(),
    profileId: profile.id,
  );
}

Future<void> _pumpDashboard(WidgetTester tester, Harness h) async {
  final auth = InMemoryGuardianAuthRepository()
    ..seedSignedIn(const GuardianSession(userId: 'u1'));
  addTearDown(auth.dispose);
  await pumpApp(
    tester,
    overrides: [
      seniorLinkRepositoryProvider.overrideWithValue(h.store),
      pairingRepositoryProvider.overrideWithValue(h.pairing),
      subscriptionRepositoryProvider.overrideWithValue(h.subs),
      ringRepositoryProvider.overrideWithValue(h.ring),
      homeAppsRepositoryProvider.overrideWithValue(
        InMemoryHomeAppsRepository(),
      ),
      guardianAuthRepositoryProvider.overrideWithValue(auth),
    ],
  );
  await tester.pumpAndSettle();
  tester.view.physicalSize = const Size(390, 2600);
  await tester.pumpAndSettle();
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(GuardianHomeKeys.ring));
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester) async {
  await tester.tap(find.byKey(RingSheet.sendKey));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('without 안심 케어 the card still advertises it', (tester) async {
    final h = await _family();
    await _pumpDashboard(tester, h);

    expect(find.byKey(GuardianHomeKeys.care), findsOneWidget);
    expect(find.byKey(GuardianHomeKeys.ring), findsNothing);
  });

  testWidgets('with 안심 케어 the same slot becomes 소리 울리기', (tester) async {
    // The grid stays 2x2. A fifth card would leave a hole in it, and a
    // locked sixth would advertise what the buyer has already answered.
    final h = await _family(careOn: true);
    await _pumpDashboard(tester, h);

    expect(find.byKey(GuardianHomeKeys.ring), findsOneWidget);
    expect(find.byKey(GuardianHomeKeys.care), findsNothing);
  });

  testWidgets('a blank message is sent as nothing, not as an empty string', (
    tester,
  ) async {
    // The gate substitutes 전화 한 번만 주세요. for a blank, and that default
    // belongs next to the rule rather than in two places.
    final h = await _family(careOn: true);
    await _pumpDashboard(tester, h);
    await _openSheet(tester);
    await _send(tester);

    expect(h.ring.calls, hasLength(1));
    expect(h.ring.calls.single.seniorProfileId, h.profileId);
    expect(h.ring.calls.single.message, isNull);
  });

  testWidgets('a chip fills the box and the box is what gets sent', (
    tester,
  ) async {
    final h = await _family(careOn: true);
    await _pumpDashboard(tester, h);
    await _openSheet(tester);

    await tester.tap(find.text(RingSheet.phrases[1]));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(RingSheet.fieldKey), '엄마 어디세요?');
    await _send(tester);

    expect(h.ring.calls.single.message, '엄마 어디세요?');
  });

  testWidgets('a ring that worked says so', (tester) async {
    final h = await _family(careOn: true);
    await _pumpDashboard(tester, h);
    await _openSheet(tester);
    await _send(tester);

    expect(find.byKey(RingSheet.resultKey), findsOneWidget);
    expect(find.textContaining('울렸어요'), findsOneWidget);
  });

  testWidgets('the four outcomes are four different sentences', (tester) async {
    // Silence is the one answer that makes a worried guardian press again,
    // and a phone that was never connected is not the same news as a sender
    // that is broken.
    final seen = <String>{};
    for (final outcome in <RingOutcome>[
      const RingSent(),
      const RingMissed(RingMiss.neverConnected),
      const RingMissed(RingMiss.unreachable),
      const RingRefused('안심 케어가 켜져 있어야 보낼 수 있어요.'),
      const RingSenderDown(),
    ]) {
      final h = await _family(careOn: true);
      h.ring.outcome = outcome;
      await _pumpDashboard(tester, h);
      await _openSheet(tester);
      await _send(tester);

      final said = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(RingSheet.resultKey),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data)
          .whereType<String>()
          .join();
      expect(said, isNotEmpty, reason: '$outcome said nothing');
      seen.add(said);
    }
    expect(seen, hasLength(5));
  });

  testWidgets('the gate refusal is shown in the server\'s own words', (
    tester,
  ) async {
    // Rewording it here would put the rule's explanation in two places, and
    // the copy a guardian reads would be the one no test can reach.
    final h = await _family(careOn: true);
    h.ring.outcome = const RingRefused('이 부모님의 보호자가 아니에요.');
    await _pumpDashboard(tester, h);
    await _openSheet(tester);
    await _send(tester);

    expect(find.text('이 부모님의 보호자가 아니에요.'), findsOneWidget);
  });

  testWidgets('a result from last time is gone when it opens again', (
    tester,
  ) async {
    final h = await _family(careOn: true);
    await _pumpDashboard(tester, h);
    await _openSheet(tester);
    await _send(tester);
    expect(find.byKey(RingSheet.resultKey), findsOneWidget);

    // Back to the dashboard, and in again.
    await tester.tapAt(const Offset(195, 60));
    await tester.pumpAndSettle();
    await _openSheet(tester);

    expect(find.byKey(RingSheet.resultKey), findsNothing);
  });
}
