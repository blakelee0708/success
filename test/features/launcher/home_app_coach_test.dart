import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/presentation/senior_settings_screen.dart';
import 'package:app/features/launcher/presentation/widgets/home_app_coach.dart';

import '../../support/pump_app.dart';

/// Every line of [HomeAppCoach] has to be a whole line.
///
/// The card's own doc comment says so and the two consent cards document
/// what the alternative costs — written long and left to wrap, `지금 쓰시는
/// 기능은` broke after 기능 and left 은 alone on a line of its own. This card
/// shipped with the same fault in three of its lines: `누르고` wrapped to
/// `고`, and the quiet fallback line wrapped to `다.`
///
/// **The count has to be measured, not eyeballed.** `목록에서 「One UI 홈」을
/// 누르고` is seventeen characters and overflows; `전에 쓰시던 화면이
/// 나옵니다.` is fourteen and does not — the brackets and the latin letters
/// are each a different width, so counting characters answers the wrong
/// question. This asks the laid-out paragraph.
///
/// The app's own faces are loaded for the same reason `screenshots_test`
/// loads them: a test environment registers no bundled fonts, so measuring
/// against whatever the harness falls back to measures a phone nobody has.
Future<void> _openSettings(WidgetTester tester, {required bool isHome}) async {
  await pumpApp(
    tester,
    overrides: [
      appLauncherProvider.overrideWithValue(
        FakeAppLauncher(defaultHome: isHome),
      ),
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
  await tester.tap(find.text('바꾸기'));
  await tester.pumpAndSettle();
}

/// Each line of the open coach, with how many pixels past its box the line
/// would run if it were allowed to stay on one.
///
/// Asked as an intrinsic width rather than counted as lines: the answer is
/// the same yes-or-no, and when it is no it says by how much, which is what
/// a line has to be shortened by.
Map<String, double> _overflow(WidgetTester tester) {
  final texts = find.descendant(
    of: find.byType(HomeAppCoach),
    matching: find.byType(Text),
  );
  expect(texts, findsWidgets, reason: 'the coach should be on screen');
  return {
    for (final element in texts.evaluate())
      (element.widget as Text).data!: () {
        final line = element.renderObject! as RenderBox;
        return line.getMaxIntrinsicWidth(double.infinity) - line.size.width;
      }(),
  };
}

void _expectWholeLines(WidgetTester tester) {
  _overflow(tester).forEach((line, over) {
    expect(
      over,
      lessThanOrEqualTo(0.5),
      reason: '`$line` runs ${over.toStringAsFixed(1)}px past its box',
    );
  });
}

void main() {
  setUpAll(() async {
    final korean = FontLoader(AppTheme.fontFamily);
    for (final asset in const [
      'assets/fonts/NotoSansKR-Regular.ttf',
      'assets/fonts/NotoSansKR-Bold.ttf',
    ]) {
      korean.addFont(rootBundle.load(asset));
    }
    await korean.load();
  });

  testWidgets('every line fits, on the way out', (tester) async {
    await _openSettings(tester, isHome: true);
    await tester.tap(find.byKey(SeniorSettingsScreen.stopUsingRow));
    await tester.pumpAndSettle();
    await tester.tap(find.text('네'));
    await tester.pumpAndSettle();

    _expectWholeLines(tester);
  });

  testWidgets('every line fits, on the way in', (tester) async {
    // The other direction says 잘보이네 where this one says One UI 홈, and
    // 잘보이네 is the shorter of the two — so the way in cannot be assumed
    // safe just because the way out is.
    await _openSettings(tester, isHome: false);
    await tester.tap(find.byKey(SeniorSettingsScreen.homeAppRow));
    await tester.pumpAndSettle();

    _expectWholeLines(tester);
  });
}
