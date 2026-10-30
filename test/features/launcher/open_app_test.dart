import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/app_category.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';

import '../../support/pump_app.dart';

/// Starts the app on a home the senior has already set up, so the launcher is
/// what is on screen.
Future<void> _pumpHome(
  WidgetTester tester,
  FakeAppLauncher launcher, {
  ScreenMode mode = ScreenMode.easy,
}) async {
  await pumpApp(
    tester,
    overrides: [appLauncherProvider.overrideWithValue(launcher)],
    prefs: {
      SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
        SeniorSettings(
          screenMode: mode,
          apps: mode == ScreenMode.easy ? defaultEasyApps : defaultDetailedApps,
        ).toJson(),
      ),
    },
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tapping 전화 opens the dialer', (tester) async {
    final launcher = FakeAppLauncher(defaultHome: true);
    await _pumpHome(tester, launcher);

    await tester.tap(find.text('전화'));
    await tester.pumpAndSettle();

    expect(launcher.opened.single, launchRequestFor(AppCategory.phone));
  });

  testWidgets('tapping a tile no longer shows a "다음 단계" placeholder', (
    tester,
  ) async {
    final launcher = FakeAppLauncher(defaultHome: true);
    await _pumpHome(tester, launcher);

    await tester.tap(find.text('사진 보기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('다음 단계'), findsNothing);
    expect(launcher.opened.single, launchRequestFor(AppCategory.gallery));
  });

  testWidgets('a renamed button still opens what its category says', (
    tester,
  ) async {
    // Renaming 전화 to 아들 must not change what it opens — the label is for
    // the senior, the category is what the phone acts on.
    final launcher = FakeAppLauncher(defaultHome: true);
    await pumpApp(
      tester,
      overrides: [appLauncherProvider.overrideWithValue(launcher)],
      prefs: {
        SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
          const SeniorSettings(
            screenMode: ScreenMode.easy,
            apps: [
              LauncherApp(
                id: 'phone',
                label: '아들',
                category: AppCategory.phone,
              ),
            ],
          ).toJson(),
        ),
      },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('아들'));
    await tester.pumpAndSettle();

    expect(launcher.opened.single.intent, LaunchIntent.dial);
  });

  testWidgets('an app that is not installed says so in the senior\'s words', (
    tester,
  ) async {
    final launcher = FakeAppLauncher(installed: false, defaultHome: true);
    await _pumpHome(tester, launcher, mode: ScreenMode.detailed);

    await tester.tap(find.text('카카오톡'));
    await tester.pumpAndSettle();

    // Not a stack trace and not silence: the senior cannot install it, but
    // they can tell whoever set the phone up.
    expect(find.text('카카오톡을(를) 열 수 없어요. 자녀분께 말씀해 주세요.'), findsOneWidget);
  });

  testWidgets('an app that opened shows nothing at all', (tester) async {
    final launcher = FakeAppLauncher(defaultHome: true);
    await _pumpHome(tester, launcher, mode: ScreenMode.detailed);

    await tester.tap(find.text('카카오톡'));
    await tester.pumpAndSettle();

    expect(find.textContaining('열 수 없어요'), findsNothing);
  });

  testWidgets('the detailed home opens apps too', (tester) async {
    final launcher = FakeAppLauncher(defaultHome: true);
    await _pumpHome(tester, launcher, mode: ScreenMode.detailed);

    await tester.tap(find.text('사진찍기'));
    await tester.pumpAndSettle();

    expect(launcher.opened.single, launchRequestFor(AppCategory.camera));
  });
}
