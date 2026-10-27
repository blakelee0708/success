import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:app/core/router/routes.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/presentation/widgets/go_home_bar.dart';

import '../../support/pump_app.dart';

/// Lands on the senior's home, then opens [route] the way the app does.
Future<void> _open(WidgetTester tester, String route) async {
  await pumpApp(
    tester,
    prefs: {
      SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
        const SeniorSettings(
          screenMode: ScreenMode.easy,
          apps: defaultEasyApps,
        ).toJson(),
      ),
    },
  );
  await tester.pumpAndSettle();
  GoRouter.of(tester.element(find.byType(Scaffold).first)).push(route);
  await tester.pumpAndSettle();
}

/// Every screen a senior can reach has a way out that is a **word**.
///
/// Usability work on older adults says two things that land on exactly the
/// arrangement these screens had. They navigate by content rather than by
/// menus and buttons, and the assisted buttons around the corners are the
/// ones they are measured not noticing at all; and an icon whose meaning sits
/// far from its function is among the most common things they get stuck on.
/// The `←` in the top-left is both of those at once.
///
/// 앱 설정 worked this out on its own and grew a 첫 화면으로 가기. For a while
/// it was the only screen that had one, which made it the only screen a
/// senior could reliably leave.
void main() {
  for (final (name, route) in [
    ('설정', Routes.seniorSettings),
    ('글씨 크기', Routes.fontSize),
    ('긴급 구조', Routes.sos),
    ('가족 연결', Routes.familyLink),
    ('앱 설정', Routes.appSettings),
  ]) {
    testWidgets('$name can be left by pressing a word', (tester) async {
      await _open(tester, route);

      expect(
        find.byKey(GoHomeBar.buttonKey),
        findsOneWidget,
        reason: '$name has only the corner arrow',
      );
      expect(find.text('첫 화면으로 가기'), findsOneWidget);
    });
  }

  testWidgets('and it goes home rather than back one screen', (tester) async {
    // Several of these have more than one way in, so popping would leave
    // half the visitors somewhere they did not come from. Going home is also
    // what makes the label true.
    await _open(tester, Routes.seniorSettings);

    await tester.tap(find.byKey(GoHomeBar.buttonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(GoHomeBar.buttonKey), findsNothing);
  });
}
