import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/home_app_mapping.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/app_category.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/presentation/widgets/category_picker.dart';
import 'package:app/features/launcher/presentation/widgets/installed_app_picker.dart';

import '../../support/pump_app.dart';

/// 폰에 있는 앱 — a button for an app the senior already has.
///
/// The six categories are *kinds* of app, and the one a senior most wants is
/// usually their 고스톱 or their bank, which is not a kind and never will be.
/// They do not fail at opening apps; they fail at finding them.
final _icon = Uint8List.fromList(List.filled(32, 7));

const _gostop = InstalledApp(packageName: 'com.game.gostop', label: '고스톱');

Future<void> _openAppSettings(
  WidgetTester tester, {
  List<InstalledApp> apps = const [],
}) async {
  final launcher = FakeAppLauncher(defaultHome: true)..apps = apps;
  await pumpApp(
    tester,
    overrides: [appLauncherProvider.overrideWithValue(launcher)],
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
  await tester.tap(find.text('설정'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('앱 설정하기'));
  await tester.pumpAndSettle();
}

Future<void> _pickKind(WidgetTester tester) async {
  await tester.tap(find.text('버튼 추가하기'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(CategoryPickerKeys.option(AppCategory.installed)),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('adding one', () {
    testWidgets('the senior picks an app and it lands on their home', (
      tester,
    ) async {
      await _openAppSettings(tester, apps: [_gostop]);
      await _pickKind(tester);

      expect(find.byKey(InstalledAppPickerKeys.sheet), findsOneWidget);
      await tester.tap(
        find.byKey(InstalledAppPickerKeys.option('com.game.gostop')),
      );
      await tester.pumpAndSettle();

      expect(find.text('고스톱'), findsWidgets);
    });

    testWidgets('it never asks them to type a name', (tester) async {
      // The app arrives carrying the name the phone already shows for it. A
      // keyboard is the step that defeats the reader this is built for.
      await _openAppSettings(tester, apps: [_gostop]);
      await _pickKind(tester);
      await tester.tap(
        find.byKey(InstalledAppPickerKeys.option('com.game.gostop')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a phone that lists nothing says so and does not break', (
      tester,
    ) async {
      // `flutter test` is such a phone, and so is one whose launcher service
      // has wedged. An empty list is an answer, not an error.
      await _openAppSettings(tester);
      await _pickKind(tester);

      expect(find.byKey(InstalledAppPickerKeys.empty), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the guardian is not offered it at all', (tester) async {
      // Picking an app on the parent's phone means reading the list of apps
      // on the parent's phone, and that list never leaves it.
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

      expect(
        find.byKey(CategoryPickerKeys.option(AppCategory.installed)),
        findsNothing,
      );
      expect(
        find.byKey(CategoryPickerKeys.option(AppCategory.contact)),
        findsOneWidget,
      );
    });
  });

  group('opening it', () {
    test('it opens the package the senior chose', () {
      const app = LauncherApp(
        id: 'x',
        label: '고스톱',
        category: AppCategory.installed,
        packageName: 'com.game.gostop',
      );
      expect(launchRequestForApp(app).packageName, 'com.game.gostop');
    });

    test('every other kind still opens by category', () {
      const phone = LauncherApp(
        id: 'p',
        label: '전화',
        category: AppCategory.phone,
      );
      expect(launchRequestForApp(phone), launchRequestFor(AppCategory.phone));
    });
  });

  group('the icon stays with the button', () {
    final app = LauncherApp(
      id: 'x',
      label: 'KB스타뱅킹',
      category: AppCategory.installed,
      packageName: 'com.bank.kb',
      iconBytes: _icon,
    );

    test('it survives a trip through the saved settings', () {
      // Kept on disk rather than fetched when the home screen draws: nothing
      // a senior is looking at may wait on a platform channel, and this is
      // the slowest one in the app.
      final back = LauncherApp.fromJson(app.toJson())!;
      expect(back.iconBytes, _icon);
      expect(back.packageName, 'com.bank.kb');
    });

    test('renaming and recolouring keep it', () {
      expect(app.copyWith(label: '은행').iconBytes, _icon);
      expect(app.withColor(ButtonColor.indigo).iconBytes, _icon);
      expect(app.withColor(ButtonColor.indigo).packageName, 'com.bank.kb');
    });

    test('a stored icon that will not decode is simply no icon', () {
      // One unreadable button must not take the home screen down with it.
      final back = LauncherApp.fromJson({
        ...app.toJson(),
        'iconBytes': 'not base64 at all!!',
      });
      expect(back?.iconBytes, isNull);
      expect(back?.label, 'KB스타뱅킹');
    });
  });

  group('what goes to the server, and what does not', () {
    final app = LauncherApp(
      id: 'x',
      label: 'KB스타뱅킹',
      category: AppCategory.installed,
      packageName: 'com.bank.kb',
      iconBytes: _icon,
    );

    test('the type and the package go up', () {
      final row = homeAppsPayload([app]).single;
      // `installed_app` was in the Phase 4 check constraint from the start.
      expect(row['app_type'], 'installed_app');
      expect(row['package_name'], 'com.bank.kb');
    });

    test('the icon does not', () {
      // Sending it would hand the guardian a picture of what is on their
      // parent's phone, which is the one thing this was scoped not to do.
      final row = homeAppsPayload([app]).single;
      expect(row.values.whereType<Uint8List>(), isEmpty);
      expect(jsonEncode(row), isNot(contains(base64Encode(_icon))));
    });

    test('and it round-trips back without one', () {
      final back = launcherAppsFromRows(homeAppsPayload([app])).single;
      expect(back.packageName, 'com.bank.kb');
      expect(back.category, AppCategory.installed);
      expect(back.iconBytes, isNull);
    });
  });
}
