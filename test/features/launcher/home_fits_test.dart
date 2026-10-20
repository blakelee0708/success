import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/core/clock.dart';
import 'package:app/features/launcher/presentation/widgets/app_tile.dart';
import 'package:app/features/launcher/presentation/widgets/home_body.dart';
import 'package:app/features/launcher/presentation/widgets/home_strip.dart';

import '../../support/pump_app.dart';

/// Neither home scrolls, so everything on both of them has to fit.
///
/// Raising the text size is the point of this app: a home screen that only
/// holds together at the default size fails at exactly the setting it exists
/// for. And a clipped tile is worse than an overflow stripe — the grid is a
/// scrollable, so it swallows the excess silently and nothing throws.
///
/// 자세한 화면 is the tighter of the two and was not covered here at all until
/// it lost its tab bar: eight cells in the height the easy screen gives four
/// leaves each row 108px, and an icon and a label do not fit that by much.
Future<void> _pumpHome(
  WidgetTester tester,
  ScreenMode mode,
  FontSize size,
) async {
  await pumpApp(
    tester,
    overrides: [
      // Shows the 첫 화면으로 정하기 card, which is the tightest the screen ever
      // gets — and it is shown at whatever size the senior already chose.
      appLauncherProvider.overrideWithValue(FakeAppLauncher(defaultHome: false)),
    ],
    prefs: {
      SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
        SeniorSettings(
          screenMode: mode,
          fontSize: size,
          apps: mode == ScreenMode.easy ? defaultEasyApps : defaultDetailedApps,
        ).toJson(),
      ),
    },
  );
  await tester.pumpAndSettle();
}

void main() {
  _bandHeightTests();

  for (final mode in ScreenMode.values) {
    testWidgets('${mode.name}: the tiles stay usable with the 첫 화면 card up', (
      tester,
    ) async {
      // Nothing overflows when they do not — every tile is a FittedBox — so
      // the failure is silent: at 제일 크게 with the card on screen the rows
      // came out 45px tall and the labels shrank to a few pixels, smaller
      // than the 가족 pill under them. A home whose app names are the
      // smallest writing on it is not a home screen.
      await _pumpHome(tester, mode, FontSize.largest);

      final tile = tester.getSize(find.byType(AppTile).first);
      expect(
        tile.height,
        greaterThanOrEqualTo(HomeBody.minRow),
        reason: 'the 첫 화면 card has eaten the grid',
      );
    });
  }

  for (final mode in ScreenMode.values) {
    for (final size in FontSize.values) {
      testWidgets('${mode.name}: every tile is fully visible at ${size.name}', (
        tester,
      ) async {
        await _pumpHome(tester, mode, size);

        final grid = tester.getRect(find.byType(GridView));
        for (final tile in find.byType(AppTile).evaluate()) {
          final rect = tester.getRect(find.byWidget(tile.widget));
          expect(
            rect.bottom,
            lessThanOrEqualTo(grid.bottom + 0.5),
            reason: '${(tile.widget as AppTile).app.label} is cut off at '
                '${size.name}',
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final (mode, labels) in [
    (ScreenMode.easy, ['전화', '문자', '앨범', '영상 보기']),
    (ScreenMode.detailed, ['전화', '카카오톡', '사진찍기', '설정']),
  ]) {
    testWidgets('${mode.name}: the labels are still readable at 아주 크게', (
      tester,
    ) async {
      // Fitting by shrinking the tiles to nothing would pass the check above.
      await _pumpHome(tester, mode, FontSize.extraLarge);

      for (final label in labels) {
        expect(find.text(label), findsOneWidget);
        expect(tester.getSize(find.text(label)).height, greaterThan(0));
      }
    });
  }
}

/// What the band actually gets, which is not what it was designed for.
///
/// It is drawn at 192px — date, clock, rule and the family line — and wrapped
/// in a `FittedBox`, so handing it less does not overflow or throw: it quietly
/// scales the whole thing down. At 110px the clock comes out at 29px instead
/// of 50, and nothing anywhere says so.
void _bandHeightTests() {
  for (final mode in ScreenMode.values) {
    testWidgets('${mode.name}: the band is drawn at its full height', (
      tester,
    ) async {
      await pumpApp(
        tester,
        overrides: [
          nowProvider.overrideWithValue(() => DateTime(2026, 10, 20, 14, 30)),
          appLauncherProvider.overrideWithValue(
            FakeAppLauncher(defaultHome: true),
          ),
        ],
        prefs: {
          SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
            SeniorSettings(
              screenMode: mode,
              apps: mode == ScreenMode.easy
                  ? defaultEasyApps
                  : defaultDetailedApps,
            ).toJson(),
          ),
        },
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(HomeStrip)).height,
        greaterThanOrEqualTo(HomeBody.preferredStrip),
        reason: 'the band is being scaled down instead of laid out',
      );
      // And the clock is the size the design draws it, not a fraction of it.
      expect(tester.getSize(find.text('오후 2:30')).height, greaterThan(45));
    });
  }
}
