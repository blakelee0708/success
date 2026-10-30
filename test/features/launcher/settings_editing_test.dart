import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/app_category.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/application/senior_settings_controller.dart';

/// Builds a container over a real (mocked-store) repository so every
/// assertion also proves the edit reached disk.
ProviderContainer _container() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

Future<SeniorSettings> _stored() =>
    SharedPreferencesSeniorSettingsRepository().load();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SeniorSettingsController> ready(ProviderContainer c) async {
    await c.read(seniorSettingsControllerProvider.future);
    return c.read(seniorSettingsControllerProvider.notifier);
  }

  test('choosing a mode seeds that mode\'s default buttons', () async {
    final c = _container();
    await (await ready(c)).chooseScreenMode(ScreenMode.easy);

    expect((await _stored()).apps.map((a) => a.label), [
      '전화',
      '문자',
      '사진 보기',
      '영상 보기',
    ]);
  });

  test('choosing a mode again does not discard edited buttons', () async {
    // Re-entering onboarding must not wipe a home the senior has arranged.
    final c = _container();
    final controller = await ready(c);
    await controller.chooseScreenMode(ScreenMode.easy);
    await controller.renameApp('phone', '전화걸기');
    await controller.chooseScreenMode(ScreenMode.detailed);

    final apps = (await _stored()).apps;
    expect(apps.firstWhere((a) => a.id == 'phone').label, '전화걸기');
  });

  test('the text size is written through', () async {
    final c = _container();
    await (await ready(c)).setFontSize(FontSize.extraLarge);

    expect((await _stored()).fontSize, FontSize.extraLarge);
  });

  test('renaming a button leaves its icon and position alone', () async {
    final c = _container();
    final controller = await ready(c);
    await controller.chooseScreenMode(ScreenMode.easy);
    await controller.renameApp('gallery', '사진');

    final apps = (await _stored()).apps;
    expect(apps[2].label, '사진');
    expect(apps[2].category, AppCategory.gallery);
    expect(apps.length, 4);
  });

  test('recolouring a button survives, and can be cleared again', () async {
    final c = _container();
    final controller = await ready(c);
    await controller.chooseScreenMode(ScreenMode.easy);

    await controller.setAppColor('phone', ButtonColor.rose);
    expect((await _stored()).apps.first.color, ButtonColor.rose);

    await controller.setAppColor('phone', null);
    expect((await _stored()).apps.first.color, isNull);
  });

  test('removing a button drops only that button', () async {
    final c = _container();
    final controller = await ready(c);
    await controller.chooseScreenMode(ScreenMode.easy);
    await controller.removeApp('message');

    expect((await _stored()).apps.map((a) => a.id), [
      'phone',
      'gallery',
      'youtube',
    ]);
  });

  test('reordering moves one button and keeps the rest in order', () async {
    final c = _container();
    final controller = await ready(c);
    await controller.chooseScreenMode(ScreenMode.easy);
    await controller.reorderApps(0, 3);

    expect((await _stored()).apps.map((a) => a.id), [
      'message',
      'gallery',
      'phone',
      'youtube',
    ]);
  });

  test('an added button goes to the end with a fresh id', () async {
    final c = _container();
    final controller = await ready(c);
    await controller.chooseScreenMode(ScreenMode.easy);
    await controller.addApp(label: '카카오톡', category: AppCategory.kakao);

    final apps = (await _stored()).apps;
    expect(apps.last.label, '카카오톡');
    expect(apps.length, 5);
    expect(apps.map((a) => a.id).toSet().length, 5, reason: 'ids stay unique');
  });

  test('adding the same label twice still yields two buttons', () async {
    final c = _container();
    final controller = await ready(c);
    await controller.chooseScreenMode(ScreenMode.easy);
    await controller.addApp(label: '메모', category: AppCategory.message);
    await controller.addApp(label: '메모', category: AppCategory.message);

    final apps = (await _stored()).apps;
    expect(apps.length, 6);
    expect(apps.map((a) => a.id).toSet().length, 6);
  });

  test('editing a button that is gone changes nothing', () async {
    final c = _container();
    final controller = await ready(c);
    await controller.chooseScreenMode(ScreenMode.easy);
    await controller.renameApp('nope', '없음');

    expect((await _stored()).apps.length, 4);
    expect((await _stored()).apps.map((a) => a.label), contains('전화'));
  });
}
