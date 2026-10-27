import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/message_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/remote/subscription_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/messages/presentation/family_message_prompt.dart';

import '../../support/pump_app.dart';

/// Two children write into one thread, so the parent has to be told which of
/// them said what.
///
/// The conversation is the family's, not each guardian's - the same decision
/// that makes the monthly allowance the family's, and for the same reason:
/// the parent is the one reading it. That is right, and it left a gap. Until
/// now every incoming bubble looked identical, so a mother with two children
/// could not tell 영희 from 철수 at all.
///
/// It is **not** fixed by putting two name buttons on the home screen. Both
/// would open the same conversation, which is a choice that chooses nothing.
void main() {
  Future<
    ({
      InMemorySeniorLinkRepository store,
      InMemoryPairingRepository pairing,
      InMemorySubscriptionRepository subs,
      InMemoryMessageRepository messages,
      String profileId,
    })
  >
  family({required List<String> children}) async {
    final store = InMemorySeniorLinkRepository();
    final pairing = InMemoryPairingRepository(store);
    final subs = InMemorySubscriptionRepository(store);
    final messages = InMemoryMessageRepository(store, subscriptions: subs);
    final started = await pairing.startSeniorPairing(installId: 'senior-phone');
    final profile = await pairing.claimSeniorPairingCode(
      code: started.code,
      displayName: '어머니',
    );
    // The first child is the one the pairing code attached; any sibling is
    // added the way a family invite would, which the twin models as another
    // row in the roster.
    for (var i = 0; i < children.length; i++) {
      final id = 'account-${i + 1}';
      if (i == 0) {
        await store.ensureGuardianAccount(displayName: children[i]);
      } else {
        store.rolesByProfile.putIfAbsent(profile.id, () => {})[id] = 'family';
      }
      store.guardianNames[id] = children[i];
      messages.sendingGuardianId = id;
      await messages.send(profile.id, body: '${children[i]} 입니다');
    }
    return (
      store: store,
      pairing: pairing,
      subs: subs,
      messages: messages,
      profileId: profile.id,
    );
  }

  Future<void> pumpSenior(WidgetTester tester, dynamic h) async {
    h.messages.sendingAsSenior = true;
    h.messages.readingAsSenior = true;
    await pumpApp(
      tester,
      overrides: [
        seniorLinkRepositoryProvider.overrideWithValue(h.store),
        pairingRepositoryProvider.overrideWithValue(h.pairing),
        subscriptionRepositoryProvider.overrideWithValue(h.subs),
        messageRepositoryProvider.overrideWithValue(h.messages),
        homeAppsRepositoryProvider.overrideWithValue(
          InMemoryHomeAppsRepository(),
        ),
        appLauncherProvider.overrideWithValue(
          FakeAppLauncher(defaultHome: true),
        ),
        seniorLinkStoreProvider.overrideWithValue(
          InMemorySeniorLinkStore(
            SeniorLink(installId: 'senior-phone', seniorProfileId: h.profileId),
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
    await tester.tap(find.byKey(FamilyMessagePrompt.openKey));
    await tester.pumpAndSettle();
  }

  testWidgets('with two children every bubble says who wrote it', (
    tester,
  ) async {
    final h = await family(children: ['영희', '철수']);
    await pumpSenior(tester, h);

    expect(find.text('영희'), findsWidgets);
    expect(find.text('철수'), findsWidgets);
  });

  testWidgets('with one child no bubble is labelled', (tester) async {
    // A name over every bubble when only one person can have sent it is
    // clutter, on a screen already scaled up for an ageing eye.
    final h = await family(children: ['영희']);
    await pumpSenior(tester, h);

    expect(find.text('영희 입니다'), findsOneWidget);
    expect(find.text('영희'), findsNothing);
  });
}
