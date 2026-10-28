import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/message_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/remote/subscription_repository.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/features/messages/presentation/conversation_view.dart';

import '../../support/pump_app.dart';

/// The guardian's 메시지 tab, with a thread already in it.
Future<InMemoryMessageRepository> _pump(WidgetTester tester) async {
  final store = InMemorySeniorLinkRepository();
  final pairing = InMemoryPairingRepository(store);
  final subs = InMemorySubscriptionRepository(store);
  final messages = InMemoryMessageRepository(store, subscriptions: subs);
  await store.ensureGuardianAccount(displayName: '김보호');
  final started = await pairing.startSeniorPairing(installId: 'senior-phone');
  final profile = await pairing.claimSeniorPairingCode(
    code: started.code,
    displayName: '어머니',
  );
  await messages.send(profile.id, body: '첫째');
  await messages.send(profile.id, body: '둘째');

  final auth = InMemoryGuardianAuthRepository()
    ..seedSignedIn(const GuardianSession(userId: 'u1'));
  addTearDown(auth.dispose);
  await pumpApp(
    tester,
    overrides: [
      seniorLinkRepositoryProvider.overrideWithValue(store),
      pairingRepositoryProvider.overrideWithValue(pairing),
      subscriptionRepositoryProvider.overrideWithValue(subs),
      messageRepositoryProvider.overrideWithValue(messages),
      homeAppsRepositoryProvider.overrideWithValue(
        InMemoryHomeAppsRepository(),
      ),
      guardianAuthRepositoryProvider.overrideWithValue(auth),
    ],
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('메시지'));
  await tester.pumpAndSettle();
  return messages;
}

void main() {
  testWidgets('the newest message sits at the bottom, by the composer', (
    tester,
  ) async {
    // It was an ordinary list, so a short thread sat at the top of an empty
    // screen and a long one put the newest message below the fold with
    // nothing scrolling to it. Every messaging app this is modelled on pins
    // the newest just above where you type.
    await _pump(tester);

    final list = tester.widget<ListView>(find.byKey(ConversationKeys.list));
    expect(list.reverse, isTrue);

    // The order of the data is unchanged - oldest first - so the oldest has
    // to come out above the newest on screen.
    expect(
      tester.getCenter(find.text('첫째')).dy,
      lessThan(tester.getCenter(find.text('둘째')).dy),
    );
  });

  testWidgets('a short thread hangs off the bottom, not the top', (
    tester,
  ) async {
    await _pump(tester);

    final list = tester.getRect(find.byKey(ConversationKeys.list));
    final newest = tester.getRect(find.text('둘째'));
    // Nearer the composer than the heading: with two messages in a tall list
    // this is the whole difference between the two arrangements.
    expect(list.bottom - newest.bottom, lessThan(newest.top - list.top));
  });

  testWidgets('sending does not re-read the thread to find the message', (
    tester,
  ) async {
    // `send_family_message` returns the row it wrote. The screen used to
    // throw that away and read all two hundred rows back, so pressing 보내기
    // cost a second round trip before anything appeared - which is what it
    // felt like on a real phone.
    final messages = await _pump(tester);
    final before = messages.reads;

    await tester.enterText(find.byKey(ConversationKeys.field), '셋째');
    await tester.tap(find.byKey(ConversationKeys.send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('셋째'), findsOneWidget);
    expect(messages.reads, before);
  });
}
