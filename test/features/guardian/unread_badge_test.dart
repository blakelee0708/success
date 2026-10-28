import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/message_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/remote/subscription_repository.dart';
import 'package:app/features/guardian/presentation/widgets/guardian_nav_bar.dart';
import 'package:app/features/messages/presentation/family_message_prompt.dart';

import '../../support/pump_app.dart';

/// The guardian is told a count; the senior is handed a card.
///
/// They are different people in different situations and the app should not
/// pretend otherwise. The senior's launcher *is* their phone, they see it
/// dozens of times a day, and they do not go looking - so a card over it is
/// the only thing that reliably reaches them. The guardian is an adult with
/// an ordinary phone on which this is one app among many, so a card could
/// only ever appear once they had already opened the app, which is both late
/// and redundant.
///
/// What actually reaches the guardian when it matters is a push notification,
/// and it is not built. Until it is, a count is what the app can honestly
/// show. This is the exact opposite of the rule FCM follows for the senior,
/// for the same reason: a status-bar entry is the one place a senior who
/// cannot find their contacts app will not look, and the first place their
/// child will.
void main() {
  Future<({InMemoryMessageRepository messages, String profileId})>
  family() async {
    final store = InMemorySeniorLinkRepository();
    final pairing = InMemoryPairingRepository(store);
    final subs = InMemorySubscriptionRepository(store);
    final messages = InMemoryMessageRepository(store, subscriptions: subs);
    await store.ensureGuardianAccount(displayName: '영희');
    final started = await pairing.startSeniorPairing(installId: 'senior-phone');
    final profile = await pairing.claimSeniorPairingCode(
      code: started.code,
      displayName: '어머니',
    );
    _store = store;
    _pairing = pairing;
    _subs = subs;
    return (messages: messages, profileId: profile.id);
  }

  Future<void> pumpGuardian(
    WidgetTester tester,
    InMemoryMessageRepository m,
  ) async {
    final auth = InMemoryGuardianAuthRepository()
      ..seedSignedIn(const GuardianSession(userId: 'u1'));
    addTearDown(auth.dispose);
    await pumpApp(
      tester,
      overrides: [
        seniorLinkRepositoryProvider.overrideWithValue(_store!),
        pairingRepositoryProvider.overrideWithValue(_pairing!),
        subscriptionRepositoryProvider.overrideWithValue(_subs!),
        messageRepositoryProvider.overrideWithValue(m),
        homeAppsRepositoryProvider.overrideWithValue(
          InMemoryHomeAppsRepository(),
        ),
        guardianAuthRepositoryProvider.overrideWithValue(auth),
      ],
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the 메시지 tab counts what the parent said', (tester) async {
    final h = await family();
    h.messages.sendingAsSenior = true;
    await h.messages.send(h.profileId, body: '밥 잘 먹었다');
    await h.messages.send(h.profileId, body: '고맙다');
    h.messages.sendingAsSenior = false;

    await pumpGuardian(tester, h.messages);

    expect(find.byKey(GuardianNavKeys.badge('메시지')), findsOneWidget);
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('with nothing waiting there is no badge at all', (tester) async {
    // A zero badge is a mark that means nothing, and a bar that always wears
    // one stops being read.
    final h = await family();

    await pumpGuardian(tester, h.messages);

    expect(find.byKey(GuardianNavKeys.badge('메시지')), findsNothing);
  });

  testWidgets('and the guardian is never handed the senior’s card', (
    tester,
  ) async {
    final h = await family();
    h.messages.sendingAsSenior = true;
    await h.messages.send(h.profileId, body: '밥 잘 먹었다');
    h.messages.sendingAsSenior = false;

    await pumpGuardian(tester, h.messages);

    expect(find.byType(FamilyMessagePrompt), findsNothing);
  });
}

InMemorySeniorLinkRepository? _store;
InMemoryPairingRepository? _pairing;
InMemorySubscriptionRepository? _subs;
