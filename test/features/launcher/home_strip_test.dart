import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/clock.dart';
import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/message_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/remote/subscription_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/presentation/widgets/home_strip.dart';

import '../../support/pump_app.dart';

final _tuesdayAfternoon = DateTime(2026, 10, 20, 14, 30);

Future<void> _pumpHome(
  WidgetTester tester, {
  List<Object> overrides = const [],
}) async {
  await pumpApp(
    tester,
    overrides: [nowProvider.overrideWithValue(() => _tuesdayAfternoon), ...overrides],
    prefs: {
      SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
        const SeniorSettings(screenMode: ScreenMode.easy, apps: defaultEasyApps)
            .toJson(),
      ),
    },
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the clock is the first thing on the screen', (tester) async {
    // A senior reaches for their phone to check the time more often than for
    // anything else, and the system clock in the status bar is tiny.
    await _pumpHome(tester);

    expect(find.text('오후 2:30'), findsOneWidget);
    expect(find.text('10월 20일 화요일'), findsOneWidget);
  });

  testWidgets('with nobody connected it invites them to connect', (
    tester,
  ) async {
    await _pumpHome(tester);

    expect(find.byKey(HomeStrip.connectKey), findsOneWidget);
    expect(find.byKey(HomeStrip.messageKey), findsNothing);
  });

  testWidgets('once a family is attached it shows their newest message', (
    tester,
  ) async {
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

    await _pumpHome(
      tester,
      overrides: [
        seniorLinkRepositoryProvider.overrideWithValue(store),
        pairingRepositoryProvider.overrideWithValue(pairing),
        subscriptionRepositoryProvider.overrideWithValue(subs),
        messageRepositoryProvider.overrideWithValue(messages),
        seniorLinkStoreProvider.overrideWithValue(
          InMemorySeniorLinkStore(
            SeniorLink(installId: 'senior-phone', seniorProfileId: profile.id),
          ),
        ),
      ],
    );

    expect(find.byKey(HomeStrip.messageKey), findsOneWidget);
    expect(find.text('엄마, 점심 드셨어요?'), findsOneWidget);
    expect(find.text('영희'), findsOneWidget);
    expect(find.byKey(HomeStrip.connectKey), findsNothing);
  });
}
