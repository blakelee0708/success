import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/app_category.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/presentation/widgets/app_tile.dart';
import 'package:app/features/launcher/presentation/widgets/category_picker.dart';

import '../../support/pump_app.dart';

/// Adding a button hard-coded `AppCategory.message` on both sides, so a button
/// called 딸 came out blue, wore the 문자 icon, and opened the messaging app
/// when the senior pressed it. The kind decides all three.
void main() {
  testWidgets('the senior picks the kind, and it is the kind they get', (
    tester,
  ) async {
    await pumpApp(
      tester,
      overrides: [
        appLauncherProvider.overrideWithValue(
          FakeAppLauncher(defaultHome: true),
        ),
      ],
      prefs: {
        SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
          const SeniorSettings(
            screenMode: ScreenMode.detailed,
            apps: [
              LauncherApp(
                id: 'phone',
                label: '전화',
                category: AppCategory.phone,
              ),
            ],
          ).toJson(),
        ),
      },
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('앱 설정하기'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('버튼 추가하기'));
    await tester.pumpAndSettle();

    // The kind first, because it decides the icon, the colour and the app
    // that opens — none of which a name can imply.
    expect(find.byKey(CategoryPickerKeys.sheet), findsOneWidget);
    await tester.tap(find.byKey(CategoryPickerKeys.option(AppCategory.kakao)));
    await tester.pumpAndSettle();

    // And the name comes pre-filled with what that kind is usually called.
    await tester.enterText(find.byType(TextField), '딸');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('딸'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    // On the home screen it is a 카카오톡 button, not a blue 문자 one.
    final tile = tester.widget<AppTile>(
      find.ancestor(of: find.text('딸'), matching: find.byType(AppTile)),
    );
    expect(tile.app.category, AppCategory.kakao);
  });

  testWidgets('the guardian picks it too, and the server gets it', (
    tester,
  ) async {
    final auth = InMemoryGuardianAuthRepository()
      ..seedSignedIn(const GuardianSession(userId: 'u1'));
    addTearDown(auth.dispose);
    final links = InMemorySeniorLinkRepository();
    await links.ensureGuardianAccount(displayName: '김보호');
    final profile = await links.createSeniorProfile(displayName: '어머니');
    final homeApps = InMemoryHomeAppsRepository();
    await homeApps.replace(profile.id, const [
      LauncherApp(id: 'phone', label: '전화', category: AppCategory.phone),
    ]);

    await pumpApp(
      tester,
      overrides: [
        guardianAuthRepositoryProvider.overrideWithValue(auth),
        seniorLinkRepositoryProvider.overrideWithValue(links),
        homeAppsRepositoryProvider.overrideWithValue(homeApps),
      ],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('홈 화면'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('버튼 추가하기'));
    await tester.pumpAndSettle();
    expect(find.byKey(CategoryPickerKeys.sheet), findsOneWidget);
    await tester.tap(
      find.byKey(CategoryPickerKeys.option(AppCategory.youtube)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '드라마');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    final written = homeApps.byProfile[profile.id]!.last;
    expect(written.label, '드라마');
    expect(written.category, AppCategory.youtube);
  });
}
