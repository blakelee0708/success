import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/app_category.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/family/presentation/family_link_screen.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/presentation/widgets/app_tile.dart';
import 'package:app/features/launcher/presentation/widgets/home_strip.dart';

import '../../support/pump_app.dart';

/// 자세한 화면 after the 2026-10-20 review: the same band as the easy screen,
/// eight cells instead of six-plus-two, and two buttons where the Material
/// tab bar used to be.
Future<void> _pumpDetailedHome(
  WidgetTester tester, {
  List<LauncherApp> apps = defaultDetailedApps,
}) async {
  await pumpApp(
    tester,
    overrides: [
      appLauncherProvider.overrideWithValue(FakeAppLauncher(defaultHome: true)),
    ],
    prefs: {
      SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
        SeniorSettings(screenMode: ScreenMode.detailed, apps: apps).toJson(),
      ),
    },
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the band, eight cells, and two buttons under them', (
    tester,
  ) async {
    await _pumpDetailedHome(tester);

    expect(find.byKey(HomeStrip.stripKey), findsOneWidget);
    expect(find.byType(AppTile), findsNWidgets(6));
    expect(find.text('카카오톡'), findsOneWidget);
    expect(find.text('사진찍기'), findsOneWidget);
    // Six apps, 설정, and one slot left to fill: eight cells, 2x4.
    expect(find.text('바꾸기'), findsOneWidget);
    expect(find.text('추가하기'), findsOneWidget);
    expect(find.text('긴급 구조 요청'), findsOneWidget);
    expect(find.text('가족 연결'), findsOneWidget);
  });

  testWidgets('the Material tab bar is gone', (tester) async {
    // It was the one part of the screen the text size never reached, and it
    // is what made the two homes look like two different apps.
    await _pumpDetailedHome(tester);

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('첫 화면'), findsNothing);
    expect(find.text('SOS'), findsNothing);
  });

  testWidgets('설정 is still reachable, now as a tile', (tester) async {
    // Dropping the tab bar without this would take 글씨 크기 조절하기 with it,
    // and that is the setting the whole app exists for.
    await _pumpDetailedHome(tester);

    await tester.tap(find.text('바꾸기'));
    await tester.pumpAndSettle();

    expect(find.text('앱 설정하기'), findsOneWidget);
    expect(find.text('글씨 크기 조절하기'), findsOneWidget);
  });

  testWidgets('긴급 구조 요청 opens the SOS screen', (tester) async {
    await _pumpDetailedHome(tester);

    await tester.tap(find.text('긴급 구조 요청'));
    await tester.pumpAndSettle();

    expect(find.text('긴급 연락'), findsOneWidget);
  });

  testWidgets('가족 연결 opens the pairing screen while nobody is attached', (
    tester,
  ) async {
    await _pumpDetailedHome(tester);

    await tester.tap(find.text('가족 연결'));
    await tester.pumpAndSettle();

    // The button is named for the job the senior has at the time, exactly as
    // it is on the easy screen, and it lands on the screen that does it.
    expect(find.byType(FamilyLinkScreen), findsOneWidget);
  });

  testWidgets('removing buttons shortens the grid rather than padding it', (
    tester,
  ) async {
    // Two apps plus 설정 plus one slot is four cells, not eight: a screen
    // two-thirds full of 추가하기 is not an invitation, it is a reproach.
    await _pumpDetailedHome(
      tester,
      apps: const [
        LauncherApp(id: 'phone', label: '전화', category: AppCategory.phone),
        LauncherApp(id: 'kakao', label: '카카오톡', category: AppCategory.kakao),
      ],
    );

    expect(find.byType(AppTile), findsNWidgets(2));
    expect(find.text('추가하기'), findsOneWidget);
  });
}
