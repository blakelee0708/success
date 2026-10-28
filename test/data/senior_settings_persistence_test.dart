import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/app_category.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';

/// A second repository over the same store stands in for a restart: the old
/// object is gone, only what reached disk is left.
Future<SeniorSettings> _reload() =>
    SharedPreferencesSeniorSettingsRepository().load();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a fresh install has no screen mode and normal text', () async {
    final settings = await _reload();

    expect(settings.screenMode, isNull);
    expect(settings.fontSize, FontSize.normal);
    expect(settings.apps, isEmpty);
  });

  test('the screen-mode choice survives a restart', () async {
    final repo = SharedPreferencesSeniorSettingsRepository();
    await repo.save(const SeniorSettings(screenMode: ScreenMode.detailed));

    expect((await _reload()).screenMode, ScreenMode.detailed);
  });

  test('the chosen text size survives a restart', () async {
    final repo = SharedPreferencesSeniorSettingsRepository();
    await repo.save(const SeniorSettings(fontSize: FontSize.extraLarge));

    expect((await _reload()).fontSize, FontSize.extraLarge);
  });

  test('the home buttons survive a restart in order', () async {
    final repo = SharedPreferencesSeniorSettingsRepository();
    await repo.save(
      SeniorSettings(
        screenMode: ScreenMode.easy,
        apps: const [
          LauncherApp(id: 'a', label: '전화', category: AppCategory.phone),
          LauncherApp(id: 'b', label: '앨범', category: AppCategory.gallery),
        ],
      ),
    );

    final apps = (await _reload()).apps;
    expect(apps.map((a) => a.id), ['a', 'b']);
    expect(apps.map((a) => a.label), ['전화', '앨범']);
    expect(apps.first.category, AppCategory.phone);
  });

  test('a renamed button keeps its identity and icon', () async {
    final repo = SharedPreferencesSeniorSettingsRepository();
    await repo.save(
      const SeniorSettings(
        apps: [
          LauncherApp(id: 'a', label: '카카오톡', category: AppCategory.kakao),
        ],
      ),
    );

    final renamed = (await _reload()).apps.single.copyWith(label: '카톡');
    await repo.save(SeniorSettings(apps: [renamed]));

    final reloaded = (await _reload()).apps.single;
    expect(reloaded.label, '카톡');
    expect(reloaded.id, 'a');
    expect(reloaded.category, AppCategory.kakao);
  });

  test('a recoloured button survives a restart', () async {
    final repo = SharedPreferencesSeniorSettingsRepository();
    await repo.save(
      const SeniorSettings(
        apps: [
          LauncherApp(
            id: 'a',
            label: '전화',
            category: AppCategory.phone,
            color: ButtonColor.orange,
          ),
        ],
      ),
    );

    expect((await _reload()).apps.single.color, ButtonColor.orange);
  });

  test('a button with no chosen colour falls back to its category', () async {
    final repo = SharedPreferencesSeniorSettingsRepository();
    await repo.save(
      const SeniorSettings(
        apps: [LauncherApp(id: 'a', label: '전화', category: AppCategory.phone)],
      ),
    );

    expect((await _reload()).apps.single.color, isNull);
  });

  test('unreadable stored settings fall back to defaults', () async {
    // A half-written or older payload must not brick the launcher: this app
    // is the senior's home screen.
    SharedPreferences.setMockInitialValues({
      SharedPreferencesSeniorSettingsRepository.storageKey: '{not json',
    });

    expect((await _reload()).screenMode, isNull);
  });
}
