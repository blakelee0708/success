import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/clock.dart';
import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/remote/subscription_repository.dart';
import 'package:app/domain/device_status.dart';
import 'package:app/domain/senior_device.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/features/guardian/presentation/guardian_dashboard_screen.dart';

import '../../support/pump_app.dart';

/// 안부 신호 and the battery are 안심 케어 from 2026-10-28, free for the
/// first week.
///
/// The screen has to say three different things, and conflating any two of
/// them is the failure worth guarding: **없음** (no phone has ever connected),
/// **말할 수 없음** (the week is over and nobody subscribed) and the readings
/// themselves. The middle one is an offer; the first is a fact about setup;
/// and rounding either into `아직 / 연결되기 전이에요` would have the card
/// telling a guardian their parent never set the phone up.
final _now = DateTime(2026, 10, 28, 15, 0);

typedef Harness = ({
  InMemorySeniorLinkRepository store,
  InMemoryPairingRepository pairing,
  InMemorySubscriptionRepository subs,
  String profileId,
});

Future<Harness> _family({
  bool visible = true,
  DateTime? trialEndsAt,
  bool careOn = false,
  bool withPhone = true,
}) async {
  final store = InMemorySeniorLinkRepository();
  final pairing = InMemoryPairingRepository(store);
  final subs = InMemorySubscriptionRepository(store);
  await store.ensureGuardianAccount(displayName: '영희');
  final started = await pairing.startSeniorPairing(installId: 'senior-phone');
  final profile = await pairing.claimSeniorPairingCode(
    code: started.code,
    displayName: '어머니',
  );
  if (withPhone) {
    store.attachDevice(profile.id, 'senior-phone', platform: 'Android');
    store.activeDeviceByProfile[profile.id] = SeniorDevice(
      id: 'device-1',
      installId: 'senior-phone',
      isActive: true,
      platform: 'Android',
      lastSeenAt: _now.subtract(const Duration(minutes: 3)),
      status: DeviceStatus(
        readAt: _now.subtract(const Duration(minutes: 3)),
        batteryPercent: 61,
        isCharging: false,
        ringer: RingerMode.normal,
      ),
    );
  } else {
    store.activeDeviceByProfile.remove(profile.id);
  }
  store.readingsVisible = visible;
  store.trialEndsAt = trialEndsAt;
  if (careOn) {
    await subs.startCare(profile.id);
    await subs.resolveCareConsent(profile.id, true);
  }
  return (store: store, pairing: pairing, subs: subs, profileId: profile.id);
}

Future<void> _pumpHome(WidgetTester tester, Harness h) async {
  final auth = InMemoryGuardianAuthRepository()
    ..seedSignedIn(const GuardianSession(userId: 'u1'));
  addTearDown(auth.dispose);
  await pumpApp(
    tester,
    overrides: [
      nowProvider.overrideWithValue(() => _now),
      seniorLinkRepositoryProvider.overrideWithValue(h.store),
      pairingRepositoryProvider.overrideWithValue(h.pairing),
      subscriptionRepositoryProvider.overrideWithValue(h.subs),
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

void main() {
  testWidgets('inside the week the readings are simply shown', (tester) async {
    final h = await _family(trialEndsAt: _now.add(const Duration(days: 3)));
    await _pumpHome(tester, h);

    expect(find.textContaining('방금'), findsWidgets);
    expect(find.text('61%'), findsOneWidget);
    expect(find.byKey(GuardianHomeKeys.lockedStatus), findsNothing);
  });

  testWidgets('and the week is counted down while it runs', (tester) async {
    // A free trial that stops on the eighth day with no warning reads as the
    // app breaking, and the guardian never connects the two - they were
    // never told there was a week.
    final h = await _family(trialEndsAt: _now.add(const Duration(days: 3)));
    await _pumpHome(tester, h);

    expect(find.byKey(GuardianHomeKeys.trial), findsOneWidget);
    expect(find.textContaining('3일 남았어요'), findsOneWidget);
  });

  testWidgets('the last day says 오늘까지, never 0일', (tester) async {
    final h = await _family(trialEndsAt: _now.add(const Duration(hours: 2)));
    await _pumpHome(tester, h);

    expect(find.textContaining('오늘까지'), findsOneWidget);
    expect(find.textContaining('0일'), findsNothing);
  });

  testWidgets('a subscriber is not counted down at anything', (tester) async {
    final h = await _family(
      careOn: true,
      trialEndsAt: _now.subtract(const Duration(days: 30)),
    );
    await _pumpHome(tester, h);

    expect(find.byKey(GuardianHomeKeys.trial), findsNothing);
    expect(find.text('61%'), findsOneWidget);
  });

  testWidgets('after the week it offers rather than reporting nothing', (
    tester,
  ) async {
    final h = await _family(
      visible: false,
      trialEndsAt: _now.subtract(const Duration(days: 2)),
    );
    await _pumpHome(tester, h);

    expect(find.text('안심 케어로 볼 수 있어요'), findsOneWidget);
    expect(find.byKey(GuardianHomeKeys.lockedStatus), findsOneWidget);
    expect(find.text('61%'), findsNothing);
  });

  testWidgets('withheld is never reported as a phone that never connected', (
    tester,
  ) async {
    // The whole reason the server returns nulls rather than no row. These
    // are the words `SeniorPresence` uses for a family with no phone, and
    // showing them here would tell a guardian their parent never set theirs
    // up - which is both false and unfixable from their end.
    final h = await _family(visible: false);
    await _pumpHome(tester, h);

    expect(find.textContaining('연결되기 전'), findsNothing);
  });

  testWidgets('withheld, the green dot is not lit', (tester) async {
    // It claims *now*. There is nothing to claim.
    final h = await _family(visible: false);
    await _pumpHome(tester, h);

    expect(find.textContaining('방금'), findsNothing);
  });

  testWidgets('a family with no phone still says so', (tester) async {
    // Not the same as withheld, and the one case that must keep its own
    // sentence - it is a fact about setup, and the guardian can act on it.
    final h = await _family(withPhone: false);
    await _pumpHome(tester, h);

    expect(find.text('안심 케어로 볼 수 있어요'), findsNothing);
    expect(find.textContaining('연결되기 전'), findsWidgets);
  });
}
