import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/care/data/care_capabilities.dart';
import 'package:app/features/care/data/family_visibility.dart';
import 'package:app/features/care/presentation/family_visibility_screen.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/presentation/senior_settings_screen.dart';

import '../../support/pump_app.dart';

/// 자녀가 보는 것.
///
/// The consent card asks once and goes away, so until this screen existed a
/// senior who wanted to know what their children could see had nowhere to
/// look. That is the gap Play's rules about collecting an adult's data are
/// aimed at, and separately a fair question from somebody whose home screen
/// this is.
Future<void> _pumpSettings(WidgetTester tester) async {
  await pumpApp(
    tester,
    overrides: [
      appLauncherProvider.overrideWithValue(FakeAppLauncher(defaultHome: true)),
    ],
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
}

void main() {
  group('the list cannot drift from what 안심 케어 is', () {
    test('every paid capability is named on the screen', () {
      // The gap this screen exists to close, pointing the other way: a
      // capability added to the paid tier and not named here would leave the
      // senior agreeing to something they can never look up again.
      final named = familyVisibility
          .map((v) => v.capabilityKey)
          .whereType<String>()
          .toSet();
      for (final c in careCapabilities.where(
        (c) => c.stage == CareReadiness.live,
      )) {
        expect(named, contains(c.key), reason: '${c.key} is sold and unlisted');
      }
    });

    test('every free capability is named too', () {
      // These go to the family whatever the senior answers, which is exactly
      // why they belong here and not on the consent card.
      final named = familyVisibility
          .map((v) => v.capabilityKey)
          .whereType<String>()
          .toSet();
      for (final c in careCapabilities.where(
        (c) => c.stage == CareReadiness.free,
      )) {
        expect(named, contains(c.key), reason: '${c.key} runs and is unlisted');
      }
    });

    test('nothing unbuilt is promised here', () {
      // Same rule the consent card follows. A capability that is planned and
      // not built must not appear on a screen a senior reads as a statement
      // of what happens today.
      final named = familyVisibility
          .map((v) => v.capabilityKey)
          .whereType<String>()
          .toSet();
      for (final c in plannedCareCapabilities) {
        expect(named, isNot(contains(c.key)), reason: c.key);
      }
    });

    test('each line sits in the section its readiness puts it in', () {
      final byKey = {for (final c in careCapabilities) c.key: c};
      for (final item in familyVisibility) {
        final key = item.capabilityKey;
        if (key == null) continue;
        expect(byKey, contains(key), reason: '$key is not a capability');
        expect(
          byKey[key]!.stage,
          readinessFor(item.sees),
          reason: '$key is in the wrong section',
        );
      }
    });

    test('every key names a capability that exists', () {
      final keys = careCapabilities.map((c) => c.key).toSet();
      for (final item in familyVisibility) {
        if (item.capabilityKey == null) continue;
        expect(keys, contains(item.capabilityKey), reason: item.line);
      }
    });
  });

  group('what the screen says', () {
    test('all three sections have something in them', () {
      // 보지 못합니다 emptying out is the one that would pass unnoticed: the
      // screen would still look complete and would have stopped being the
      // reassurance it exists to be.
      for (final sees in FamilySees.values) {
        expect(familySees(sees), isNotEmpty, reason: '$sees');
      }
    });

    test('location is named as something nobody sees', () {
      // 위치 is out of the product. A senior asking what their children can
      // see is asking this first, whether or not they say so.
      final never = familySees(FamilySees.never).map((v) => v.line).join();
      expect(never, contains('어디 계신지'));
    });

    test('every line fits one line of the list', () {
      // Korean glyphs are about as wide as the type size. At 20px in the
      // width this list runs at, a long line wraps and leaves a syllable
      // alone - the fault the consent cards exist to document.
      for (final item in familyVisibility) {
        expect(item.line.length, lessThanOrEqualTo(22), reason: item.line);
      }
    });
  });

  testWidgets('설정 has a row that opens it', (tester) async {
    await _pumpSettings(tester);

    expect(find.byKey(SeniorSettingsScreen.familyVisibilityRow), findsOneWidget);
    await tester.tap(find.byKey(SeniorSettingsScreen.familyVisibilityRow));
    await tester.pumpAndSettle();

    expect(find.byKey(FamilyVisibilityScreen.listKey), findsOneWidget);
  });

  testWidgets('the screen draws every line and every heading', (tester) async {
    await _pumpSettings(tester);
    await tester.tap(find.byKey(SeniorSettingsScreen.familyVisibilityRow));
    await tester.pumpAndSettle();

    for (final sees in FamilySees.values) {
      expect(find.text(familySeesTitle(sees)), findsOneWidget, reason: '$sees');
    }
    for (final item in familyVisibility) {
      expect(find.text(item.line), findsOneWidget, reason: item.line);
    }
  });

  testWidgets('there is nothing on it to press', (tester) async {
    // It is not a second consent screen. The card asks *may we turn this on*;
    // this answers *what do they see*, and a button here would make a senior
    // think an answer was wanted.
    await _pumpSettings(tester);
    await tester.tap(find.byKey(SeniorSettingsScreen.familyVisibilityRow));
    await tester.pumpAndSettle();

    final inList = find.descendant(
      of: find.byKey(FamilyVisibilityScreen.listKey),
      matching: find.byType(ButtonStyleButton),
    );
    expect(inList, findsNothing);
  });

  testWidgets('첫 화면으로 가기 leaves it, like every other senior screen', (
    tester,
  ) async {
    await _pumpSettings(tester);
    await tester.tap(find.byKey(SeniorSettingsScreen.familyVisibilityRow));
    await tester.pumpAndSettle();

    await tester.tap(find.text('첫 화면으로 가기'));
    await tester.pumpAndSettle();

    expect(find.byKey(FamilyVisibilityScreen.listKey), findsNothing);
  });
}
