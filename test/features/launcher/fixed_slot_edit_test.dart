import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:app/core/router/routes.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/presentation/widgets/category_picker.dart';

import 'package:app/features/launcher/presentation/app_settings_screen.dart';

import '../../support/pump_app.dart';

/// 가족, 소리 and 인터넷 are the senior's buttons too.
///
/// They were fixed widgets with hard-coded words and colours, which made them
/// the only things on a senior's home screen that their family could not
/// rename or recolour — on the half of the app whose whole job is that the
/// family can.
///
/// They are **not** in either screen's defaults. Seeding them changed the
/// count and the order of `defaultDetailedApps`, which a dozen tests read as
/// the spec's six in the spec's order, and they were right to. A saved list
/// holds one only once somebody has edited it.
Future<void> _openSettings(
  WidgetTester tester, {
  List<LauncherApp>? apps,
}) async {
  await pumpApp(
    tester,
    overrides: [
      appLauncherProvider.overrideWithValue(FakeAppLauncher(defaultHome: true)),
    ],
    prefs: {
      SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
        SeniorSettings(
          screenMode: ScreenMode.easy,
          apps: apps ?? defaultEasyApps,
        ).toJson(),
      ),
    },
  );
  await tester.pumpAndSettle();
  GoRouter.of(
    tester.element(find.byType(Scaffold).first),
  ).push(Routes.appSettings);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('all four are offered for editing', (tester) async {
    await _openSettings(tester);
    await showSlotRows(tester);

    expect(find.text('이 화면의 자리 버튼'), findsOneWidget);
    for (final label in ['가족', '소리', '인터넷', '긴급 구조 요청']) {
      expect(find.text(label), findsWidgets, reason: '$label cannot be edited');
    }
  });

  testWidgets('renaming one sticks, and reaches the home screen', (
    tester,
  ) async {
    await _openSettings(tester);

    // 이 화면의 자리 버튼 sits under the app rows, which are two lines each
    // now, so it starts below the fold. 이름 is the control, not the row:
    // these carry the same three words an app row does, minus 순서.
    await tapInAppSettings(
      tester,
      find.byKey(AppSettingsKeys.rename('internet')),
    );
    await tester.enterText(find.byType(TextField).first, '와이파이');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('와이파이'), findsWidgets);

    await tester.tap(find.text('첫 화면으로 가기'));
    await tester.pumpAndSettle();
    expect(find.text('와이파이'), findsOneWidget);
  });

  testWidgets('none of them is dragged, and all of them can be removed', (
    tester,
  ) async {
    // 순서 is the one control an app row has that these do not: each has a
    // place of its own on both home screens and never joins the grid.
    //
    // 지우기 arrived on 2026-10-28. These four used to be the only buttons on
    // a senior's phone that nobody could take off, which is the opposite of
    // what this half of the app is for - and the case is a real one, a
    // senior who finds the red emergency bar alarming and a child asked to
    // remove it.
    await _openSettings(tester);
    await showSlotRows(tester);

    for (final id in ['family', 'sound', 'internet', 'sos']) {
      expect(find.byKey(AppSettingsKeys.delete(id)), findsOneWidget);
      expect(find.byKey(AppSettingsKeys.dragHandle(id)), findsNothing);
    }
  });

  testWidgets('adding a button offers only the ones that are gone', (
    tester,
  ) async {
    await _openSettings(tester);

    await tapInAppSettings(tester, find.text('버튼 추가하기'));

    // Scoped to the sheet: the four sit on the screen behind it, which is
    // the point of them. A kind already on the screen is hidden, exactly as
    // a second 전화 is.
    final sheet = find.byKey(CategoryPickerKeys.sheet);
    expect(sheet, findsOneWidget);
    for (final label in ['소리', '인터넷', '긴급 구조 요청']) {
      expect(
        find.descendant(of: sheet, matching: find.text(label)),
        findsNothing,
        reason: '$label is already on the screen',
      );
    }
  });
}
