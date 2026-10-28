import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/family/presentation/primary_guardian_prompt.dart';

import '../../support/pump_app.dart';

/// A senior phone already connected to a family with two guardians, where the
/// sibling has asked to take over.
Future<
  ({InMemorySeniorLinkRepository store, InMemoryPairingRepository pairing})
>
_pumpHomeWithRequest(WidgetTester tester, {bool requested = true}) async {
  final store = InMemorySeniorLinkRepository();
  final pairing = InMemoryPairingRepository(store);

  final started = await pairing.startSeniorPairing(installId: 'senior-phone');
  final profile = await pairing.claimSeniorPairingCode(
    code: started.code,
    displayName: '어머니',
  );
  final invite = await pairing.createFamilyInvite(profile.id);
  pairing.actingGuardianId = 'sibling';
  await pairing.redeemFamilyInvite(invite.code);
  if (requested) await pairing.requestPrimaryGuardian(profile.id);
  pairing.actingGuardianId = 'account-1';

  await pumpApp(
    tester,
    overrides: [
      seniorLinkRepositoryProvider.overrideWithValue(store),
      pairingRepositoryProvider.overrideWithValue(pairing),
      homeAppsRepositoryProvider.overrideWithValue(
        InMemoryHomeAppsRepository(),
      ),
      seniorLinkStoreProvider.overrideWithValue(
        InMemorySeniorLinkStore(
          SeniorLink(installId: 'senior-phone', seniorProfileId: profile.id),
        ),
      ),
    ],
    // A phone that has been connected has already chosen a mode, so it opens
    // straight onto the home the prompt has to appear on.
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
  testWidgets('the senior is asked on their own home screen', (tester) async {
    // A senior may never open 가족 연결, and their answer is what decides it.
    await _pumpHomeWithRequest(tester);

    expect(find.byKey(PrimaryGuardianPrompt.promptKey), findsOneWidget);
    expect(find.text('가족 한 분이 대표 보호자를\n맡겠다고 하십니다'), findsOneWidget);
  });

  testWidgets('nothing is shown when nobody has asked', (tester) async {
    await _pumpHomeWithRequest(tester, requested: false);

    expect(find.byKey(PrimaryGuardianPrompt.promptKey), findsNothing);
  });

  testWidgets('the question offers a refusal as plainly as an approval', (
    tester,
  ) async {
    await _pumpHomeWithRequest(tester);

    expect(find.byKey(PrimaryGuardianPrompt.declineKey), findsOneWidget);
    expect(find.byKey(PrimaryGuardianPrompt.approveKey), findsOneWidget);
  });

  testWidgets('approving moves who speaks for them', (tester) async {
    final h = await _pumpHomeWithRequest(tester);

    await tester.tap(find.byKey(PrimaryGuardianPrompt.approveKey));
    await tester.pumpAndSettle();

    final profileId = h.store.profiles.keys.single;
    expect(h.store.rolesByProfile[profileId]!['sibling'], 'primary');
    expect(h.store.rolesByProfile[profileId]!['account-1'], 'family');
    expect(find.byKey(PrimaryGuardianPrompt.promptKey), findsNothing);
  });

  testWidgets('refusing leaves it where it was', (tester) async {
    final h = await _pumpHomeWithRequest(tester);

    await tester.tap(find.byKey(PrimaryGuardianPrompt.declineKey));
    await tester.pumpAndSettle();

    final profileId = h.store.profiles.keys.single;
    expect(h.store.rolesByProfile[profileId]!['account-1'], 'primary');
    expect(find.byKey(PrimaryGuardianPrompt.promptKey), findsNothing);
  });
}
