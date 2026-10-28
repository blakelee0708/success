import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/message_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/remote/subscription_repository.dart';
import 'package:app/domain/family_message.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/features/guardian/presentation/widgets/guardian_nav_bar.dart';
import 'package:app/features/messages/presentation/conversation_view.dart';

import '../../support/pump_app.dart';

/// What the guardian sees as the free allowance runs out.
///
/// It counted down to `메시지 0번, 사진 0장 더 보낼 수 있어요` - a sentence
/// that contradicts its own numbers - and then refused with a grey error line
/// carrying no way to act on it.
typedef Harness = ({
  InMemorySeniorLinkRepository store,
  InMemoryPairingRepository pairing,
  InMemorySubscriptionRepository subs,
  InMemoryMessageRepository messages,
  String profileId,
});

Future<Harness> _family({int texts = 0, int photos = 0}) async {
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
  for (var i = 0; i < texts; i++) {
    await messages.send(profile.id, body: '$i');
  }
  for (var i = 0; i < photos; i++) {
    await messages.send(profile.id, imagePath: '${profile.id}/$i.jpg');
  }
  return (
    store: store,
    pairing: pairing,
    subs: subs,
    messages: messages,
    profileId: profile.id,
  );
}

Future<void> _pumpMessages(WidgetTester tester, Harness h) async {
  final auth = InMemoryGuardianAuthRepository()
    ..seedSignedIn(const GuardianSession(userId: 'u1'));
  addTearDown(auth.dispose);
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
      guardianAuthRepositoryProvider.overrideWithValue(auth),
    ],
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(GuardianNavKeys.destination('메시지')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with room left it counts both numbers', (tester) async {
    final h = await _family();
    await _pumpMessages(tester, h);

    expect(
      find.text(
        '이번 달 메시지 ${MessageQuota.free.textLimit}번, '
        '사진 ${MessageQuota.free.imageLimit}장 더 보낼 수 있어요',
      ),
      findsOneWidget,
    );
    expect(find.byKey(ConversationKeys.quotaOffer), findsNothing);
  });

  testWidgets('spent, it stops counting and says so', (tester) async {
    final h = await _family(
      texts: MessageQuota.free.textLimit,
      photos: MessageQuota.free.imageLimit,
    );
    await _pumpMessages(tester, h);

    expect(find.textContaining('다 쓰셨어요'), findsWidgets);
    expect(find.textContaining('더 보낼 수 있어요'), findsNothing);
    expect(find.textContaining('0번'), findsNothing);
  });

  testWidgets('photos gone but messages left names both halves', (
    tester,
  ) async {
    // The case that made the line carry two numbers: a guardian whose photos
    // had run out was told they had plenty of sends and then refused.
    final h = await _family(photos: MessageQuota.free.imageLimit);
    await _pumpMessages(tester, h);

    expect(find.textContaining('사진을 다 쓰셨어요'), findsOneWidget);
    expect(
      find.textContaining('메시지는 ${MessageQuota.free.textLimit}번 남았어요'),
      findsOneWidget,
    );
  });

  testWidgets('spent, the offer is a button rather than grey text', (
    tester,
  ) async {
    final h = await _family(texts: MessageQuota.free.textLimit);
    await _pumpMessages(tester, h);

    expect(find.byKey(ConversationKeys.quotaOffer), findsOneWidget);
  });

  testWidgets('and it lands on 돌봄', (tester) async {
    final h = await _family(texts: MessageQuota.free.textLimit);
    await _pumpMessages(tester, h);

    await tester.tap(find.byKey(ConversationKeys.quotaOffer));
    await tester.pumpAndSettle();

    expect(find.byKey(ConversationKeys.field), findsNothing);
    expect(find.textContaining('안심 케어'), findsWidgets);
  });

  testWidgets('a spent send never reaches the server', (tester) async {
    // Checked before the round trip. The server refuses either way; what
    // this saves is a guardian watching their message vanish and then
    // reading a failure.
    final h = await _family(texts: MessageQuota.free.textLimit);
    await _pumpMessages(tester, h);
    final before = h.messages.byProfile[h.profileId]!.length;

    await tester.enterText(find.byKey(ConversationKeys.field), '엄마');
    await tester.tap(find.byKey(ConversationKeys.send));
    await tester.pumpAndSettle();

    expect(h.messages.byProfile[h.profileId], hasLength(before));
    expect(find.byKey(ConversationKeys.error), findsOneWidget);
  });

  testWidgets('읽음 확인 says why it is not there', (tester) async {
    // Paid, and until this line the guardian simply never saw a 읽음 mark
    // and had no way to learn why.
    final h = await _family();
    await _pumpMessages(tester, h);

    expect(find.byKey(ConversationKeys.readHint), findsOneWidget);
  });

  testWidgets('and stops once they have it', (tester) async {
    final h = await _family();
    await h.subs.startCare(h.profileId);
    await h.subs.resolveCareConsent(h.profileId, true);
    await _pumpMessages(tester, h);

    expect(find.byKey(ConversationKeys.readHint), findsNothing);
    expect(find.byKey(ConversationKeys.quotaOffer), findsNothing);
  });
}
