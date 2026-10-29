import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/family/presentation/link_consent_prompt.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/presentation/widgets/senior_notice_layer.dart';

import '../../support/pump_app.dart';

/// 가족 연결 동의 — the senior answers on their own phone.
///
/// **A guardian typed a number and was connected.** Nothing ever asked the
/// person whose phone it is: on the install-SMS path they did nothing at all,
/// and a sibling joining by invitation was never mentioned to their mother.
Future<
  ({InMemorySeniorLinkRepository store, InMemoryPairingRepository pairing})
>
_pumpSeniorHome(WidgetTester tester, {String? guardianName}) async {
  final store = InMemorySeniorLinkRepository();
  final pairing = InMemoryPairingRepository(store)
    ..store.pendingLinkConsent = true;
  if (guardianName != null) {
    await store.ensureGuardianAccount(displayName: guardianName);
  }
  final started = await pairing.startSeniorPairing(installId: 'senior-phone');
  final profile = await pairing.claimSeniorPairingCode(
    code: started.code,
    displayName: '어머니',
  );

  await pumpApp(
    tester,
    overrides: [
      seniorLinkRepositoryProvider.overrideWithValue(store),
      pairingRepositoryProvider.overrideWithValue(pairing),
      appLauncherProvider.overrideWithValue(FakeAppLauncher(defaultHome: true)),
      seniorLinkStoreProvider.overrideWithValue(
        InMemorySeniorLinkStore(
          SeniorLink(installId: 'senior-phone', seniorProfileId: profile.id),
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
  return (store: store, pairing: pairing);
}

void main() {
  testWidgets('the card names who is asking', (tester) async {
    // 가족 연결 요청이 있어요 tells a senior nothing they can act on, and with
    // two children a card that cannot name one asks somebody to agree to
    // they-do-not-know-who. The name is why every guardian is asked for one
    // before they ever see their dashboard.
    await _pumpSeniorHome(tester, guardianName: '영희');

    expect(find.byKey(LinkConsentPrompt.promptKey), findsOneWidget);
    expect(find.textContaining('영희님이'), findsOneWidget);
  });

  testWidgets('it covers the home until it is answered', (tester) async {
    await _pumpSeniorHome(tester, guardianName: '영희');

    // Drawn over the whole home rather than squeezed above the tiles: it has
    // to be answered, and it is answered by pressing one of two buttons.
    // The tiles are still in the tree underneath, so the layer is what is
    // asserted rather than their absence.
    expect(find.byKey(SeniorNoticeLayer.layerKey), findsOneWidget);
  });

  testWidgets('허락합니다 connects them and the card goes', (tester) async {
    final h = await _pumpSeniorHome(tester, guardianName: '영희');

    await tester.tap(find.byKey(LinkConsentPrompt.approveKey));
    await tester.pumpAndSettle();

    expect(find.byKey(LinkConsentPrompt.promptKey), findsNothing);
    expect(h.store.linkedProfileIds, hasLength(1));
    // And the home screen is uncovered.
    expect(find.byKey(SeniorNoticeLayer.layerKey), findsNothing);
  });

  testWidgets('아니요 leaves nobody connected', (tester) async {
    // Not final and not a punishment: the row is removed, the guardian can
    // ask again, and a 아니요 pressed by mistake must not lock a family out.
    // What it must not do is leave something a later query reads as a
    // connection.
    final h = await _pumpSeniorHome(tester, guardianName: '영희');

    await tester.tap(find.byKey(LinkConsentPrompt.declineKey));
    await tester.pumpAndSettle();

    expect(find.byKey(LinkConsentPrompt.promptKey), findsNothing);
    expect(h.store.linkedProfileIds, isEmpty);
  });

  testWidgets('a guardian with no name still gets a readable card', (
    tester,
  ) async {
    await _pumpSeniorHome(tester);

    expect(find.textContaining('가족이'), findsOneWidget);
    expect(find.textContaining('보호자님이'), findsNothing);
  });

  test(
    'the card says what connecting lets them do, in the senior\'s words',
    () {
      // Not 부모님의 홈 화면: the reader is the parent, and their own home
      // screen described in the third person is somebody else talking about
      // them. Every line is short enough to be a whole line - sixteen glyphs at
      // 20px in a 318px card.
      for (final line in LinkConsentPrompt.can) {
        expect(line, isNot(contains('부모님의')), reason: line);
        expect('· $line'.length, lessThanOrEqualTo(16), reason: line);
      }
    },
  );
}
