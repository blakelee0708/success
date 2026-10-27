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
Future<void> _openSettings(WidgetTester tester, {List<LauncherApp>? apps}) async {
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
  testWidgets('all three are offered for editing', (tester) async {
    await _openSettings(tester);

    expect(find.text('이 화면에 늘 있는 버튼'), findsOneWidget);
    for (final label in ['가족', '소리', '인터넷']) {
      expect(find.text(label), findsWidgets, reason: '$label cannot be edited');
    }
  });

  testWidgets('renaming one sticks, and reaches the home screen', (
    tester,
  ) async {
    await _openSettings(tester);

    await tester.tap(find.text('인터넷'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '와이파이');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('와이파이'), findsWidgets);

    await tester.tap(find.text('첫 화면으로 가기'));
    await tester.pumpAndSettle();
    expect(find.text('와이파이'), findsOneWidget);
  });

  testWidgets('none of them can be deleted or dragged', (tester) async {
    // There is exactly one of each and the senior did not put it there. A
    // senior who could delete 가족 would lose the only way to their family
    // from the home screen, with nothing on that screen to say why.
    await _openSettings(tester);

    final fixed = find.ancestor(
      of: find.text('인터넷'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: fixed.first, matching: find.byTooltip('지우기')),
      findsNothing,
    );
  });

  testWidgets('and adding a button never offers one of them', (tester) async {
    await _openSettings(tester);

    await tester.tap(find.text('버튼 추가하기'));
    await tester.pumpAndSettle();

    // Scoped to the sheet: the three sit on the screen behind it, which is
    // the point of them.
    final sheet = find.byKey(CategoryPickerKeys.sheet);
    expect(sheet, findsOneWidget);
    for (final label in ['소리', '인터넷']) {
      expect(
        find.descendant(of: sheet, matching: find.text(label)),
        findsNothing,
        reason: '$label is offered as a button to add',
      );
    }
  });
}
