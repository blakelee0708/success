import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';

import '../../support/pump_app.dart';

/// The parent's phone saying it is still being used.
///
/// This is the whole of 안부 신호: no permission, no sensor, no background
/// service — the launcher reports that it came to the foreground, which on a
/// phone whose home screen this is means the parent unlocked it or came back
/// from another app.
///
/// Until this existed `last_seen_at` was written once, when the phone
/// registered, and never again. The guardian's hero card read it in the
/// present tense.
Future<InMemorySeniorLinkRepository> _pumpSeniorPhone(
  WidgetTester tester, {
  required bool linked,
}) async {
  final store = InMemorySeniorLinkRepository();
  final pairing = InMemoryPairingRepository(store);
  await store.ensureGuardianAccount(displayName: '김보호');
  final started = await pairing.startSeniorPairing(installId: 'senior-phone');
  final profile = await pairing.claimSeniorPairingCode(
    code: started.code,
    displayName: '어머니',
  );
  store.touchCount = 0;

  await pumpApp(
    tester,
    overrides: [
      appLauncherProvider.overrideWithValue(FakeAppLauncher(defaultHome: true)),
      seniorLinkRepositoryProvider.overrideWithValue(store),
      pairingRepositoryProvider.overrideWithValue(pairing),
      homeAppsRepositoryProvider.overrideWithValue(InMemoryHomeAppsRepository()),
      seniorLinkStoreProvider.overrideWithValue(
        InMemorySeniorLinkStore(
          SeniorLink(
            installId: 'senior-phone',
            seniorProfileId: linked ? profile.id : null,
          ),
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
  return store;
}

void main() {
  testWidgets('opening the launcher reports the phone is in use', (
    tester,
  ) async {
    final store = await _pumpSeniorPhone(tester, linked: true);

    expect(store.touchCount, greaterThan(0));
    expect(store.activeDeviceByProfile.values.single.lastSeenAt, isNotNull);
  });

  testWidgets('coming back to the home screen reports it again', (
    tester,
  ) async {
    // The commoner case by far. A launcher is the screen a phone sits on and
    // may not be restarted for weeks, so start-up alone would report once and
    // then go quiet while the parent used the phone every day.
    final store = await _pumpSeniorPhone(tester, linked: true);
    final before = store.touchCount;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(store.touchCount, greaterThan(before));
  });

  testWidgets('a phone with no profile reports nothing', (tester) async {
    // Same guard the settings pull needs: a guardian's phone runs this code
    // too, and it has no device row to touch.
    final store = await _pumpSeniorPhone(tester, linked: false);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(store.touchCount, 0);
  });

  testWidgets('a phone with no signal still opens its home screen', (
    tester,
  ) async {
    // Reporting is a courtesy to the guardian. It is not allowed to be in the
    // way of the senior's own phone starting up.
    final store = await _pumpSeniorPhone(tester, linked: true);
    store.offline = true;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('전화'), findsOneWidget);
  });
}
