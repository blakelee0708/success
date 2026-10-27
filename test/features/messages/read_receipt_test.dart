import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/message_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/remote/subscription_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/domain/family_message.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/messages/presentation/conversation_view.dart';

import 'package:app/features/messages/presentation/family_message_prompt.dart';

import '../../support/pump_app.dart';

/// 읽음 확인 — what is left of the reassurance 위치 확인 was going to sell,
/// and the better half of it. `어머니가 내 메시지를 읽으셨다` is decent
/// evidence a parent is all right, and unlike a location it is something
/// **they did** rather than something taken from them.
typedef Harness = ({
  InMemorySeniorLinkRepository store,
  InMemoryMessageRepository messages,
  String profileId,
});

Future<Harness> _family() async {
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
  await messages.send(profile.id, body: '엄마, 점심 드셨어요?');
  return (store: store, messages: messages, profileId: profile.id);
}

Future<void> _pumpSenior(WidgetTester tester, Harness h) async {
  h.messages.sendingAsSenior = true;
  h.messages.readingAsSenior = true;
  await pumpApp(
    tester,
    overrides: [
      seniorLinkRepositoryProvider.overrideWithValue(h.store),
      messageRepositoryProvider.overrideWithValue(h.messages),
      appLauncherProvider.overrideWithValue(FakeAppLauncher(defaultHome: true)),
      seniorLinkStoreProvider.overrideWithValue(
        InMemorySeniorLinkStore(
          SeniorLink(installId: 'senior-phone', seniorProfileId: h.profileId),
        ),
      ),
    ],
    prefs: {
      SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
        const SeniorSettings(
          screenMode: ScreenMode.detailed,
          apps: defaultDetailedApps,
        ).toJson(),
      ),
    },
  );
  await tester.pumpAndSettle();
  // An unread message covers the home, so that card is the way in whenever
  // there is one — which is what it is for. 설정 → 가족 메시지 is still there
  // underneath for a conversation with nothing waiting in it.
  if (find.byKey(FamilyMessagePrompt.openKey).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(FamilyMessagePrompt.openKey));
    await tester.pumpAndSettle();
  } else {
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('가족 메시지'));
    await tester.pumpAndSettle();
  }
}

Future<void> _pumpGuardian(WidgetTester tester, Harness h) async {
  h.messages.readingAsSenior = false;
  final auth = InMemoryGuardianAuthRepository()
    ..seedSignedIn(const GuardianSession(userId: 'u1'));
  addTearDown(auth.dispose);
  await pumpApp(
    tester,
    overrides: [
      seniorLinkRepositoryProvider.overrideWithValue(h.store),
      messageRepositoryProvider.overrideWithValue(h.messages),
      guardianAuthRepositoryProvider.overrideWithValue(auth),
    ],
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('메시지'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opening the conversation is what reading it means', (
    tester,
  ) async {
    final h = await _family();
    expect(h.messages.byProfile[h.profileId]!.single.isRead, isFalse);

    await _pumpSenior(tester, h);

    expect(h.messages.byProfile[h.profileId]!.single.isRead, isTrue);
  });

  testWidgets('the guardian then sees 읽음 on their own message', (
    tester,
  ) async {
    final h = await _family();
    await _pumpSenior(tester, h);
    final id = h.messages.byProfile[h.profileId]!.single.id;

    await _pumpGuardian(tester, h);

    expect(find.byKey(ConversationKeys.readMark(id)), findsOneWidget);
    expect(find.text('읽음'), findsOneWidget);
  });

  testWidgets('before it is read there is no mark at all', (tester) async {
    // Deliberately no 안 읽음. A mark counting how long a parent has left a
    // message unopened teaches a guardian to nag.
    final h = await _family();
    final id = h.messages.byProfile[h.profileId]!.single.id;

    await _pumpGuardian(tester, h);

    expect(find.byKey(ConversationKeys.readMark(id)), findsNothing);
    expect(find.textContaining('안 읽'), findsNothing);
  });

  testWidgets('the parent is never shown whether their child read them', (
    tester,
  ) async {
    // One direction only. A senior watching an unread mark on a message to a
    // busy adult is the unkindest thing this app could put on a screen.
    final h = await _family();
    h.messages.sendingAsSenior = true;
    await h.messages.send(h.profileId, body: '잘 있다');
    h.messages.readingAsSenior = false;
    await h.messages.markRead(h.profileId);

    await _pumpSenior(tester, h);

    expect(find.text('읽음'), findsNothing);
  });

  testWidgets('nobody marks their own message read', (tester) async {
    // The guardian opening their own tab must not mark what they sent.
    final h = await _family();

    await _pumpGuardian(tester, h);

    expect(h.messages.byProfile[h.profileId]!.single.isRead, isFalse);
  });

  test('a receipt survives the wire', () {
    final row = {
      'id': 'm1',
      'created_at': '2026-08-01T10:00:00Z',
      'body': '안녕',
      'sender_guardian_id': 'g1',
      'read_at': '2026-08-01T12:00:00Z',
    };
    final back = FamilyMessage.fromRow(row)!;
    expect(back.isRead, isTrue);
    expect(back.readAt!.toUtc().hour, 12);
  });
}
