import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/clock.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/presentation/widgets/home_strip.dart';

import '../../support/pump_app.dart';

final _tuesdayAfternoon = DateTime(2026, 10, 20, 14, 30);

Future<void> _pumpHome(
  WidgetTester tester, {
  List<Object> overrides = const [],
}) async {
  await pumpApp(
    tester,
    overrides: [
      nowProvider.overrideWithValue(() => _tuesdayAfternoon),
      ...overrides,
    ],
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
}

void main() {
  testWidgets('the clock is the first thing on the screen', (tester) async {
    // A senior reaches for their phone to check the time more often than for
    // anything else, and the system clock in the status bar is tiny.
    await _pumpHome(tester);

    expect(find.text('오후 2:30'), findsOneWidget);
    expect(find.text('10월 20일 화요일'), findsOneWidget);
  });

  testWidgets('the band carries the clock and nothing else', (tester) async {
    // It used to hold the family's newest message under a rule, and tapping
    // it opened the conversation. Both moved to the 가족 button, which is
    // where `04_SCREEN_SPEC` had put them before the band took them over.
    //
    // The band kept the job for as long as it was the only thing with room
    // for it. Giving it up is what let 소리 and 인터넷 onto both home screens
    // and took 자세한 화면's tiles out of the squeeze they were in.
    await _pumpHome(tester);

    expect(find.byType(HomeStrip), findsOneWidget);
    expect(find.text('오후 2:30'), findsOneWidget);
    expect(find.text('10월 20일 화요일'), findsOneWidget);
    // Nothing about the family *inside the band*. The word still appears on
    // the home screen, on the button that took the job over, so matching it
    // anywhere would pass and fail on the wrong widget.
    expect(
      find.descendant(
        of: find.byType(HomeStrip),
        matching: find.textContaining('가족'),
      ),
      findsNothing,
    );
  });
}
