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
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/messages/data/speech_reader.dart';
import 'package:app/features/messages/presentation/conversation_view.dart';

import '../../support/pump_app.dart';

/// 읽어드리기 — the app's own promise, one step past where bigger text stops
/// working. An eye that 1.7x no longer helps is not helped by 2x either; the
/// only thing left is sound.
typedef Harness = ({
  InMemorySeniorLinkRepository store,
  InMemoryMessageRepository messages,
  FakeSpeechReader speech,
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
  messages.sendingAsSenior = true;
  await messages.send(profile.id, body: '방금 먹었다.');
  messages.sendingAsSenior = false;
  return (
    store: store,
    messages: messages,
    speech: FakeSpeechReader(),
    profileId: profile.id,
  );
}

List<Object> _shared(Harness h) => [
  seniorLinkRepositoryProvider.overrideWithValue(h.store),
  messageRepositoryProvider.overrideWithValue(h.messages),
  speechReaderProvider.overrideWithValue(h.speech),
];

/// The parent's own phone, in 가족 메시지.
Future<void> _pumpSenior(WidgetTester tester, Harness h) async {
  h.messages.sendingAsSenior = true;
  h.messages.readingAsSenior = true;
  await pumpApp(
    tester,
    overrides: [
      ..._shared(h),
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
  await tester.tap(find.text('설정'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('가족 메시지'));
  await tester.pumpAndSettle();
}

/// The guardian's phone, on the 메시지 tab.
Future<void> _pumpGuardian(WidgetTester tester, Harness h) async {
  final auth = InMemoryGuardianAuthRepository()
    ..seedSignedIn(const GuardianSession(userId: 'u1'));
  addTearDown(auth.dispose);
  await pumpApp(
    tester,
    overrides: [..._shared(h), guardianAuthRepositoryProvider.overrideWithValue(auth)],
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('메시지'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the parent can hear what their child wrote', (tester) async {
    final h = await _family();
    await _pumpSenior(tester, h);

    final incoming = h.messages.byProfile[h.profileId]!
        .firstWhere((m) => !m.isFromSenior);
    await tester.tap(find.byKey(ConversationKeys.read(incoming.id)));
    await tester.pumpAndSettle();

    expect(h.speech.spoken, ['엄마, 점심 드셨어요?']);
  });

  testWidgets('their own messages are not read back to them', (tester) async {
    // Reading someone their own words back is noise, and on a screen this
    // size it would double the number of things to press.
    final h = await _family();
    await _pumpSenior(tester, h);

    final own = h.messages.byProfile[h.profileId]!
        .firstWhere((m) => m.isFromSenior);
    expect(find.byKey(ConversationKeys.read(own.id)), findsNothing);
  });

  testWidgets('the guardian gets no read button at all', (tester) async {
    // This is for an eye that bigger text stopped helping. The son or
    // daughter reading the other end does not have one.
    final h = await _family();
    await _pumpGuardian(tester, h);

    for (final m in h.messages.byProfile[h.profileId]!) {
      expect(find.byKey(ConversationKeys.read(m.id)), findsNothing);
    }
    expect(h.speech.spoken, isEmpty);
  });

  testWidgets('a phone with no voice installed still shows the message', (
    tester,
  ) async {
    // The channel is told, never awaited, and the real one swallows both
    // channel failures. Nothing on screen depends on a speaker.
    final h = await _family();
    await _pumpSenior(tester, h);

    expect(tester.takeException(), isNull);
    expect(find.text('엄마, 점심 드셨어요?'), findsOneWidget);
  });

  testWidgets('pressing it twice reads it twice', (tester) async {
    // A senior who did not catch it the first time presses again. Nothing
    // about that is an error.
    final h = await _family();
    await _pumpSenior(tester, h);

    final incoming = h.messages.byProfile[h.profileId]!
        .firstWhere((m) => !m.isFromSenior);
    await tester.tap(find.byKey(ConversationKeys.read(incoming.id)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ConversationKeys.read(incoming.id)));
    await tester.pumpAndSettle();

    expect(h.speech.spoken, hasLength(2));
  });
}
