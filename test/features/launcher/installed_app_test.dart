import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/guardian/presentation/widgets/guardian_nav_bar.dart';
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
  await tester.tap(find.text('바꾸기'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('앱 설정하기'));
  await tester.pumpAndSettle();
}

/// The guardian's 홈 화면 tab, with one parent linked.
Future<
  ({
    InMemoryHomeAppsRepository homeApps,
    FakeAppLauncher launcher,
    String profileId,
  })
>
_pumpGuardianTab(WidgetTester tester) async {
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
  // Loaded with apps on purpose: if the guardian's half ever reached for the
  // picker, it would list the guardian's own phone, and these would show up.
  final launcher = FakeAppLauncher(defaultHome: false)..apps = [_gostop];

  await pumpApp(
    tester,
    overrides: [
      guardianAuthRepositoryProvider.overrideWithValue(auth),
      seniorLinkRepositoryProvider.overrideWithValue(links),
      homeAppsRepositoryProvider.overrideWithValue(homeApps),
      appLauncherProvider.overrideWithValue(launcher),
    ],
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(GuardianNavKeys.destination('부모님 화면')));
  await tester.pumpAndSettle();
  return (homeApps: homeApps, launcher: launcher, profileId: profile.id);
}

/// The parent's own home screen, with whatever buttons are on it.
Future<FakeAppLauncher> _pumpSeniorHome(
  WidgetTester tester, {
  required List<LauncherApp> apps,
  List<InstalledApp> installed = const [],
  ScreenMode mode = ScreenMode.easy,
}) async {
  final launcher = FakeAppLauncher(defaultHome: true)..apps = installed;
  await pumpApp(
    tester,
    overrides: [appLauncherProvider.overrideWithValue(launcher)],
    prefs: {
      SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
        SeniorSettings(screenMode: mode, apps: apps).toJson(),
      ),
    },
  );
  await tester.pumpAndSettle();
  return launcher;
}

Future<void> _pickKind(WidgetTester tester) async {
  await tapInAppSettings(tester, find.text('버튼 추가하기'));
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

    testWidgets('the guardian places an empty slot, not an app', (
      tester,
    ) async {
      // 경로 2. The guardian is never shown what is installed on their
      // parent's phone — that list never leaves it — so what they can place
      // is the slot. Their parent presses it once and picks.
      final h = await _pumpGuardianTab(tester);
      await tapInAppSettings(tester, find.text('버튼 추가하기'));
      await tester.tap(
        find.byKey(CategoryPickerKeys.option(AppCategory.installed)),
      );
      await tester.pumpAndSettle();

      final added = h.homeApps.byProfile[h.profileId]!.last;
      expect(added.category, AppCategory.installed);
      expect(added.awaitingChoice, isTrue);
      expect(added.packageName, isNull);
    });

    testWidgets('the guardian is never shown the list itself', (tester) async {
      // The picker reads the phone it is running on. Opening it on the
      // guardian's would list *their* apps, which is both useless and the
      // wrong phone.
      final h = await _pumpGuardianTab(tester);
      await tapInAppSettings(tester, find.text('버튼 추가하기'));
      await tester.tap(
        find.byKey(CategoryPickerKeys.option(AppCategory.installed)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(InstalledAppPickerKeys.sheet), findsNothing);
      expect(h.launcher.appsListed, 0);
    });

    testWidgets('and their row says whose turn it is', (tester) async {
      // A row that did not say so would read as a button that failed to
      // save. Nothing more happens until the parent presses it.
      final h = await _pumpGuardianTab(tester);
      await tapInAppSettings(tester, find.text('버튼 추가하기'));
      await tester.tap(
        find.byKey(CategoryPickerKeys.option(AppCategory.installed)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('부모님이'), findsOneWidget);
      expect(h.homeApps.byProfile[h.profileId]!.last.awaitingChoice, isTrue);
    });
  });

  group('the senior fills it in from their home screen', () {
    testWidgets(
      'pressing the slot opens the list and the button becomes the app',
      (tester) async {
        // Two presses on the screen they are already looking at. The step they
        // could not do — knowing a button should exist and placing it — was
        // done from the other phone.
        await _pumpSeniorHome(
          tester,
          apps: const [
            LauncherApp(
              id: 'slot',
              label: '눌러서 앱 고르기',
              category: AppCategory.installed,
            ),
          ],
          installed: [_gostop],
        );

        await tester.tap(find.text('눌러서 앱 고르기'));
        await tester.pumpAndSettle();
        expect(find.byKey(InstalledAppPickerKeys.sheet), findsOneWidget);

        await tester.tap(
          find.byKey(InstalledAppPickerKeys.option('com.game.gostop')),
        );
        await tester.pumpAndSettle();

        // Named after what it opens, not after whatever the guardian wrote.
        expect(find.text('고스톱'), findsWidgets);
        expect(find.text('눌러서 앱 고르기'), findsNothing);
      },
    );

    testWidgets('an unfilled slot never opens an app', (tester) async {
      // It resolves to nothing rather than to some fallback, so it cannot
      // open a browser at somebody's mother.
      final launcher = await _pumpSeniorHome(
        tester,
        apps: const [
          LauncherApp(
            id: 'slot',
            label: '눌러서 앱 고르기',
            category: AppCategory.installed,
          ),
        ],
      );

      await tester.tap(find.text('눌러서 앱 고르기'));
      await tester.pumpAndSettle();

      expect(launcher.opened, isEmpty);
    });
  });

  testWidgets(
    'the hollow slot on the home screen goes straight to the question',
    (tester) async {
      // It used to land on 앱 설정 — a list of the buttons they already have,
      // with 버튼 추가하기 at the bottom — so adding one from the home screen
      // took four screens, two of which existed to be passed through. The step
      // a senior gives up at is not the choosing; it is getting to the place
      // where they can choose.
      await _pumpSeniorHome(
        tester,
        mode: ScreenMode.detailed,
        apps: const [
          LauncherApp(id: 'phone', label: '전화', category: AppCategory.phone),
        ],
        installed: [_gostop],
      );

      // One button leaves two hollow slots — the grid keeps a whole row
      // rather than one orphan. Either opens the same question.
      await tester.tap(find.text('추가하기').first);
      await tester.pumpAndSettle();

      expect(find.byKey(CategoryPickerKeys.sheet), findsOneWidget);
    },
  );

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
