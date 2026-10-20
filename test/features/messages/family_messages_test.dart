import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/message_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/remote/subscription_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/presentation/widgets/home_strip.dart';
import 'package:app/features/messages/presentation/conversation_view.dart';

import '../../support/pump_app.dart';

typedef Harness = ({
  InMemorySeniorLinkRepository store,
  InMemoryPairingRepository pairing,
  InMemorySubscriptionRepository subs,
  InMemoryMessageRepository messages,
  String profileId,
});

Future<Harness> _family() async {
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
  return (
    store: store,
    pairing: pairing,
    subs: subs,
    messages: messages,
    profileId: profile.id,
  );
}

List<Object> _overrides(Harness h) => [
  seniorLinkRepositoryProvider.overrideWithValue(h.store),
  pairingRepositoryProvider.overrideWithValue(h.pairing),
  subscriptionRepositoryProvider.overrideWithValue(h.subs),
  messageRepositoryProvider.overrideWithValue(h.messages),
  homeAppsRepositoryProvider.overrideWithValue(InMemoryHomeAppsRepository()),
];

/// The guardian's 메시지 tab.
Future<void> _pumpGuardianMessages(WidgetTester tester, Harness h) async {
  final auth = InMemoryGuardianAuthRepository()
    ..seedSignedIn(const GuardianSession(userId: 'u1'));
  addTearDown(auth.dispose);
  await pumpApp(
    tester,
    overrides: [
      ..._overrides(h),
      guardianAuthRepositoryProvider.overrideWithValue(auth),
    ],
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('메시지'));
  await tester.pumpAndSettle();
}

