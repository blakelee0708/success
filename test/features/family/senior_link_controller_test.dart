import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/domain/app_category.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/family/application/senior_link_controller.dart';
import 'package:app/features/launcher/application/senior_settings_controller.dart';

/// The three pieces the connect flow touches, wired to in-memory twins.
({
  ProviderContainer container,
  InMemorySeniorLinkRepository links,
  InMemoryHomeAppsRepository homeApps,
  InMemorySeniorLinkStore store,
})
_harness() {
  final links = InMemorySeniorLinkRepository();
  final homeApps = InMemoryHomeAppsRepository();
  final store = InMemorySeniorLinkStore();
  final container = ProviderContainer(
    overrides: [
      seniorLinkRepositoryProvider.overrideWithValue(links),
      homeAppsRepositoryProvider.overrideWithValue(homeApps),
      seniorLinkStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, links: links, homeApps: homeApps, store: store);
}

/// Creates a profile the way a guardian would, and hands back its code.
Future<String> _profileCreatedByGuardian(
  InMemorySeniorLinkRepository links,
) async {
  await links.ensureGuardianAccount(displayName: '김보호');
  final profile = await links.createSeniorProfile(displayName: '박순자');
  return profile.customerCode;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
  });

  test('a mistyped code is refused in words the senior can act on', () async {
    final h = _harness();
    await h.container.read(seniorLinkControllerProvider.future);

    await expectLater(
      h.container
          .read(seniorLinkControllerProvider.notifier)
          .connect('NOPE1234'),
      throwsA(
        isA<SeniorLinkException>().having(
          (e) => e.message,
          'message',
          '연결 번호가 맞지 않아요. 다시 확인해 주세요.',
        ),
      ),
    );
    expect((await h.store.load()).isLinked, isFalse);
  });

  test('connecting records the profile so a restart stays linked', () async {
    final h = _harness();
    final code = await _profileCreatedByGuardian(h.links);
    await h.container.read(seniorLinkControllerProvider.future);

    final profile = await h.container
        .read(seniorLinkControllerProvider.notifier)
        .connect(code);

    expect((await h.store.load()).seniorProfileId, profile.id);
    expect(
      h.container.read(seniorLinkControllerProvider).value!.isLinked,
      isTrue,
    );
  });

  test('a lower-case code still connects', () async {
    final h = _harness();
    final code = await _profileCreatedByGuardian(h.links);
    await h.container.read(seniorLinkControllerProvider.future);

    await h.container
        .read(seniorLinkControllerProvider.notifier)
        .connect(' ${code.toLowerCase()} ');

    expect((await h.store.load()).isLinked, isTrue);
  });

  test(
    'the first phone to connect uploads the home screen it already has',
    () async {
      final h = _harness();
      final code = await _profileCreatedByGuardian(h.links);
      await h.container.read(seniorSettingsControllerProvider.future);
      await h.container
          .read(seniorSettingsControllerProvider.notifier)
          .chooseScreenMode(ScreenMode.easy);
      await h.container.read(seniorLinkControllerProvider.future);

      final profile = await h.container
          .read(seniorLinkControllerProvider.notifier)
          .connect(code);

      expect(h.homeApps.byProfile[profile.id], defaultEasyApps);
    },
  );

  test('a guardian arrangement made before connecting wins', () async {
    // The guardian may have tidied the home screen while waiting for their
    // parent to connect. That is the newer intent, so the phone adopts it.
    final h = _harness();
    await h.links.ensureGuardianAccount();
    final created = await h.links.createSeniorProfile(displayName: '박순자');
    await h.homeApps.replace(created.id, const [
      LauncherApp(id: 'phone', label: '전화', category: AppCategory.phone),
      LauncherApp(id: 'app9', label: '아들', category: AppCategory.message),
    ]);
    await h.container.read(seniorSettingsControllerProvider.future);
    await h.container
        .read(seniorSettingsControllerProvider.notifier)
        .chooseScreenMode(ScreenMode.detailed);
    await h.container.read(seniorLinkControllerProvider.future);

    await h.container
        .read(seniorLinkControllerProvider.notifier)
        .connect(created.customerCode);

    final apps = h.container.read(seniorSettingsControllerProvider).value!.apps;
    expect(apps.map((a) => a.id), ['phone', 'app9']);
  });

  test('an edit after connecting reaches the server', () async {
    final h = _harness();
    final code = await _profileCreatedByGuardian(h.links);
    await h.container.read(seniorSettingsControllerProvider.future);
    await h.container
        .read(seniorSettingsControllerProvider.notifier)
        .chooseScreenMode(ScreenMode.easy);
    await h.container.read(seniorLinkControllerProvider.future);
    final profile = await h.container
        .read(seniorLinkControllerProvider.notifier)
        .connect(code);

    final settings = h.container.read(
      seniorSettingsControllerProvider.notifier,
    );
    await settings.renameApp('phone', '전화 걸기');
    await settings.pendingSync;

    expect(
      h.homeApps.byProfile[profile.id]!
          .firstWhere((a) => a.id == 'phone')
          .label,
      '전화 걸기',
    );
  });

  test(
    'an edit before connecting does not fail for want of a server',
    () async {
      // Nothing is linked yet, and the launcher still has to work.
      final h = _harness();
      await h.container.read(seniorSettingsControllerProvider.future);
      final settings = h.container.read(
        seniorSettingsControllerProvider.notifier,
      );

      await settings.chooseScreenMode(ScreenMode.easy);
      await settings.renameApp('phone', '전화 걸기');
      await settings.pendingSync;

      expect(
        h.container
            .read(seniorSettingsControllerProvider)
            .value!
            .apps
            .first
            .label,
        '전화 걸기',
      );
      expect(h.homeApps.replaceCount, 0);
    },
  );

  test('a phone with no signal keeps editing locally', () async {
    final h = _harness();
    final code = await _profileCreatedByGuardian(h.links);
    await h.container.read(seniorSettingsControllerProvider.future);
    await h.container
        .read(seniorSettingsControllerProvider.notifier)
        .chooseScreenMode(ScreenMode.easy);
    await h.container.read(seniorLinkControllerProvider.future);
    await h.container.read(seniorLinkControllerProvider.notifier).connect(code);

    h.homeApps.offline = true;
    final settings = h.container.read(
      seniorSettingsControllerProvider.notifier,
    );
    await settings.renameApp('phone', '전화 걸기');
    await settings.pendingSync;

    expect(
      h.container
          .read(seniorSettingsControllerProvider)
          .value!
          .apps
          .first
          .label,
      '전화 걸기',
    );
  });
}
