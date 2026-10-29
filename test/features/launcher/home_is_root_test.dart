import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';

import '../../support/pump_app.dart';

/// A launcher's home screen is the root, and Back on it must do nothing.
///
/// Without that the route pops, and on a real phone the whole home **slid
/// sideways out of view** as the senior watched. On the screen a phone
/// *sits* on that reads as the app falling over, and it leaves them
/// somewhere they did not ask to be — with no way back that they know.
Future<void> _pumpHome(WidgetTester tester, ScreenMode mode) async {
  await pumpApp(
    tester,
    overrides: [
      appLauncherProvider.overrideWithValue(FakeAppLauncher(defaultHome: true)),
    ],
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
}

void main() {
  for (final (name, mode, anchor) in [
    ('정말 쉬운 화면', ScreenMode.easy, '더 보기'),
    ('자세한 화면', ScreenMode.detailed, '바꾸기'),
  ]) {
    testWidgets('$name: Back does not take it away', (tester) async {
      await _pumpHome(tester, mode);
      expect(find.text(anchor), findsOneWidget);

      final popped = await tester.binding.handlePopRoute();

      // False means the app did not consume the pop as "leave this screen" —
      // which is what tells Android to do nothing rather than animate the
      // home away.
      expect(popped, isTrue);
      await tester.pumpAndSettle();
      expect(find.text(anchor), findsOneWidget);
      expect(find.text('전화'), findsOneWidget);
    });

    testWidgets('$name: and a screen opened off it still closes', (
      tester,
    ) async {
      // The root refusing Back must not make the rest of the app a trap.
      await _pumpHome(tester, mode);
      await tester.tap(find.text(anchor));
      await tester.pumpAndSettle();
      expect(find.text('글씨 크기 조절하기'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('글씨 크기 조절하기'), findsNothing);
      expect(find.text('전화'), findsOneWidget);
    });
  }
}
