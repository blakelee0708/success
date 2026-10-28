import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/message_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/care/data/push_messaging.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/messages/application/message_controller.dart';

import '../../support/pump_app.dart';

/// 자녀 폰에 뜨는 알림.
///
/// The exact opposite of the rule FCM follows for the senior, and for the
/// same reason. A status-bar entry is the one place a parent who cannot find
/// their contacts app will not look, so their messages are drawn full screen.
/// Their child is an adult with an ordinary phone on which this is one app
/// among many: a card could only appear once they had already opened it,
/// which is both late and redundant.
typedef Harness = ({
  InMemorySeniorLinkRepository store,
  InMemoryPairingRepository pairing,
  InMemoryMessageRepository messages,
  FakePushMessaging push,
  String profileId,
});

Future<Harness> _family() async {
  final store = InMemorySeniorLinkRepository();
  final pairing = InMemoryPairingRepository(store);
  await store.ensureGuardianAccount(displayName: '영희');
  final started = await pairing.startSeniorPairing(installId: 'senior-phone');
  final profile = await pairing.claimSeniorPairingCode(
    code: started.code,
    displayName: '어머니',
  );
  return (
    store: store,
    pairing: pairing,
    messages: InMemoryMessageRepository(store),
    push: FakePushMessaging(),
    profileId: profile.id,
  );
}

List<Object> _shared(Harness h) => [
  seniorLinkRepositoryProvider.overrideWithValue(h.store),
  pairingRepositoryProvider.overrideWithValue(h.pairing),
  messageRepositoryProvider.overrideWithValue(h.messages),
  pushMessagingProvider.overrideWithValue(h.push),
  homeAppsRepositoryProvider.overrideWithValue(InMemoryHomeAppsRepository()),
];

/// The guardian's phone, landing on the dashboard.
Future<void> _pumpDashboard(WidgetTester tester, Harness h) async {
  final auth = InMemoryGuardianAuthRepository()
    ..seedSignedIn(const GuardianSession(userId: 'u1'));
  addTearDown(auth.dispose);
  await pumpApp(
    tester,
    overrides: [
      ..._shared(h),
      guardianAuthRepositoryProvider.overrideWithValue(auth),
    ],
  );
  await tester.pumpAndSettle();
}

/// The parent's phone, on their home screen.
Future<void> _pumpSeniorHome(WidgetTester tester, Harness h) async {
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
          screenMode: ScreenMode.easy,
          apps: defaultEasyApps,
        ).toJson(),
      ),
    },
  );
  await tester.pumpAndSettle();
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

void main() {
  testWidgets('opening the dashboard reports where this phone is', (
    tester,
  ) async {
    final h = await _family();
    await _pumpDashboard(tester, h);

    expect(h.store.guardianPushTokens, ['token-abc']);
  });

  testWidgets('permission is asked before the token is read', (tester) async {
    // A token with notifications denied is an address that accepts post and
    // burns it. `POST_NOTIFICATIONS` is already in the built APK because
    // firebase_messaging declares it; what was missing was the asking.
    final h = await _family();
    await _pumpDashboard(tester, h);

    expect(h.push.permissionAsks, 1);
    expect(h.push.tokenReads, 1);
  });

  testWidgets('a phone with no token reports nothing rather than empty', (
    tester,
  ) async {
    // Writing a blank through would wipe the address the last open left, and
    // the guardian would stop being reachable with nothing saying so.
    final h = await _family();
    h.push.fixedToken = null;
    await _pumpDashboard(tester, h);

    expect(h.store.guardianPushTokens, isEmpty);
  });

  testWidgets('a phone with no network does not stop the dashboard', (
    tester,
  ) async {
    final h = await _family();
    h.push.offline = true;
    await _pumpDashboard(tester, h);

    expect(h.store.guardianPushTokens, isEmpty);
    expect(find.text('어머니'), findsWidgets);
  });

  testWidgets('the senior\'s phone never registers a guardian token', (
    tester,
  ) async {
    // `GuardianPushRegistrar` runs from the dashboard, which a parent's phone
    // never opens. Checked rather than assumed, because the senior half has
    // twice been hung by a provider built on the wrong phone.
    final h = await _family();
    await _pumpSeniorHome(tester, h);

    expect(h.store.guardianPushTokens, isEmpty);
    expect(h.push.permissionAsks, 0);
  });

  testWidgets('a message from the parent tells the family', (tester) async {
    final h = await _family();
    h.messages.sendingAsSenior = true;
    await _pumpSeniorHome(tester, h);

    final container = _container(tester);
    await container.read(messageControllerProvider.notifier).send('잘 있다');

    expect(h.messages.notified, hasLength(1));
    expect(
      h.messages.byProfile[h.profileId]!.single.id,
      h.messages.notified.single,
    );
  });

  testWidgets('a message from a guardian tells nobody', (tester) async {
    // Their parent's screen already shows it the moment the phone is picked
    // up, and buzzing a sibling about what you just typed is noise. The
    // server refuses such a call; the app does not make it.
    final h = await _family();
    h.messages.sendingAsSenior = false;
    await _pumpDashboard(tester, h);

    final container = _container(tester);
    await container.read(messageControllerProvider.notifier).send('엄마 잘 계세요?');

    expect(h.messages.byProfile[h.profileId], hasLength(1));
    expect(h.messages.notified, isEmpty);
  });
}
