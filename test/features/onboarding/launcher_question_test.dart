import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/presentation/widgets/default_home_prompt.dart';
import 'package:app/features/onboarding/presentation/screen_mode_choice_screen.dart';
import 'package:app/features/onboarding/presentation/splash_screen.dart';

import '../../support/pump_app.dart';

/// Asking at the end of onboarding rather than on the home screen.
///
/// `06_PERMISSION_AND_POLICY` allows exactly one request during onboarding —
/// the launcher setup — so this is where it belongs. The card on the home
/// screen stays, because a senior may say 나중에 and some phones refuse the
/// chooser outright, but it is a fallback now rather than the only ask.
Future<FakeAppLauncher> _choose(
  WidgetTester tester, {
  required bool? isDefaultHome,
}) async {
  final launcher = FakeAppLauncher()..defaultHome = isDefaultHome;
  await pumpApp(tester, overrides: [
    appLauncherProvider.overrideWithValue(launcher),
  ]);
  await settleSplashEntrance(tester);
  await tester.tap(find.byKey(SplashScreen.tapTargetKey));
  await settleAfterSplashTap(tester);
  await tester.tap(find.text('정말 쉬운 화면'));
  await tester.pumpAndSettle();
  return launcher;
}

void main() {
  testWidgets('choosing a screen asks about the home app', (tester) async {
    final launcher = await _choose(tester, isDefaultHome: false);

    expect(find.byKey(ScreenModeChoiceKeys.homeAppAsk), findsOneWidget);
    expect(launcher.homeSettingsOpened, 0, reason: 'asked before opening');

    await tester.tap(find.text('첫 화면으로 정하기'));
    await tester.pumpAndSettle();

    expect(launcher.homeSettingsOpened, 1);
  });

  testWidgets('나중에 lands on the home and leaves the card there', (
    tester,
  ) async {
    final launcher = await _choose(tester, isDefaultHome: false);

    await tester.tap(find.text('나중에'));
    await tester.pumpAndSettle();

    expect(launcher.homeSettingsOpened, 0);
    // The card is the fallback for exactly this: they said not now.
    expect(find.byKey(DefaultHomePrompt.promptKey), findsOneWidget);
  });

  testWidgets('a phone that cannot answer is not asked at all', (tester) async {
    // A desktop build or `flutter test` has no home app to be, and a dialog
    // about it there is noise.
    final launcher = await _choose(tester, isDefaultHome: null);

    expect(find.byKey(ScreenModeChoiceKeys.homeAppAsk), findsNothing);
    expect(launcher.homeSettingsOpened, 0);
  });

  testWidgets('a phone already set up is not asked either', (tester) async {
    await _choose(tester, isDefaultHome: true);

    expect(find.byKey(ScreenModeChoiceKeys.homeAppAsk), findsNothing);
    expect(find.byKey(DefaultHomePrompt.promptKey), findsNothing);
  });
}
