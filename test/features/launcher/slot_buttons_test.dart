import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/app_category.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/presentation/app_settings_screen.dart';
import 'package:app/features/launcher/presentation/widgets/category_picker.dart';
import 'package:app/features/launcher/presentation/widgets/home_utility_row.dart';

import '../../support/pump_app.dart';

/// 가족, 소리, 인터넷 and 긴급 구조 요청 can be taken off the home screen.
///
/// They were the only buttons on a senior's phone that nobody could remove -
/// not the senior, not their family - on the half of the app whose whole job
/// is that the family can arrange that screen. The case is a real one: a
/// senior who finds a large red emergency bar alarming, or who keeps pressing
/// it by accident, asks their child to take it away.
///
/// **What it costs is stated rather than hidden.** With 긴급 구조 요청 gone
/// there is no route to 119 from the home screen, and the only way back is
/// 설정 → 앱 설정하기 → 버튼 추가하기.
Future<void> _openAppSettings(
  WidgetTester tester, {
  SeniorSettings? saved,
}) async {
  await pumpApp(
    tester,
    overrides: [
      appLauncherProvider.overrideWithValue(FakeAppLauncher(defaultHome: true)),
    ],
    prefs: {
      SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
        (saved ??
                const SeniorSettings(
                  screenMode: ScreenMode.easy,
                  apps: defaultEasyApps,
                ))
            .toJson(),
      ),
    },
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('더 보기'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('앱 설정하기'));
  await tester.pumpAndSettle();
}

Future<void> _remove(WidgetTester tester, String id) async {
  await tapInAppSettings(tester, find.byKey(AppSettingsKeys.delete(id)));
  await tester.tap(find.byKey(AppSettingsKeys.deleteConfirm));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a removed slot leaves the home screen', (tester) async {
    await _openAppSettings(tester);
    await _remove(tester, 'sos');

    await tester.tap(find.text('첫 화면으로 가기'));
    await tester.pumpAndSettle();

    expect(find.text('긴급 구조 요청'), findsNothing);
    // Everything else is where it was.
    expect(find.text('가족 연결'), findsOneWidget);
    expect(find.text('전화'), findsOneWidget);
  });

  testWidgets('the 소리·인터넷 row closes up, and then goes', (tester) async {
    await _openAppSettings(tester);
    await _remove(tester, 'sound');

    await tester.tap(find.text('첫 화면으로 가기'));
    await tester.pumpAndSettle();

    // One gone, the other keeps the row at the same small height.
    expect(find.byKey(HomeUtilityRow.soundKey), findsNothing);
    expect(find.byKey(HomeUtilityRow.internetKey), findsOneWidget);
    expect(
      tester.getSize(find.byKey(HomeUtilityRow.internetKey)).height,
      HomeUtilityRow.height,
      reason: 'the survivor must not grow into the space',
    );

    await tester.tap(find.text('더 보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('앱 설정하기'));
    await tester.pumpAndSettle();
    await _remove(tester, 'internet');
    await tester.tap(find.text('첫 화면으로 가기'));
    await tester.pumpAndSettle();

    // Both gone and the row takes no height at all, rather than leaving a
    // 48px band of nothing where they used to be.
    expect(find.byType(HomeUtilityRow), findsNothing);
  });

  testWidgets('a removed slot comes back from 버튼 추가하기', (tester) async {
    // A kind that can be taken off and never offered back is a one-way door.
    await _openAppSettings(tester);
    await _remove(tester, 'sos');

    await tapInAppSettings(tester, find.text('버튼 추가하기'));
    final sheet = find.byKey(CategoryPickerKeys.sheet);
    expect(
      find.descendant(of: sheet, matching: find.text('긴급 구조 요청')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(CategoryPickerKeys.option(AppCategory.sos)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('첫 화면으로 가기'));
    await tester.pumpAndSettle();
    expect(find.text('긴급 구조 요청'), findsOneWidget);
  });

  testWidgets('it comes back with the name the family gave it', (tester) async {
    // Removing one was never meant to throw the family's own word away.
    await _openAppSettings(
      tester,
      saved: const SeniorSettings(
        screenMode: ScreenMode.easy,
        apps: [
          ...defaultEasyApps,
          LauncherApp(id: 'sos', label: '도와주세요', category: AppCategory.sos),
        ],
      ),
    );
    await _remove(tester, 'sos');

    await tapInAppSettings(tester, find.text('버튼 추가하기'));
    await tester.tap(find.byKey(CategoryPickerKeys.option(AppCategory.sos)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('첫 화면으로 가기'));
    await tester.pumpAndSettle();
    expect(find.text('도와주세요'), findsOneWidget);
  });

  testWidgets('a settings file written before these existed keeps all four', (
    tester,
  ) async {
    // Absence has always meant *nobody has edited this yet, use the
    // default*, which is why removal is recorded rather than inferred.
    // Reading absence as removal would have emptied every one of these
    // screens the moment the feature shipped.
    await _openAppSettings(
      tester,
      saved: const SeniorSettings(
        screenMode: ScreenMode.easy,
        apps: defaultEasyApps,
      ),
    );

    await showSlotRows(tester);

    for (final id in ['family', 'sound', 'internet', 'sos']) {
      expect(
        find.byKey(AppSettingsKeys.delete(id)),
        findsOneWidget,
        reason: '$id should still be on the screen',
      );
    }
  });

  testWidgets('the screen cannot be reduced below four buttons', (
    tester,
  ) async {
    // The four slot buttons became removable on 2026-10-28, which for the
    // first time made an **empty home screen** reachable - and a senior
    // looking at a blank phone cannot be told what to press to get their
    // buttons back, which is the whole reason this app exists.
    //
    // The floor is not enforced by hiding 지우기. A button that does nothing
    // reads as the phone being broken; the refusal says the number and
    // offers the way round it, which is the rule every other refusal in this
    // product follows.
    await _openAppSettings(tester);

    // Eight to start with: four tiles and the four slot buttons.
    expect(find.byKey(AppSettingsKeys.count), findsOneWidget);
    for (final id in ['sos', 'internet', 'sound', 'family']) {
      await _remove(tester, id);
    }

    // Four tiles left, and the fifth removal is refused.
    await tapInAppSettings(tester, find.byKey(AppSettingsKeys.delete('phone')));
    expect(find.byKey(AppSettingsKeys.floorNotice), findsOneWidget);
    expect(find.byKey(AppSettingsKeys.deleteConfirm), findsNothing);
    await tester.tap(find.text('알겠어요'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('첫 화면으로 가기'));
    await tester.pumpAndSettle();
    expect(find.text('전화'), findsOneWidget);
  });

  testWidgets('the count is said before the floor is met', (tester) async {
    await _openAppSettings(tester);

    expect(
      tester.widget<Text>(find.byKey(AppSettingsKeys.count)).data,
      contains('8개'),
    );
  });
}
