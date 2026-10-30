import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/app_category.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/presentation/detailed_home_screen.dart';
import 'package:app/features/launcher/presentation/easy_home_screen.dart';
import 'package:app/features/launcher/presentation/senior_settings_screen.dart';
import 'package:app/features/launcher/presentation/widgets/go_home_bar.dart';
import 'package:app/features/onboarding/presentation/screen_mode_choice_screen.dart';

import '../../support/pump_app.dart';

/// 바꾸기 → 화면 바꾸기.
///
/// Onboarding said 나중에 언제든 바꿀 수 있어요 and nothing in the app could:
/// the choice was made once and `chooseScreenMode` had no other caller.
Future<void> _openChoice(WidgetTester tester) async {
  await pumpApp(
    tester,
    overrides: [
      // A phone that was never set as home - the one where onboarding would
      // ask the home-app question after the choice.
      appLauncherProvider.overrideWithValue(
        FakeAppLauncher(defaultHome: false),
      ),
    ],
    prefs: {
      SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
        const SeniorSettings(
          screenMode: ScreenMode.easy,
          apps: [
            LauncherApp(id: 'phone', label: '전화', category: AppCategory.phone),
            LauncherApp(id: 'b', label: '영희 사진', category: AppCategory.gallery),
          ],
        ).toJson(),
      ),
    },
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('더 보기'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(SeniorSettingsScreen.screenModeRow));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('it opens the same two cards, with a way home', (tester) async {
    await _openChoice(tester);

    expect(find.byType(ScreenModeChoiceScreen), findsOneWidget);
    expect(find.text('정말 쉬운 화면'), findsOneWidget);
    expect(find.text('자세한 화면'), findsOneWidget);
    expect(find.text('버튼은 그대로 있어요'), findsOneWidget);
    expect(find.byKey(GoHomeBar.buttonKey), findsOneWidget);
  });

  testWidgets('choosing goes home on the new screen and keeps the buttons', (
    tester,
  ) async {
    await _openChoice(tester);

    await tester.tap(find.text('자세한 화면'));
    await tester.pumpAndSettle();

    // Not asked again: onboarding is the one place for that question.
    expect(find.byKey(ScreenModeChoiceKeys.homeAppAsk), findsNothing);
    expect(find.byType(DetailedHomeScreen), findsOneWidget);
    expect(find.text('영희 사진'), findsOneWidget);
  });

  testWidgets('the way home leaves the screen as it was', (tester) async {
    await _openChoice(tester);

    await tester.tap(find.byKey(GoHomeBar.buttonKey));
    await tester.pumpAndSettle();

    expect(find.byType(EasyHomeScreen), findsOneWidget);
  });
}