/// The parent's phone, on 가족 메시지.
Future<void> _pumpSeniorMessages(WidgetTester tester, Harness h) async {
  h.messages.sendingAsSenior = true;
  await pumpApp(
    tester,
    overrides: [
      ..._overrides(h),
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
  // The conversation is reached from the band across the top of the home,
  // which shows the family's newest message. It used to be a button down by
  // 더 보기; the band replaced it and shows the message itself.
  await tester.tap(find.byKey(HomeStrip.stripKey));
  await tester.pumpAndSettle();
}

void main() {
  group('the quota', () {
    test('counts what the guardian sends', () async {
      final h = await _family();

      await h.messages.send(h.profileId, body: '엄마 밥 드셨어요?');

      expect((await h.messages.quota(h.profileId)).textUsed, 1);
    });

    test('never counts the parent replying', () async {
      // A launcher that stops an elderly person answering their daughter
      // because a monthly allowance ran out is selling the wrong thing.
      final h = await _family();
      h.messages.sendingAsSenior = true;

      await h.messages.send(h.profileId, body: '먹었다');

      expect((await h.messages.quota(h.profileId)).textUsed, 0);
    });

    test('the free limits are the PRD\'s', () async {
      final h = await _family();
      final quota = await h.messages.quota(h.profileId);

      expect(quota.textLimit, 50);
      expect(quota.imageLimit, 10);
      expect(quota.unlimited, isFalse);
    });

    test('the guardian is stopped once it is spent', () async {
      final h = await _family();
      for (var i = 0; i < 50; i++) {
        await h.messages.send(h.profileId, body: '$i');
      }

      await expectLater(
        h.messages.send(h.profileId, body: '하나 더'),
        throwsA(isA<MessageQuotaExceeded>()),
      );
    });

    test('the parent can still reply with the quota spent', () async {
      final h = await _family();
      for (var i = 0; i < 50; i++) {
        await h.messages.send(h.profileId, body: '$i');
      }

      h.messages.sendingAsSenior = true;
      final reply = await h.messages.send(h.profileId, body: '왜 답이 없니');

      expect(reply.isFromSenior, isTrue);
    });

    test('안심 케어 lifts it', () async {
      final h = await _family();
      await h.subs.startCare(h.profileId);
      await h.subs.resolveCareConsent(h.profileId, true);

      expect((await h.messages.quota(h.profileId)).unlimited, isTrue);
    });

    test('it warns before it runs out, not after', () async {
      final h = await _family();
      for (var i = 0; i < 46; i++) {
        await h.messages.send(h.profileId, body: '$i');
      }

      final quota = await h.messages.quota(h.profileId);
      expect(quota.textLeft, 4);
      expect(quota.isRunningLow, isTrue);
      expect(quota.canSendText, isTrue);
    });
  });

  group('the guardian tab', () {
    testWidgets('sends a message and shows it', (tester) async {
      final h = await _family();
      await _pumpGuardianMessages(tester, h);

      await tester.enterText(find.byKey(ConversationKeys.field), '엄마 밥 드셨어요?');
      await tester.tap(find.byKey(ConversationKeys.send));
      await tester.pumpAndSettle();

      expect(find.text('엄마 밥 드셨어요?'), findsOneWidget);
      expect(h.messages.byProfile[h.profileId], hasLength(1));
    });

    testWidgets('shows how many are left this month', (tester) async {
      final h = await _family();
      await _pumpGuardianMessages(tester, h);

      expect(find.text('이번 달 50번 더 보낼 수 있어요'), findsOneWidget);
    });

    testWidgets('offers 안심 케어 as it runs low, before it is stuck', (
      tester,
    ) async {
      final h = await _family();
      for (var i = 0; i < 47; i++) {
        await h.messages.send(h.profileId, body: '$i');
      }
      await _pumpGuardianMessages(tester, h);

      expect(find.text('이번 달 3번 더 보낼 수 있어요'), findsOneWidget);
      expect(find.textContaining('안심 케어를 시작하시면'), findsOneWidget);
    });

    testWidgets('says so plainly when the allowance is spent', (tester) async {
      final h = await _family();
      for (var i = 0; i < 50; i++) {
        await h.messages.send(h.profileId, body: '$i');
      }
      await _pumpGuardianMessages(tester, h);

      await tester.enterText(find.byKey(ConversationKeys.field), '하나 더');
      await tester.tap(find.byKey(ConversationKeys.send));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(ConversationKeys.error)).data,
        contains('이번 달 무료 메시지를 다 쓰셨어요'),
      );
    });

    testWidgets('an unlimited family is told so instead of a number', (
      tester,
    ) async {
      final h = await _family();
      await h.subs.startCare(h.profileId);
      await h.subs.resolveCareConsent(h.profileId, true);
      await _pumpGuardianMessages(tester, h);

      expect(find.textContaining('제한 없이'), findsOneWidget);
      expect(find.textContaining('더 보낼 수 있어요'), findsNothing);
    });
  });

  group('the parent’s phone', () {
    testWidgets('reaches the conversation from the home screen', (
      tester,
    ) async {
      // 04_SCREEN_SPEC gives this slot as 가족 연결 또는 자녀 이름 버튼: once a
      // family is attached, connecting is not what they need it for. The slot
      // is now the band at the top, which carries the name and the message.
      final h = await _family();
      await _pumpSeniorMessages(tester, h);

      expect(find.byKey(ConversationKeys.field), findsOneWidget);
    });

    testWidgets('is never shown a count of what their family may send', (
      tester,
    ) async {
      // The allowance is the guardian's to manage, and the senior's own
      // replies are not counted against it.
      final h = await _family();
      await _pumpSeniorMessages(tester, h);

      expect(find.byKey(ConversationKeys.quota), findsNothing);
      expect(find.textContaining('더 보낼 수 있어요'), findsNothing);
    });

    testWidgets('can reply', (tester) async {
      final h = await _family();
      await _pumpSeniorMessages(tester, h);

      await tester.enterText(find.byKey(ConversationKeys.field), '먹었다');
      await tester.tap(find.byKey(ConversationKeys.send));
      await tester.pumpAndSettle();

      expect(h.messages.byProfile[h.profileId]!.single.isFromSenior, isTrue);
    });

    testWidgets('the home button still connects when nobody is attached', (
      tester,
    ) async {
      final store = InMemorySeniorLinkRepository();
      final pairing = InMemoryPairingRepository(store);
      final subs = InMemorySubscriptionRepository(store);
      await pumpApp(
        tester,
        overrides: [
          seniorLinkRepositoryProvider.overrideWithValue(store),
          pairingRepositoryProvider.overrideWithValue(pairing),
          subscriptionRepositoryProvider.overrideWithValue(subs),
          messageRepositoryProvider.overrideWithValue(
            InMemoryMessageRepository(store, subscriptions: subs),
          ),
          homeAppsRepositoryProvider.overrideWithValue(
            InMemoryHomeAppsRepository(),
          ),
          seniorLinkStoreProvider.overrideWithValue(InMemorySeniorLinkStore()),
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

      expect(find.text('가족 연결'), findsOneWidget);
      expect(find.byKey(HomeStrip.connectKey), findsOneWidget);
      expect(find.byKey(HomeStrip.messageKey), findsNothing);
    });
  });
}
