import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/care/data/push_messaging.dart';
import 'package:app/features/care/presentation/senior_ring_layer.dart';
import 'package:app/features/launcher/data/app_launcher.dart';

import '../../support/pump_app.dart';

/// 소리 울리기's receiving half — the push that reaches the parent's phone.
///
/// The sending half does not exist yet (it needs an Edge Function holding a
/// service-account key), and neither does the native background wake-up. What
/// is covered here is everything between a message arriving and the screen
/// the senior sees.
typedef Harness = ({
  InMemorySeniorLinkRepository store,
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
  store.touchCount = 0;
  final push = FakePushMessaging();
  addTearDown(push.dispose);
  return (store: store, push: push, profileId: profile.id);
}

/// The parent's own phone, on their home screen.
Future<void> _pumpSenior(
  WidgetTester tester,
  Harness h, {
  bool linked = true,
}) async {
  await pumpApp(
    tester,
    overrides: [
      appLauncherProvider.overrideWithValue(FakeAppLauncher(defaultHome: true)),
      pushMessagingProvider.overrideWithValue(h.push),
      seniorLinkRepositoryProvider.overrideWithValue(h.store),
      homeAppsRepositoryProvider.overrideWithValue(
        InMemoryHomeAppsRepository(),
      ),
      seniorLinkStoreProvider.overrideWithValue(
        InMemorySeniorLinkStore(
          SeniorLink(
            installId: 'senior-phone',
            seniorProfileId: linked ? h.profileId : null,
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
}

/// A guardian's phone. `HomeKeyListener` wraps the router on this half too.
Future<void> _pumpGuardian(WidgetTester tester, Harness h) async {
  final auth = InMemoryGuardianAuthRepository()
    ..seedSignedIn(const GuardianSession(userId: 'u1'));
  addTearDown(auth.dispose);
  await pumpApp(
    tester,
    overrides: [
      guardianAuthRepositoryProvider.overrideWithValue(auth),
      pushMessagingProvider.overrideWithValue(h.push),
      seniorLinkRepositoryProvider.overrideWithValue(h.store),
    ],
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the token gets to the server', () {
    testWidgets('it rides on the check-in', (tester) async {
      // Not a call of its own: a token rotates, and the check-in is the one
      // thing that already runs on every resume.
      final h = await _family();
      await _pumpSenior(tester, h);
      await tester.pumpAndSettle();

      expect(h.store.pushTokenByInstallId['senior-phone'], 'token-abc');
    });

    testWidgets('a guardian phone never reports one', (tester) async {
      // This phone has no parent attached, so it is not reachable by a ring
      // and has no business writing a token against somebody's device row.
      final h = await _family();
      await _pumpGuardian(tester, h);
      await tester.pumpAndSettle();

      expect(h.store.pushTokenByInstallId, isEmpty);
    });

    testWidgets('a phone with no network still checks in', (tester) async {
      // The check-in is the valuable half. A token it could not fetch must
      // not take 안부 신호 down with it.
      final h = await _family();
      h.push.offline = true;
      await _pumpSenior(tester, h);
      await tester.pumpAndSettle();

      expect(h.store.touchCount, greaterThan(0));
      expect(h.store.pushTokenByInstallId, isEmpty);
    });
  });

  group('a ring arrives', () {
    testWidgets('it covers the home screen and says who is asking', (
      tester,
    ) async {
      final h = await _family();
      await _pumpSenior(tester, h);

      h.push.deliver({'type': 'ring', 'from': '영희', 'message': '엄마 전화 좀 줘'});
      await tester.pumpAndSettle();

      expect(find.byKey(SeniorRingLayer.layerKey), findsOneWidget);
      expect(find.textContaining('영희'), findsWidgets);
      expect(find.text('엄마 전화 좀 줘'), findsOneWidget);
    });

    testWidgets('one with no words of their own still explains itself', (
      tester,
    ) async {
      final h = await _family();
      await _pumpSenior(tester, h);

      h.push.deliver({'type': 'ring', 'from': '영희'});
      await tester.pumpAndSettle();

      expect(find.text('전화 한 번만 주세요.'), findsOneWidget);
    });

    testWidgets('one with no name still rings', (tester) async {
      // Dropping it silently is worse: the guardian pressed the button and
      // has no way of learning that nothing happened.
      final h = await _family();
      await _pumpSenior(tester, h);

      h.push.deliver({'type': 'ring'});
      await tester.pumpAndSettle();

      expect(find.byKey(SeniorRingLayer.layerKey), findsOneWidget);
      expect(find.textContaining('가족'), findsWidgets);
    });

    testWidgets('anything that is not a ring is ignored', (tester) async {
      final h = await _family();
      await _pumpSenior(tester, h);

      h.push.deliver({'type': 'something_else', 'from': '영희'});
      h.push.deliver(const {});
      await tester.pumpAndSettle();

      expect(find.byKey(SeniorRingLayer.layerKey), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a phone with no parent attached does not ring', (
      tester,
    ) async {
      // Nothing should be able to reach an unpaired phone, but the guard is
      // here rather than only on the server.
      final h = await _family();
      await _pumpSenior(tester, h, linked: false);

      h.push.deliver({'type': 'ring', 'from': '영희'});
      await tester.pumpAndSettle();

      expect(find.byKey(SeniorRingLayer.layerKey), findsNothing);
    });

    testWidgets('the guardian half never rings', (tester) async {
      final h = await _family();
      await _pumpGuardian(tester, h);

      h.push.deliver({'type': 'ring', 'from': '영희'});
      await tester.pumpAndSettle();

      expect(find.byKey(SeniorRingLayer.layerKey), findsNothing);
    });
  });

  group('a build with no Firebase', () {
    test('says nothing and offers no token', () async {
      // Every `flutter test`, and any APK built without google-services.json.
      const push = NoPushMessaging();

      expect(await push.token(), isNull);
      expect(await push.messages().toList(), isEmpty);
    });
  });
}
