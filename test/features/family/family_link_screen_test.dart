import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/features/family/presentation/family_link_screen.dart';
import 'package:app/features/onboarding/presentation/splash_screen.dart';

import '../../support/pump_app.dart';

typedef Harness = ({
  InMemorySeniorLinkRepository store,
  InMemoryPairingRepository pairing,
});

/// Walks the senior's route: splash → 정말 쉬운 화면 → 가족 연결.
Future<Harness> _gotoFamilyLink(WidgetTester tester, {Harness? existing}) async {
  final store = existing?.store ?? InMemorySeniorLinkRepository();
  final pairing = existing?.pairing ?? InMemoryPairingRepository(store);

  await pumpApp(
    tester,
    overrides: [
      seniorLinkRepositoryProvider.overrideWithValue(store),
      pairingRepositoryProvider.overrideWithValue(pairing),
      homeAppsRepositoryProvider.overrideWithValue(InMemoryHomeAppsRepository()),
      seniorLinkStoreProvider.overrideWithValue(InMemorySeniorLinkStore()),
    ],
  );
  // The hand is still swinging up for the first frames, and the tap target
  // rides with it.
  await settleSplashEntrance(tester);
  await tester.tap(find.byKey(SplashScreen.tapTargetKey));
  await settleAfterSplashTap(tester);
  await tester.tap(find.text('정말 쉬운 화면'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('가족 연결'));
  await tester.pumpAndSettle();

  return (store: store, pairing: pairing);
}

Future<void> _enterCode(WidgetTester tester, String code) async {
  await tester.enterText(find.byKey(FamilyLinkKeys.code), code);
  await tester.tap(find.byKey(FamilyLinkKeys.submit));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the screen offers both directions at once', (tester) async {
    // Which one applies is not something the senior should have to work out:
    // whether they are being connected for the first time or replacing a
    // phone is their child's business, not theirs.
    await _gotoFamilyLink(tester);

    expect(find.byKey(FamilyLinkKeys.showCode), findsOneWidget);
    expect(find.byKey(FamilyLinkKeys.code), findsOneWidget);
  });

  testWidgets('the phone shows a 4-digit code for the guardian to type', (
    tester,
  ) async {
    final h = await _gotoFamilyLink(tester);

    await tester.tap(find.byKey(FamilyLinkKeys.showCode));
    await tester.pumpAndSettle();

    final shown = tester.widget<Text>(find.byKey(FamilyLinkKeys.shownCode)).data!;
    expect(shown, hasLength(4));
    expect(h.pairing.issued.single.code, shown);
  });

  testWidgets('showing a code says it does not last', (tester) async {
    // The difference between a number that stopped working and a phone that
    // seems broken.
    await _gotoFamilyLink(tester);

    await tester.tap(find.byKey(FamilyLinkKeys.showCode));
    await tester.pumpAndSettle();

    expect(find.text('이 번호는 10분 동안만 쓸 수 있어요'), findsOneWidget);
  });

  testWidgets('showing a code creates the profile with no guardian involved', (
    tester,
  ) async {
    // Path A depends on the Play referrer surviving an install, so this has to
    // work before any guardian exists.
    final h = await _gotoFamilyLink(tester);

    await tester.tap(find.byKey(FamilyLinkKeys.showCode));
    await tester.pumpAndSettle();

    expect(h.store.profiles, hasLength(1));
  });

  testWidgets('showing a code does not claim the family has arrived', (
    tester,
  ) async {
    // Showing a code creates the profile, so "this phone has a profile" is not
    // the same question as "somebody is looking after this phone". Telling a
    // senior their family had connected when nobody had typed the number yet
    // would be a lie they have no way to check.
    await _gotoFamilyLink(tester);

    await tester.tap(find.byKey(FamilyLinkKeys.showCode));
    await tester.pumpAndSettle();

    expect(find.byKey(FamilyLinkKeys.connected), findsNothing);
    expect(find.byKey(FamilyLinkKeys.shownCode), findsOneWidget);
  });

  testWidgets('the screen notices by itself once a guardian claims it', (
    tester,
  ) async {
    // The senior has no way to know when their child finished typing, so
    // asking them to check would be asking the wrong person.
    final h = await _gotoFamilyLink(tester);
    await tester.tap(find.byKey(FamilyLinkKeys.showCode));
    await tester.pumpAndSettle();

    await h.pairing.claimSeniorPairingCode(
      code: h.pairing.issued.single.code,
      displayName: '어머니',
    );
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(find.byKey(FamilyLinkKeys.connected), findsOneWidget);
  });

  testWidgets('a wrong number says so and stays on the form', (tester) async {
    await _gotoFamilyLink(tester);

    await _enterCode(tester, '999999');

    expect(
      tester.widget<Text>(find.byKey(FamilyLinkKeys.message)).data,
      '연결 번호가 맞지 않거나 시간이 지났어요. 다시 확인해 주세요.',
    );
    expect(find.byKey(FamilyLinkKeys.submit), findsOneWidget);
  });

  testWidgets('a recovery number connects the phone', (tester) async {
    final store = InMemorySeniorLinkRepository();
    final pairing = InMemoryPairingRepository(store);
    // A parent who already exists, and whose phone is being replaced.
    final started = await pairing.startSeniorPairing(installId: 'old-phone');
    final profile = await pairing.claimSeniorPairingCode(
      code: started.code,
      displayName: '어머니',
    );
    final recovery = await pairing.createRecoveryCode(profile.id);

    await _gotoFamilyLink(tester, existing: (store: store, pairing: pairing));
    await _enterCode(tester, recovery.code);

    expect(find.byKey(FamilyLinkKeys.connected), findsOneWidget);
    expect(find.text('가족과 연결되었어요'), findsOneWidget);
  });

  testWidgets('an invite number connects the phone too', (tester) async {
    // The same field takes both — the senior was told "type this number", not
    // which kind of number it is.
    final store = InMemorySeniorLinkRepository();
    final pairing = InMemoryPairingRepository(store);
    final invite = await pairing.createSeniorInvite(displayName: '아버지');

    await _gotoFamilyLink(tester, existing: (store: store, pairing: pairing));
    await _enterCode(tester, invite.code);

    expect(find.byKey(FamilyLinkKeys.connected), findsOneWidget);
  });

  testWidgets('the field takes digits only', (tester) async {
    await _gotoFamilyLink(tester);

    await tester.enterText(find.byKey(FamilyLinkKeys.code), 'AB12 34!');
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byKey(FamilyLinkKeys.code)).controller!.text,
      '1234',
    );
  });
}
