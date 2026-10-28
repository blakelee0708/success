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
import 'package:app/domain/device_status.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/data/device_status_reader.dart';

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
  DeviceStatusReader? reader,
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
      if (reader != null) deviceStatusReaderProvider.overrideWithValue(reader),
      seniorLinkRepositoryProvider.overrideWithValue(store),
      pairingRepositoryProvider.overrideWithValue(pairing),
      homeAppsRepositoryProvider.overrideWithValue(
        InMemoryHomeAppsRepository(),
      ),
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
    final store = await _pumpSeniorPhone(
      tester,
      linked: true,
      reader: FakeDeviceStatusReader(null),
    );

    expect(store.touchCount, greaterThan(0));
    expect(store.activeDeviceByProfile.values.single.lastSeenAt, isNotNull);
  });

  testWidgets('coming back to the home screen reports it again', (
    tester,
  ) async {
    // The commoner case by far. A launcher is the screen a phone sits on and
    // may not be restarted for weeks, so start-up alone would report once and
    // then go quiet while the parent used the phone every day.
    final store = await _pumpSeniorPhone(
      tester,
      linked: true,
      reader: FakeDeviceStatusReader(null),
    );
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
    final store = await _pumpSeniorPhone(
      tester,
      linked: true,
      reader: FakeDeviceStatusReader(null),
    );
    store.offline = true;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('전화'), findsOneWidget);
  });

  testWidgets('the report carries the battery and the ringer with it', (
    tester,
  ) async {
    // No separate schedule and no background service: the readings ride on
    // the check-in the launcher already sends, so they exist exactly when
    // the parent used the phone — which is when a reading means anything.
    final reader = FakeDeviceStatusReader(
      DeviceStatus(
        readAt: DateTime(2026, 10, 20, 14, 30),
        batteryPercent: 61,
        isCharging: false,
        ringer: RingerMode.vibrate,
      ),
    );
    final store = await _pumpSeniorPhone(tester, linked: true, reader: reader);
    await tester.pumpAndSettle();

    expect(reader.reads, greaterThan(0));
    expect(store.touchCount, greaterThan(0));
  });

  testWidgets(
    'a platform that answers nothing reports no reading, not a zero',
    (tester) async {
      // `flutter test` is such a platform and so is a phone whose channel is
      // not there. 배터리 0% is the most alarming reading the card could show
      // and nothing may invent it.
      final store = await _pumpSeniorPhone(
        tester,
        linked: true,
        reader: FakeDeviceStatusReader(null),
      );

      expect(store.touchCount, greaterThan(0));
      expect(store.activeDeviceByProfile.values.single.status, isNull);
    },
  );

  testWidgets('a reader that throws does not stop the check-in', (
    tester,
  ) async {
    final store = await _pumpSeniorPhone(
      tester,
      linked: true,
      reader: FakeDeviceStatusReader.throwing(),
    );

    expect(tester.takeException(), isNull);
    expect(store.touchCount, greaterThan(0));
  });

  testWidgets('a phone that never answers about its battery still checks in', (
    tester,
  ) async {
    // A platform channel is not obliged to reply. `flutter test` is such a
    // platform and so is a phone whose launcher service has wedged. Waiting
    // for one — which is how this was first written — meant the parent's
    // phone stopped reporting that it was being used at all, trading the
    // valuable half for a battery percentage. Bounding the wait with a
    // timeout was the second attempt and was worse: the timer outlives every
    // phone that does not answer.
    final store = await _pumpSeniorPhone(
      tester,
      linked: true,
      reader: FakeDeviceStatusReader.silent(),
    );

    expect(store.touchCount, greaterThan(0));
    expect(store.activeDeviceByProfile.values.single.lastSeenAt, isNotNull);
  });

  testWidgets('the reading reaches the server on the check-in after it', (
    tester,
  ) async {
    // The read is started and not waited for, so the first check-in of a run
    // carries no reading and the next one carries it. That is the trade for
    // never blocking the check-in, and it costs nothing a guardian can see:
    // the reading is stamped with the time it was taken, so the card states
    // its real age either way.
    final reader = FakeDeviceStatusReader(
      DeviceStatus(
        readAt: DateTime(2026, 10, 20, 14, 30),
        batteryPercent: 61,
        ringer: RingerMode.vibrate,
      ),
    );
    final store = await _pumpSeniorPhone(tester, linked: true, reader: reader);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    final device = store.activeDeviceByProfile.values.single;
    expect(device.status?.batteryPercent, 61);
    expect(device.status?.ringer, RingerMode.vibrate);
  });
}
