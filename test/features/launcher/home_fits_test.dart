import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/remote/subscription_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/features/care/presentation/care_consent_prompt.dart';
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
      appLauncherProvider.overrideWithValue(
        FakeAppLauncher(defaultHome: false),
      ),
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

  _noticeCardTests();

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
            reason:
                '${(tile.widget as AppTile).app.label} is cut off at '
                '${size.name}',
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final (mode, labels) in [
    (ScreenMode.easy, ['전화', '문자', '사진 보기', '영상 보기']),
    (ScreenMode.detailed, ['전화', '카카오톡', '사진찍기', '바꾸기']),
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

/// The two cards that still sit on the senior's home: 안심 케어 동의 and the
/// primary-guardian handover. Both are answered on the parent's own phone, so
/// neither can move anywhere else.
///
/// The 첫 화면 card had this exact problem and was taken off the home for it.
/// These two were never covered, and had it too — at 제일 크게 the tiles came
/// out 24px tall, wide bars with no icon and no label, because every tile is
/// a FittedBox and nothing overflows.
void _noticeCardTests() {
  for (final mode in ScreenMode.values) {
    testWidgets('${mode.name}: the tiles survive the 안심 케어 card', (
      tester,
    ) async {
      final store = InMemorySeniorLinkRepository();
      final pairing = InMemoryPairingRepository(store);
      final subs = InMemorySubscriptionRepository(store);
      await store.ensureGuardianAccount(displayName: '김보호');
      final started = await pairing.startSeniorPairing(
        installId: 'senior-phone',
      );
      final profile = await pairing.claimSeniorPairingCode(
        code: started.code,
        displayName: '어머니',
      );
      await subs.startCare(profile.id);

      await pumpApp(
        tester,
        overrides: [
          appLauncherProvider.overrideWithValue(
            FakeAppLauncher(defaultHome: true),
          ),
          seniorLinkRepositoryProvider.overrideWithValue(store),
          pairingRepositoryProvider.overrideWithValue(pairing),
          subscriptionRepositoryProvider.overrideWithValue(subs),
          homeAppsRepositoryProvider.overrideWithValue(
            InMemoryHomeAppsRepository(),
          ),
          seniorLinkStoreProvider.overrideWithValue(
            InMemorySeniorLinkStore(
              SeniorLink(
                installId: 'senior-phone',
                seniorProfileId: profile.id,
              ),
            ),
          ),
        ],
        prefs: {
          SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
            SeniorSettings(
              screenMode: mode,
              fontSize: FontSize.largest,
              apps: mode == ScreenMode.easy
                  ? defaultEasyApps
                  : defaultDetailedApps,
            ).toJson(),
          ),
        },
      );
      await tester.pumpAndSettle();

      expect(find.byKey(CareConsentPrompt.promptKey), findsOneWidget);
      expect(
        tester.getSize(find.byType(AppTile).first).height,
        greaterThanOrEqualTo(HomeBody.minRow),
        reason: 'the 안심 케어 card has eaten the grid',
      );
    });
  }

  group('the band is not quietly scaled away', () {
    // The third time this wrapper has hidden a fault in this file, and the
    // one that survived a fix: the sizes inside the band were raised and the
    // band looked exactly the same afterwards, because `오후 7:14` was
    // breaking after 오후 and the two-line result was then scaled to 0.79 to
    // fit. The code said 54px and the phone drew 43.
    //
    // Nothing throws when this happens. The only way to catch it is to ask
    // the `FittedBox` what it did.
    for (final (name, mode) in [
      ('easy', ScreenMode.easy),
      ('detailed', ScreenMode.detailed),
    ]) {
      testWidgets('$name: at the default size it is drawn 1:1', (tester) async {
        await _pumpHome(tester, mode, FontSize.normal);

        final box = tester.renderObject<RenderBox>(
          find
              .descendant(
                of: find.byKey(HomeStrip.stripKey),
                matching: find.byType(FittedBox),
              )
              .first,
        );
        final child = (box as dynamic).child as RenderBox;
        expect(
          box.size.height / child.size.height,
          closeTo(1.0, 0.001),
          reason: 'the band is being shrunk, so its type sizes are a fiction',
        );
      });

      testWidgets('$name: the clock is one line, not two', (tester) async {
        // Korean glyphs are about as wide as the type size, so a line has to
        // be counted rather than eyeballed — the date above it learnt this
        // first, in the same card.
        await _pumpHome(tester, mode, FontSize.normal);

        final clock = tester.getSize(find.textContaining(':'));
        expect(
          clock.height,
          lessThan(90),
          reason: 'the clock has wrapped; the band will be scaled to absorb it',
        );
      });
    }
  });
}
