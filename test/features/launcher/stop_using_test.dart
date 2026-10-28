import 'package:flutter/material.dart';
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
        matching: find.text('버튼과 글씨 크기는 그대로 있어요'),
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
    await tester.tap(find.text('아니요, 그대로 쓸게요'));
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
    await tester.tap(find.text('네'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('알겠어요'));
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
    await tester.tap(find.text('네'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('알겠어요'));
    await tester.pumpAndSettle();

    expect(find.byKey(SeniorSettingsScreen.stopUsingManual), findsOneWidget);
  });

  testWidgets('it promises nothing is lost, because nothing is', (
    tester,
  ) async {
    // The buttons, the text size and the family connection all live on in
    // shared preferences and on the server.
    //
    // It is said **on the row**, before the dialog, because its job is to
    // stop someone refusing out of fear — and a card that only appears after
    // they have already said 네 cannot do that job. It also leaves the
    // dialog as the one sentence they are actually answering.
    await _openSettings(tester, isHome: true);

    expect(find.textContaining('그대로'), findsWidgets);
  });

  testWidgets('neither button reads as the other one', (tester) async {
    // They both used to. `그만두기` is the word in the row that opens this —
    // 잘보이네 사용하지 않기 — so it read as the confirm; `돌아가기` in a
    // dialog reads as *go back*, which is the cancel. Two buttons each
    // saying the opposite of what they did, on the screen that hands a
    // senior their phone back.
    await _openSettings(tester, isHome: true);
    await tester.tap(find.byKey(SeniorSettingsScreen.stopUsingRow));
    await tester.pumpAndSettle();

    // `아니요` cannot be mistaken for a confirm in any reading.
    expect(find.text('아니요, 그대로 쓸게요'), findsOneWidget);
    expect(find.text('그만두기'), findsNothing);
    // And the confirm repeats the question's own verb, after 네.
    expect(find.text('네'), findsOneWidget);
  });

  testWidgets('it names what is kept, rather than calling it 설정', (
    tester,
  ) async {
    // This card exists to say that nothing is lost, and `설정해 두신 것은
    // 그대로 있어요` is the abstraction: a senior does not think of
    // themselves as having configured anything. They think of their buttons,
    // their big letters and their daughter. Left to guess, a reversible
    // choice reads as a final one and nobody presses it.
    await _openSettings(tester, isHome: true);
    await tester.tap(find.byKey(SeniorSettingsScreen.stopUsingRow));
    await tester.pumpAndSettle();

    final said = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' ');
    // **`가족 연결` used to be on this list and was a false pass.** The
    // reassurance is `버튼과 글씨 크기는 그대로 있어요`, written on the row
    // itself; the family connection was being read off the 가족 연결 설정
    // row sitting behind the dialog. Adding 사용법 to 설정 pushed that row
    // below the fold and the test failed, which is the first time it had
    // been asked the question it was written to ask.
    for (final kept in ['버튼', '글씨 크기']) {
      expect(said, contains(kept), reason: '$kept is one of the things kept');
    }
    expect(said, isNot(contains('설정해 두신')));
  });

  testWidgets('the way back uses the same verb as the way out', (tester) async {
    // 바꾸다 both ways. The same word pointing in both directions is what
    // shows this can be undone, without a sentence claiming it.
    await _openSettings(tester, isHome: true);
    await tester.tap(find.byKey(SeniorSettingsScreen.stopUsingRow));
    await tester.pumpAndSettle();

    final said = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' ');
    expect(said, contains('바꿀까요'));
    // One word for a screen, not two. The app already calls its own home
    // 첫 화면, and 원래 화면 does not say which of the two it means.
    expect(said, isNot(contains('원래 화면')));
  });

  testWidgets('the second card says the result *after* the step', (
    tester,
  ) async {
    // Pressing 네 changes nothing at all — Android's own screen is next and
    // a person has to finish it. The card used to open with `홈 버튼을
    // 누르면 그 화면이 나옵니다`, stated as done, and a senior who read it
    // that way closed the system screen and found the phone unchanged.
    await _openSettings(tester, isHome: true);
    await tester.tap(find.byKey(SeniorSettingsScreen.stopUsingRow));
    await tester.pumpAndSettle();
    await tester.tap(find.text('네'));
    await tester.pumpAndSettle();

    final said = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' ');
    // `그러면` is what joins the two, and it has to come before the result.
    expect(said.indexOf('그러면'), greaterThan(said.indexOf('누르세요')));
    expect(said, contains('One UI 홈'));
    // The button the dialog actually carries. This test asked for `변경` for
    // weeks, because the card described a two-dialog Samsung flow where
    // choosing a row raised a second question with 현재 버전 유지 / 변경. On a
    // Galaxy running One UI today it is **one** dialog: both rows and
    // 취소 / 기본 앱으로 설정 together, and no 변경 anywhere on it. A senior
    // following the old card looked for a button that was not there.
    //
    // It was found by looking at a real phone, which is the only way a claim
    // about somebody else's dialog is ever checked — the chooser is
    // `RoleManager`'s, the Kotlin that opens it has never run in this
    // environment, and a test can only confirm the card says what it was
    // written to say.
    expect(said, contains('기본 앱으로 설정'));
    expect(said, isNot(contains('변경')), reason: 'the chooser has no 변경 button');
    expect(said, contains('폰에 따라'));
  });
}
