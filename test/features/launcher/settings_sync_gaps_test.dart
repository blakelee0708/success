import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/app_category.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';

import '../../support/pump_app.dart';

/// What the guardian's screen promises: 바꾸면 부모님 폰에 반영됩니다. 부모님
/// 폰이 꺼져 있으면 다음에 켤 때 적용돼요.
///
/// The second half of that sentence is the one under test.
void main() {
  testWidgets('a change made while the parent\'s phone was off arrives on the '
      'next launch', (tester) async {
    final store = InMemorySeniorLinkRepository();
    final pairing = InMemoryPairingRepository(store);
    final homeApps = InMemoryHomeAppsRepository();
    await store.ensureGuardianAccount(displayName: '김보호');
    final started = await pairing.startSeniorPairing(installId: 'senior-phone');
    final profile = await pairing.claimSeniorPairingCode(
      code: started.code,
      displayName: '어머니',
    );

    // The guardian rearranged the home screen from their own phone.
    await homeApps.replace(profile.id, const [
      LauncherApp(id: 'phone', label: '전화', category: AppCategory.phone),
      LauncherApp(id: 'daughter', label: '딸', category: AppCategory.kakao),
    ]);

    // The parent's phone starts up with what it had on disk from before.
    await pumpApp(
      tester,
      overrides: [
        appLauncherProvider.overrideWithValue(
          FakeAppLauncher(defaultHome: true),
        ),
        seniorLinkRepositoryProvider.overrideWithValue(store),
        pairingRepositoryProvider.overrideWithValue(pairing),
        homeAppsRepositoryProvider.overrideWithValue(homeApps),
        seniorLinkStoreProvider.overrideWithValue(
          InMemorySeniorLinkStore(
            SeniorLink(installId: 'senior-phone', seniorProfileId: profile.id),
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

    expect(
      find.text('딸'),
      findsOneWidget,
      reason: 'the guardian\'s arrangement never reached the phone',
    );
  });
}
