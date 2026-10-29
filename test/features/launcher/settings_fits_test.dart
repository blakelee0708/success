import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';

import '../../support/pump_app.dart';

/// 설정, and the gesture it may not ask for.
///
/// **Scrolling down is one of the two things this app's readers fail at
/// most**, and not because of the finger: they do not know there is anything
/// below, so what is off the screen may as well not exist. 사용법 has had a
/// test forbidding it since the day it was written. 설정 did not, and it was
/// measured at **1410px of content in a 696px window** - more than half of it
/// out of sight, including 문의하기, which is the one row for a senior with
/// nobody to ask.
///
/// Three rows were cut to get here (진동/벨소리 and 인터넷, both already on
/// the home screen, and 자녀가 보는 것, which moved to 가족 연결 설정), the
/// four group titles went, and the row came down from 92px to 84.
Future<void> _openSettings(
  WidgetTester tester, {
  required FontSize size,
  required bool isHomeApp,
}) async {
  await pumpApp(
    tester,
    overrides: [
      appLauncherProvider.overrideWithValue(
        FakeAppLauncher(defaultHome: isHomeApp),
      ),
    ],
    prefs: {
      SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
        SeniorSettings(
          screenMode: ScreenMode.easy,
          fontSize: size,
          apps: defaultEasyApps,
        ).toJson(),
      ),
    },
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('더 보기'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    // The app's own faces. Measuring against whatever the harness falls back
    // to measures a phone nobody has.
    final korean = FontLoader(AppTheme.fontFamily);
    for (final asset in const [
      'assets/fonts/NotoSansKR-Regular.ttf',
      'assets/fonts/NotoSansKR-Bold.ttf',
    ]) {
      korean.addFont(rootBundle.load(asset));
    }
    await korean.load();
  });

  for (final size in FontSize.values) {
    for (final isHomeApp in const [true, false]) {
      // Exactly one of 첫 화면으로 정하기 and 잘보이네 사용하지 않기 is ever
      // drawn, so the count is seven either way - but which one it is decides
      // the longest line, so both are walked.
      testWidgets('설정 does not scroll at ${size.name}'
          '${isHomeApp ? '' : ', with the home-app row'}', (tester) async {
        await _openSettings(tester, size: size, isHomeApp: isHomeApp);

        for (final state in tester.stateList<ScrollableState>(
          find.byType(Scrollable),
        )) {
          expect(
            state.position.maxScrollExtent,
            0,
            reason:
                '설정 scrolls at ${size.name}: '
                '${state.position.maxScrollExtent.round()}px below the fold',
          );
        }
      });
    }
  }
}
