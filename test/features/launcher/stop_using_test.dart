import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/presentation/senior_settings_screen.dart';

import '../../support/pump_app.dart';

/// 잘보이네 사용하지 않기 — giving the phone back.
///
/// It sat in 아직 준비 중 with no `onTap`, which was honest and useless: a
/// senior who wants their old home screen back has no way to say so, on the
/// one app that took the home screen over. Android does not let an app
/// unset itself as the home app, so this opens the phone's own chooser —
/// the same screen 첫 화면으로 정하기 opens, approached from the other side.
Future<FakeAppLauncher> _openSettings(
  WidgetTester tester, {
  required bool isHome,
  bool chooserOpens = true,
}) async {
  final launcher = FakeAppLauncher(defaultHome: isHome)
    ..homeSettingsOpens = chooserOpens;
  await pumpApp(
    tester,
    overrides: [appLauncherProvider.overrideWithValue(launcher)],
    prefs: {
      SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
        const SeniorSettings(
          screenMode: ScreenMode.detailed,
          apps: defaultDetailedApps,
        ).toJson(),
      ),
    },
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('설정'));
  await tester.pumpAndSettle();
  return launcher;
}

void main() {
  testWidgets('the row is there once this app is the home screen', (
    tester,
  ) async {
    await _openSettings(tester, isHome: true);

    expect(find.byKey(SeniorSettingsScreen.stopUsingRow), findsOneWidget);
    // It says what it does now. 진동/벨소리 전환 is still unbuilt and still
    // says so, which is why this looks at the row rather than the screen.
    expect(
      find.descendant(
        of: find.byKey(SeniorSettingsScreen.stopUsingRow),
        matching: find.text('곧 쓰실 수 있어요'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(SeniorSettingsScreen.stopUsingRow),
        matching: find.text('원래 쓰시던 화면으로 돌아갑니다'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('and is absent when there is nothing to undo', (tester) async {
    // On a phone this app never became the home screen of, the row offers to
    // undo something that did not happen. 첫 화면으로 정하기 is what belongs
    // there, and it is already the row that shows.
    await _openSettings(tester, isHome: false);

    expect(find.byKey(SeniorSettingsScreen.stopUsingRow), findsNothing);
    expect(find.byKey(SeniorSettingsScreen.homeAppRow), findsOneWidget);
  });

  testWidgets('it asks before changing the phone', (tester) async {
    final launcher = await _openSettings(tester, isHome: true);

    await tester.tap(find.byKey(SeniorSettingsScreen.stopUsingRow));
    await tester.pumpAndSettle();

    expect(find.byKey(SeniorSettingsScreen.stopUsingConfirm), findsOneWidget);
    expect(launcher.homeSettingsOpened, 0);
  });

  testWidgets('backing out leaves the phone exactly as it was', (tester) async {
    final launcher = await _openSettings(tester, isHome: true);

    await tester.tap(find.byKey(SeniorSettingsScreen.stopUsingRow));
    await tester.pumpAndSettle();
    await tester.tap(find.text('그만두기'));
    await tester.pumpAndSettle();

    expect(launcher.homeSettingsOpened, 0);
    expect(find.byKey(SeniorSettingsScreen.stopUsingConfirm), findsNothing);
  });

  testWidgets('agreeing opens the phone\'s own home-screen chooser', (
    tester,
  ) async {
    // Android gives an app no way to stop being the home app. The chooser is
    // the only route, and it is the phone's screen rather than this app's.
    final launcher = await _openSettings(tester, isHome: true);

    await tester.tap(find.byKey(SeniorSettingsScreen.stopUsingRow));
    await tester.pumpAndSettle();
    await tester.tap(find.text('돌아가기'));
    await tester.pumpAndSettle();

    expect(launcher.homeSettingsOpened, 1);
  });

  testWidgets('a phone that refuses the chooser is given the way by hand', (
    tester,
  ) async {
    // Samsung keeps its own launcher set, so some phones open nothing at all.
    // A senior looking at an unchanged screen cannot tell a refused chooser
    // from a broken button.
    await _openSettings(tester, isHome: true, chooserOpens: false);

    await tester.tap(find.byKey(SeniorSettingsScreen.stopUsingRow));
    await tester.pumpAndSettle();
    await tester.tap(find.text('돌아가기'));
    await tester.pumpAndSettle();

    expect(find.byKey(SeniorSettingsScreen.stopUsingManual), findsOneWidget);
  });

  testWidgets('it promises nothing is lost, because nothing is', (
    tester,
  ) async {
    // The buttons, the text size and the family connection all live on in
    // shared preferences and on the server. Leaving a senior to guess that
    // is how a reversible choice gets read as a final one.
    await _openSettings(tester, isHome: true);

    await tester.tap(find.byKey(SeniorSettingsScreen.stopUsingRow));
    await tester.pumpAndSettle();

    expect(find.textContaining('그대로'), findsWidgets);
    expect(find.textContaining('다시'), findsWidgets);
  });
}
