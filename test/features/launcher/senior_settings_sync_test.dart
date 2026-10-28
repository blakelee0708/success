import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/domain/app_category.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_profile.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/application/senior_settings_sync.dart';

/// A store already pointing at a profile, as a connected phone would be.
InMemorySeniorLinkStore _linkedStore() => InMemorySeniorLinkStore(
  const SeniorLink(installId: 'install-1', seniorProfileId: 'profile-1'),
);

/// A link repository that already knows the profile, so `pull` has something
/// to read back.
InMemorySeniorLinkRepository _linksWithProfile({
  ScreenMode? screenMode,
  FontSize? fontSize,
}) {
  final links = InMemorySeniorLinkRepository();
  links.profiles['profile-1'] = SeniorProfile(
    id: 'profile-1',
    displayName: '박순자',
    customerCode: 'CODE0001',
    screenMode: screenMode,
    fontSize: fontSize,
  );
  return links;
}

void main() {
  const settings = SeniorSettings(
    screenMode: ScreenMode.easy,
    fontSize: FontSize.large,
    apps: [
      LauncherApp(id: 'phone', label: '전화', category: AppCategory.phone),
      LauncherApp(id: 'app2', label: '아들', category: AppCategory.message),
    ],
  );

  test('a linked phone pushes its buttons and its profile settings', () async {
    final homeApps = InMemoryHomeAppsRepository();
    final links = _linksWithProfile();
    final sync = SeniorSettingsSync(
      linkStore: _linkedStore(),
      homeApps: homeApps,
      links: links,
    );

    expect(await sync.push(settings), isTrue);
    expect(homeApps.byProfile['profile-1'], settings.apps);
    expect(links.profiles['profile-1']!.screenMode, ScreenMode.easy);
    expect(links.profiles['profile-1']!.fontSize, FontSize.large);
  });

  test('a phone that is not linked yet pushes nothing', () async {
    final homeApps = InMemoryHomeAppsRepository();
    final sync = SeniorSettingsSync(
      linkStore: InMemorySeniorLinkStore(),
      homeApps: homeApps,
      links: InMemorySeniorLinkRepository(),
    );

    expect(await sync.push(settings), isFalse);
    expect(homeApps.replaceCount, 0);
  });

  test('a phone with no signal reports failure instead of throwing', () async {
    // The senior's home screen is drawn from disk and has to keep being drawn
    // with no network. A failed sync is a missing update, never a crash.
    final homeApps = InMemoryHomeAppsRepository()..offline = true;
    final sync = SeniorSettingsSync(
      linkStore: _linkedStore(),
      homeApps: homeApps,
      links: _linksWithProfile(),
    );

    expect(await sync.push(settings), isFalse);
  });

  test('pull adopts the guardian arrangement waiting on the server', () async {
    final homeApps = InMemoryHomeAppsRepository();
    await homeApps.replace('profile-1', const [
      LauncherApp(id: 'kakao', label: '카카오톡', category: AppCategory.kakao),
    ]);
    final sync = SeniorSettingsSync(
      linkStore: _linkedStore(),
      homeApps: homeApps,
      links: _linksWithProfile(fontSize: FontSize.extraLarge),
    );

    final merged = await sync.pull(settings);
    expect(merged!.apps.single.id, 'kakao');
    expect(merged.fontSize, FontSize.extraLarge);
  });

  test('an empty server list does not wipe a home screen in use', () async {
    // A profile nobody has pushed to reads as zero rows. Taking that literally
    // would leave the senior with no buttons at all.
    final sync = SeniorSettingsSync(
      linkStore: _linkedStore(),
      homeApps: InMemoryHomeAppsRepository(),
      links: _linksWithProfile(),
    );

    final merged = await sync.pull(settings);
    expect(merged, isNull);
  });

  test(
    'a profile with no font size chosen leaves the phone on its own',
    () async {
      // A guardian creates the profile before the parent connects, so the row
      // says nothing about font size. Reading that silence as 보통 would shrink
      // the text of a senior who had already set 아주 크게.
      final sync = SeniorSettingsSync(
        linkStore: _linkedStore(),
        homeApps: InMemoryHomeAppsRepository(),
        links: _linksWithProfile(screenMode: ScreenMode.easy),
      );

      expect(await sync.pull(settings), isNull);
    },
  );

  test('pull on an unlinked phone changes nothing', () async {
    final sync = SeniorSettingsSync(
      linkStore: InMemorySeniorLinkStore(),
      homeApps: InMemoryHomeAppsRepository(),
      links: InMemorySeniorLinkRepository(),
    );

    expect(await sync.pull(settings), isNull);
  });

  test('a failed pull leaves the phone on what it already had', () async {
    final sync = SeniorSettingsSync(
      linkStore: _linkedStore(),
      homeApps: InMemoryHomeAppsRepository()..offline = true,
      links: _linksWithProfile(),
    );

    expect(await sync.pull(settings), isNull);
  });
}
