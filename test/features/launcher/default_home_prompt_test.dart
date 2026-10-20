import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/presentation/more_apps_placeholder.dart';
import 'package:app/features/launcher/presentation/widgets/home_strip.dart';
import 'package:app/features/launcher/presentation/widgets/default_home_prompt.dart';

import '../../support/pump_app.dart';

/// Opens 설정, which is where the offer lives now.
///
/// It used to sit on the home screen itself; onboarding asks the question
/// instead, and this is the way back for anyone who said 나중에. The route in
/// differs by screen — a tile on 자세한 화면, 더 보기 on the easy one — so
/// both are walked here.
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

  if (mode == ScreenMode.easy) {
    await tester.tap(find.text('더 보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(MoreAppsPlaceholder.settingsKey));
  } else {
    await tester.tap(find.text('설정'));
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a phone that has not been set up yet is offered the way', (
    tester,
  ) async {
    await _pumpHome(tester, FakeAppLauncher(defaultHome: false));

    expect(find.byKey(DefaultHomePrompt.promptKey), findsOneWidget);
    expect(find.text('이 화면을 첫 화면으로 만들어 두세요'), findsOneWidget);
  });

  testWidgets('a phone already using this launcher is not nagged', (
    tester,
  ) async {
    await _pumpHome(tester, FakeAppLauncher(defaultHome: true));

    expect(find.byKey(DefaultHomePrompt.promptKey), findsNothing);
  });

  testWidgets('a platform that cannot answer shows nothing', (tester) async {
    // A desktop build, or `flutter test`, has no home app to be. Reading that
    // silence as "no" would put the prompt on every screenshot.
    await _pumpHome(tester, FakeAppLauncher());

    expect(find.byKey(DefaultHomePrompt.promptKey), findsNothing);
  });

  testWidgets('the prompt opens the system chooser', (tester) async {
    final launcher = FakeAppLauncher(defaultHome: false);
    await _pumpHome(tester, launcher);

    await tester.tap(find.byKey(DefaultHomePrompt.buttonKey));
    await tester.pumpAndSettle();

    expect(launcher.homeSettingsOpened, 1);
  });

  testWidgets('the prompt goes away once the phone has been set up', (
    tester,
  ) async {
    // The chooser is a separate screen and the app cannot see what was picked,
    // so the answer is re-read on return rather than assumed.
    final launcher = FakeAppLauncher(defaultHome: false);
    await _pumpHome(tester, launcher);

    launcher.defaultHome = true;
    await tester.tap(find.byKey(DefaultHomePrompt.buttonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(DefaultHomePrompt.promptKey), findsNothing);
  });

  testWidgets('says what to do when the phone will not open the chooser', (
    tester,
  ) async {
    // Reported from a real phone: the button did nothing at all. The role
    // dialog can decline to appear and some phones have no home-app settings
    // screen to fall back to, and a button that silently does nothing is the
    // worst possible answer for the person this app is for — they cannot tell
    // it apart from a broken phone.
    final launcher = FakeAppLauncher(defaultHome: false)
      ..homeSettingsOpens = false;
    await _pumpHome(tester, launcher);

    await tester.tap(find.byKey(DefaultHomePrompt.buttonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(DefaultHomePrompt.manualKey), findsOneWidget);
  });

  testWidgets('says nothing extra when the chooser did open', (tester) async {
    final launcher = FakeAppLauncher(defaultHome: false);
    await _pumpHome(tester, launcher);

    await tester.tap(find.byKey(DefaultHomePrompt.buttonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(DefaultHomePrompt.manualKey), findsNothing);
  });

  testWidgets('설정 on 자세한 화면 offers it too', (tester) async {
    await _pumpHome(
      tester,
      FakeAppLauncher(defaultHome: false),
      mode: ScreenMode.detailed,
    );

    expect(find.byKey(DefaultHomePrompt.promptKey), findsOneWidget);
  });

  testWidgets('the home screen is left alone', (tester) async {
    // The whole reason it moved. On the home it was a card over the tiles
    // that could not be dismissed, and at 제일 크게 it took more height than
    // the phone had — the tiles shrank to 12px rather than overflowing,
    // because every tile is a FittedBox.
    await pumpApp(
      tester,
      overrides: [
        appLauncherProvider.overrideWithValue(
          FakeAppLauncher(defaultHome: false),
        ),
      ],
      prefs: {
        SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
          const SeniorSettings(
            screenMode: ScreenMode.easy,
            fontSize: FontSize.largest,
            apps: defaultEasyApps,
          ).toJson(),
        ),
      },
    );
    await tester.pumpAndSettle();

    expect(find.byKey(DefaultHomePrompt.promptKey), findsNothing);
    expect(find.text('전화'), findsOneWidget);
    expect(find.text('긴급 구조 요청'), findsOneWidget);
    // And the clock is back, because nothing is standing on it.
    expect(find.byKey(HomeStrip.stripKey), findsOneWidget);
  });
}
