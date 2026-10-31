import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/family/presentation/family_link_screen.dart';
import 'package:app/features/launcher/presentation/widgets/go_home_bar.dart';

import '../../support/pump_app.dart';

/// 가족 연결, on one screen.
///
/// Photographed on a real Galaxy on 2026-10-31: 연결하기 sat under the fold
/// and 자녀가 보는 것 under that, so a senior holding a number their child had
/// read out could type it and find nothing to press. Scrolling down is one of
/// the two gestures this app's readers fail at most - they do not know there
/// is anything below.
Future<void> _open(
  WidgetTester tester, {
  required FontSize size,
  SeniorLink? link,
  InMemorySeniorLinkRepository? store,
  InMemoryPairingRepository? pairing,
}) async {
  final links = store ?? InMemorySeniorLinkRepository();
  await pumpApp(
    tester,
    overrides: [
      seniorLinkRepositoryProvider.overrideWithValue(links),
      pairingRepositoryProvider.overrideWithValue(
        pairing ?? InMemoryPairingRepository(links),
      ),
      homeAppsRepositoryProvider.overrideWithValue(
        InMemoryHomeAppsRepository(),
      ),
      seniorLinkStoreProvider.overrideWithValue(InMemorySeniorLinkStore(link)),
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
  await tester.tap(find.text('가족 연결 설정'));
  await tester.pumpAndSettle();
}

void _expectOneScreen(WidgetTester tester, String where) {
  for (final state in tester.stateList<ScrollableState>(
    find.byType(Scrollable),
  )) {
    // The code field is a Scrollable of its own, sideways; only a vertical
    // one hides anything below.
    if (state.position.axis != Axis.vertical) continue;
    expect(
      state.position.maxScrollExtent,
      0,
      reason:
          '$where scrolls: ${state.position.maxScrollExtent.round()}px '
          'below the fold',
    );
  }
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  final home = tester.getRect(find.byKey(GoHomeBar.buttonKey));
  expect(home.bottom, lessThanOrEqualTo(screen.height), reason: where);
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

  for (final size in FontSize.values) {
    testWidgets('가족 연결 fits one screen at ${size.name}, before and after '
        '번호 보여주기', (tester) async {
      await _open(tester, size: size);

      _expectOneScreen(tester, 'before 번호 보여주기');
      // 연결하기 above 첫 화면으로 가기, not under it.
      final submit = tester.getRect(find.byKey(FamilyLinkKeys.submit));
      final home = tester.getRect(find.byKey(GoHomeBar.buttonKey));
      expect(submit.bottom, lessThanOrEqualTo(home.top));

      await tester.tap(find.byKey(FamilyLinkKeys.showCode));
      // The waiting spinner never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(FamilyLinkKeys.shownCode), findsOneWidget);
      _expectOneScreen(tester, 'with the number showing');
      expect(
        tester.getRect(find.byKey(FamilyLinkKeys.submit)).bottom,
        lessThanOrEqualTo(tester.getRect(find.byKey(GoHomeBar.buttonKey)).top),
      );

    });
  }

  // Shrunk to fit only where it has to be: drawn 1:1 at every size but the
  // largest, and never small enough to stop being read there.
  testWidgets('the top is drawn 1:1 below the largest size', (tester) async {
    for (final size in FontSize.values) {
      await _open(tester, size: size);
      await tester.tap(find.byKey(FamilyLinkKeys.showCode));
      // The waiting spinner never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final fitted = tester.widget<FittedBox>(
        find.descendant(
          of: find.byKey(FamilyLinkKeys.top),
          matching: find.byType(FittedBox),
        ).first,
      );
      expect(fitted.fit, BoxFit.scaleDown);
      final box = tester.renderObject<RenderBox>(find.byKey(FamilyLinkKeys.top));
      final child = tester.renderObject<RenderBox>(
        find.byKey(FamilyLinkKeys.topContent),
      );
      final drawn = box.size.width / child.size.width;
      if (size == FontSize.largest) {
        expect(drawn, greaterThanOrEqualTo(0.75), reason: size.name);
      } else {
        expect(drawn, closeTo(1.0, 0.001), reason: size.name);
      }
    }
  });

  testWidgets('자녀가 보는 것 waits until there is a family to see', (
    tester,
  ) async {
    // Before a child is attached the question has no subject, and the row
    // was the thing pushing 연결하기 off the screen.
    await _open(tester, size: FontSize.normal);
    expect(find.byKey(FamilyLinkKeys.visibility), findsNothing);
  });

  testWidgets('자녀가 보는 것 is there once a child is attached, on one screen', (
    tester,
  ) async {
    final store = InMemorySeniorLinkRepository();
    final pairing = InMemoryPairingRepository(store);
    await store.ensureGuardianAccount(displayName: '영희');
    final started = await pairing.startSeniorPairing(installId: 'senior-phone');
    final profile = await pairing.claimSeniorPairingCode(
      code: started.code,
      displayName: '어머니',
    );
    for (final size in FontSize.values) {
      await _open(
        tester,
        size: size,
        store: store,
        pairing: pairing,
        link: SeniorLink(
          installId: 'senior-phone',
          seniorProfileId: profile.id,
        ),
      );
      expect(find.byKey(FamilyLinkKeys.visibility), findsOneWidget);
      _expectOneScreen(tester, 'connected, at ${size.name}');
    }
  });
}
