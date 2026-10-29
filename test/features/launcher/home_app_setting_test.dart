import 'package:flutter/material.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/presentation/senior_settings_screen.dart';

import '../../support/pump_app.dart';

/// 설정 → 첫 화면으로 정하기.
///
/// The offer lives here and nowhere else. Onboarding asks once, right after
/// the screen is chosen; this is the way back for anyone who said 나중에 and
/// for the phones that refuse the chooser. It used to be a card on the home
/// screen, and then briefly a screen of its own that said 첫 화면으로 정하기
/// three times before doing anything.
Future<void> _openSettings(
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
  await tester.tap(find.text(mode == ScreenMode.easy ? '더 보기' : '바꾸기'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a phone that is not the home app is offered the row', (
    tester,
  ) async {
    await _openSettings(tester, FakeAppLauncher(defaultHome: false));

    expect(find.byKey(SeniorSettingsScreen.homeAppRow), findsOneWidget);
  });

  testWidgets('a phone already using this launcher never sees it', (
    tester,
  ) async {
    // Which is almost everyone, almost always: onboarding asked, they said
    // yes, and this row does not exist for them.
    await _openSettings(tester, FakeAppLauncher(defaultHome: true));

    expect(find.byKey(SeniorSettingsScreen.homeAppRow), findsNothing);
  });

  testWidgets('a platform that cannot answer shows nothing either', (
    tester,
  ) async {
    // A desktop build, or `flutter test`, has no home app to be. Reading that
    // silence as "no" would put the row on every screenshot.
    await _openSettings(tester, FakeAppLauncher());

    expect(find.byKey(SeniorSettingsScreen.homeAppRow), findsNothing);
  });

  testWidgets('the row says what the phone is about to show, then opens it', (
    tester,
  ) async {
    // There used to be a whole screen here and it was removed for saying
    // 첫 화면으로 정하기 three times — as its title, as its heading and on
    // its only button — before doing what the row does on tap.
    //
    // This is not that. Android's chooser cannot be changed in any respect,
    // including that it opens with the *other* app already selected, so the
    // only thing left is to say which row is theirs before it appears.
    final launcher = FakeAppLauncher(defaultHome: false);
    await _openSettings(tester, launcher);

    await tester.tap(find.byKey(SeniorSettingsScreen.homeAppRow));
    await tester.pumpAndSettle();

    expect(find.byKey(SeniorSettingsScreen.homeAppCoach), findsOneWidget);
    // Nothing happens to the phone until they have read it.
    expect(launcher.homeSettingsOpened, 0);

    await tester.tap(find.text('알겠어요'));
    await tester.pumpAndSettle();

    expect(launcher.homeSettingsOpened, 1);
    expect(find.byKey(SeniorSettingsScreen.manualKey), findsNothing);
  });

  testWidgets('it earns the step by saying something the row did not', (
    tester,
  ) async {
    // The bar the removed screen failed: a step that repeats the label of
    // the thing you just pressed is a step that exists to be passed through.
    final launcher = FakeAppLauncher(defaultHome: false);
    await _openSettings(tester, launcher);

    await tester.tap(find.byKey(SeniorSettingsScreen.homeAppRow));
    await tester.pumpAndSettle();

    final coach = find.descendant(
      of: find.byKey(SeniorSettingsScreen.homeAppCoach),
      matching: find.byType(Text),
    );
    final said = tester
        .widgetList<Text>(coach)
        .map((t) => t.data ?? '')
        .join(' ');
    expect(said, contains('잘보이네'));
    expect(said, isNot(contains('첫 화면으로 정하기')));
  });

  testWidgets('backing out of it leaves the phone alone', (tester) async {
    final launcher = FakeAppLauncher(defaultHome: false);
    await _openSettings(tester, launcher);

    await tester.tap(find.byKey(SeniorSettingsScreen.homeAppRow));
    await tester.pumpAndSettle();
    await tester.tap(find.text('그만두기'));
    await tester.pumpAndSettle();

    expect(launcher.homeSettingsOpened, 0);
  });

  testWidgets('says what to do when the phone will not open the chooser', (
    tester,
  ) async {
    final launcher = FakeAppLauncher(defaultHome: false)
      ..homeSettingsOpens = false;
    await _openSettings(tester, launcher);

    await tester.tap(find.byKey(SeniorSettingsScreen.homeAppRow));
    await tester.pumpAndSettle();
    await tester.tap(find.text('알겠어요'));
    await tester.pumpAndSettle();

    expect(find.byKey(SeniorSettingsScreen.manualKey), findsOneWidget);
    expect(find.textContaining('기본 앱 선택'), findsOneWidget);
  });

  testWidgets('자세한 화면 reaches it through its 설정 tile', (tester) async {
    await _openSettings(
      tester,
      FakeAppLauncher(defaultHome: false),
      mode: ScreenMode.detailed,
    );

    expect(find.byKey(SeniorSettingsScreen.homeAppRow), findsOneWidget);
  });
}
