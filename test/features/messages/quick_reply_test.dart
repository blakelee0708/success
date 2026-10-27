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
import 'package:app/features/messages/presentation/conversation_view.dart';

import 'package:app/features/messages/presentation/family_message_prompt.dart';

import '../../support/pump_app.dart';

/// 빠른 답장 — the three things a parent most often wants to say.
///
/// `전화 좀 줘` is the one this exists for. A parent who does not want to be a
/// bother will not compose a message and will not ring; they will press a
/// button that costs them nothing and explains itself. Typing is the part
/// that defeats them, and everything else on that screen assumes a keyboard.
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
  return (store: store, messages: messages, profileId: profile.id);
}

Future<void> _pumpSenior(WidgetTester tester, Harness h) async {
  // Which phone is sending is the server's answer in the real repository —
  // it reads `auth.uid()`. The fake has to be told, and forgetting leaves
  // the parent's own messages attributed to their guardian, counted against
  // the guardian's allowance and drawn on the wrong side of the screen.
  h.messages.sendingAsSenior = true;
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
  testWidgets('one press asks their child to call, with no typing', (
    tester,
  ) async {
    final h = await _family();
    await _pumpSenior(tester, h);

    await tester.tap(find.byKey(ConversationKeys.quickReply('전화 좀 줘')));
    await tester.pumpAndSettle();

    final sent = h.messages.byProfile[h.profileId]!.single;
    expect(sent.body, '전화 좀 줘');
    expect(sent.isFromSenior, isTrue);
  });

  testWidgets('all three are there and all three send', (tester) async {
    final h = await _family();
    await _pumpSenior(tester, h);

    for (final preset in ConversationView.quickReplies) {
      await tester.tap(find.byKey(ConversationKeys.quickReply(preset)));
      await tester.pumpAndSettle();
    }

    expect(
      h.messages.byProfile[h.profileId]!.map((m) => m.body),
      ConversationView.quickReplies,
    );
  });

  testWidgets('it does not disturb what they were typing', (tester) async {
    // A half-written message is work. Clearing it because they pressed a
    // preset would throw that away.
    final h = await _family();
    await _pumpSenior(tester, h);

    await tester.enterText(find.byKey(ConversationKeys.field), '오늘 저녁에');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ConversationKeys.quickReply('잘 있다')));
    await tester.pumpAndSettle();

    expect(find.text('오늘 저녁에'), findsOneWidget);
  });

  testWidgets('the guardian has none of them', (tester) async {
    // They have a keyboard and use it. Three ways to say less than they mean
    // is not a feature on that phone.
    final h = await _family();
    await _pumpGuardian(tester, h);

    for (final preset in ConversationView.quickReplies) {
      expect(find.byKey(ConversationKeys.quickReply(preset)), findsNothing);
    }
  });

  testWidgets('the allowance never blocks one', (tester) async {
    // The quota counts guardian messages only. A parent asking their child to
    // call is the last thing a monthly allowance may refuse.
    final h = await _family();
    h.messages.sendingAsSenior = false;
    for (var i = 0; i < 60; i++) {
      try {
        await h.messages.send(h.profileId, body: '안녕하세요 $i');
      } on Object {
        break;
      }
    }
    await _pumpSenior(tester, h);

    await tester.tap(find.byKey(ConversationKeys.quickReply('전화 좀 줘')));
    await tester.pumpAndSettle();

    expect(
      h.messages.byProfile[h.profileId]!.last.body,
      '전화 좀 줘',
    );
    expect(find.byKey(ConversationKeys.error), findsNothing);
  });
}
