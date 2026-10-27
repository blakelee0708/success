import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/message_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/remote/subscription_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/presentation/widgets/senior_notice_layer.dart';
import 'package:app/features/messages/presentation/conversation_view.dart';
import 'package:app/features/messages/presentation/family_message_prompt.dart';

import '../../support/pump_app.dart';

/// A message from the family, over the whole home screen.
///
/// A quiet mark beside a button is read by somebody who already knows to look
/// for it, and the person this app is for is the person who does not.
typedef Harness = ({
  InMemorySeniorLinkRepository store,
  InMemoryMessageRepository messages,
  String profileId,
});

Future<Harness> _family({String? say}) async {
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
  if (say != null) await messages.send(profile.id, body: say);
  return (store: store, messages: messages, profileId: profile.id);
}

Future<void> _pumpHome(WidgetTester tester, Harness h) async {
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
          screenMode: ScreenMode.easy,
          apps: defaultEasyApps,
        ).toJson(),
      ),
    },
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an unread message covers the home and names who sent it', (
    tester,
  ) async {
    final h = await _family(say: '엄마, 점심 드셨어요?');
    await _pumpHome(tester, h);

    expect(find.text('영희님이 보냈어요'), findsOneWidget);
    expect(find.text('엄마, 점심 드셨어요?'), findsOneWidget);
    // Drawn in the layer that covers the home, rather than squeezed in above
    // the grid - which is what the two consent cards learned the hard way.
    // The tiles stay in the tree underneath; what matters is that the layer
    // is painted over them.
    expect(find.byKey(SeniorNoticeLayer.layerKey), findsOneWidget);
  });

  testWidgets('with nothing unread the home is the home', (tester) async {
    final h = await _family();
    await _pumpHome(tester, h);

    expect(find.byType(FamilyMessagePrompt), findsNothing);
    expect(find.byKey(SeniorNoticeLayer.layerKey), findsNothing);
  });

  testWidgets('읽어 보기 opens the conversation', (tester) async {
    final h = await _family(say: '엄마, 점심 드셨어요?');
    await _pumpHome(tester, h);

    await tester.tap(find.byKey(FamilyMessagePrompt.openKey));
    await tester.pumpAndSettle();

    expect(find.byKey(ConversationKeys.field), findsOneWidget);
  });

  testWidgets('나중에 gives the tiles back without telling the server', (
    tester,
  ) async {
    // The guardian's 읽음 확인 says 어머니가 두 시에 읽으셨다. A card pushed
    // aside without looking at it is not that, and claiming otherwise is the
    // one thing this feature must never do.
    final h = await _family(say: '엄마, 점심 드셨어요?');
    await _pumpHome(tester, h);

    await tester.tap(find.byKey(FamilyMessagePrompt.laterKey));
    await tester.pumpAndSettle();

    expect(find.byType(FamilyMessagePrompt), findsNothing);
    expect(find.byKey(SeniorNoticeLayer.layerKey), findsNothing);

    final all = await h.messages.conversation(h.profileId);
    expect(
      all.where((m) => !m.isFromSenior).every((m) => !m.isRead),
      isTrue,
      reason: '나중에 marked it read',
    );
  });

  testWidgets('나중에 does not survive a restart', (tester) async {
    // The dismissal is held in memory on purpose. Persisting it would be a
    // quieter way of marking the message read - the parent would stop being
    // shown it and the guardian would never be told either, which is the
    // worst of both. A launcher goes weeks without a restart, so this is a
    // real reprieve rather than a formality.
    final h = await _family(say: '엄마, 점심 드셨어요?');
    await _pumpHome(tester, h);
    await tester.tap(find.byKey(FamilyMessagePrompt.laterKey));
    await tester.pumpAndSettle();
    expect(find.byType(FamilyMessagePrompt), findsNothing);

    await _pumpHome(tester, h);

    expect(find.byType(FamilyMessagePrompt), findsOneWidget);
    expect(find.text('엄마, 점심 드셨어요?'), findsOneWidget);
  });
}
