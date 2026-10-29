import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/remote/home_app_mapping.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/app_category.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/data/phone_dialer.dart';
import 'package:app/features/launcher/presentation/widgets/category_picker.dart';
import 'package:app/features/launcher/presentation/widgets/contact_dialog.dart';

import '../../support/pump_app.dart';

class FakePhoneDialer implements PhoneDialer {
  final List<String> opened = [];

  @override
  Future<void> openDialer(String number) async => opened.add(number);
}

/// 사람 버튼 — a person on the home screen instead of an app.
///
/// Seniors fail at finding *people* far more often than at finding apps:
/// opening 연락처 and scrolling is where they give up. The guardian supplies
/// the number from their own phone, so the parent's launcher never needs a
/// contacts permission to have their daughter one tap away.
const _daughter = LauncherApp(
  id: 'daughter',
  label: '딸 영희',
  category: AppCategory.contact,
  phoneNumber: '01012345678',
);

Future<({FakePhoneDialer dialer, FakeAppLauncher launcher})> _pumpHome(
  WidgetTester tester, {
  required List<LauncherApp> apps,
  ScreenMode mode = ScreenMode.easy,
}) async {
  final dialer = FakePhoneDialer();
  final launcher = FakeAppLauncher(defaultHome: true);
  await pumpApp(
    tester,
    overrides: [
      appLauncherProvider.overrideWithValue(launcher),
      phoneDialerProvider.overrideWithValue(dialer),
    ],
    prefs: {
      SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
        SeniorSettings(screenMode: mode, apps: apps).toJson(),
      ),
    },
  );
  await tester.pumpAndSettle();
  return (dialer: dialer, launcher: launcher);
}

// ---------------------------------------------------------------------------
// Adding one, from either phone.
// ---------------------------------------------------------------------------

Future<void> _openAppSettings(WidgetTester tester) async {
  await pumpApp(
    tester,
    overrides: [
      appLauncherProvider.overrideWithValue(FakeAppLauncher(defaultHome: true)),
    ],
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

void main() {
  testWidgets('a person button dials instead of opening an app', (
    tester,
  ) async {
    final h = await _pumpHome(tester, apps: [_daughter]);

    await tester.tap(find.text('딸 영희'));
    await tester.pumpAndSettle();

    expect(h.dialer.opened, ['01012345678']);
    expect(h.launcher.opened, isEmpty);
  });

  testWidgets('it opens the dialer and never places the call', (tester) async {
    // `06_PERMISSION_AND_POLICY` requires the user press call themselves, and
    // that rule is not only about 119.
    final h = await _pumpHome(tester, apps: [_daughter]);

    await tester.tap(find.text('딸 영희'));
    await tester.pumpAndSettle();

    expect(h.dialer.opened, hasLength(1));
  });

  testWidgets('it works on the detailed screen too', (tester) async {
    final h = await _pumpHome(
      tester,
      apps: [_daughter],
      mode: ScreenMode.detailed,
    );

    await tester.tap(find.text('딸 영희'));
    await tester.pumpAndSettle();

    expect(h.dialer.opened, ['01012345678']);
  });

  testWidgets('app buttons beside it are untouched', (tester) async {
    final h = await _pumpHome(
      tester,
      apps: const [
        LauncherApp(id: 'phone', label: '전화', category: AppCategory.phone),
        _daughter,
      ],
    );

    await tester.tap(find.text('전화'));
    await tester.pumpAndSettle();
    expect(h.launcher.opened, hasLength(1));
    expect(h.dialer.opened, isEmpty);
  });

  testWidgets('a person with no number yet does not dial nothing', (
    tester,
  ) async {
    // Half-finished setup is a real state: the guardian can save a name
    // before a number. Dialing an empty string opens the keypad blank, which
    // looks to a senior like the button is broken rather than unfinished.
    final h = await _pumpHome(
      tester,
      apps: const [
        LauncherApp(id: 'x', label: '아들', category: AppCategory.contact),
      ],
    );

    await tester.tap(find.text('아들'));
    await tester.pumpAndSettle();

    expect(h.dialer.opened, isEmpty);
  });

  group('the number survives the wire', () {
    test('a person round-trips with their number and type', () {
      final rows = homeAppsPayload([_daughter]);

      expect(rows.single['phone_number'], '01012345678');
      // `family_contact` was in the Phase 4 check constraint from the start;
      // nothing had ever written one.
      expect(rows.single['app_type'], 'family_contact');

      final back = launcherAppsFromRows(rows).single;
      expect(back.phoneNumber, '01012345678');
      expect(back.category, AppCategory.contact);
      expect(back.opensDialer, isTrue);
    });

    test('an app button carries no number and is not a contact', () {
      final rows = homeAppsPayload(const [
        LauncherApp(id: 'phone', label: '전화', category: AppCategory.phone),
      ]);

      expect(rows.single['phone_number'], isNull);
      expect(rows.single['app_type'], 'system_app');
      expect(launcherAppsFromRows(rows).single.opensDialer, isFalse);
    });

    test('a blank number reads as no number rather than as an empty one', () {
      final back = launcherAppsFromRows([
        {
          'client_id': 'x',
          'label': '아들',
          'icon_key': 'contact',
          'phone_number': '   ',
          'sort_order': 0,
        },
      ]).single;

      expect(back.phoneNumber, isNull);
      expect(back.opensDialer, isFalse);
    });

    test('recolouring and renaming keep the number', () {
      expect(_daughter.withColor(ButtonColor.rose).phoneNumber, '01012345678');
      expect(_daughter.copyWith(label: '영희').phoneNumber, '01012345678');
    });

    test('it survives the on-disk settings too', () {
      final back = LauncherApp.fromJson(_daughter.toJson())!;
      expect(back.phoneNumber, '01012345678');
    });
  });

  group('adding one', () {
    testWidgets('the senior can add a person and it dials', (tester) async {
      await _openAppSettings(tester);

      await tapInAppSettings(tester, find.text('버튼 추가하기'));
      await tester.tap(
        find.byKey(CategoryPickerKeys.option(AppCategory.contact)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ContactDialogKeys.sheet), findsOneWidget);
      await tester.enterText(find.byKey(ContactDialogKeys.name), '딸 영희');
      await tester.enterText(
        find.byKey(ContactDialogKeys.number),
        '010-1234-5678',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ContactDialogKeys.save));
      await tester.pumpAndSettle();

      expect(find.text('딸 영희'), findsWidgets);
    });

    testWidgets('it will not save half a person', (tester) async {
      // A name with no number is a button that dials nothing, on somebody's
      // mother's home screen.
      await _openAppSettings(tester);

      await tapInAppSettings(tester, find.text('버튼 추가하기'));
      await tester.tap(
        find.byKey(CategoryPickerKeys.option(AppCategory.contact)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(ContactDialogKeys.name), '딸');
      await tester.pumpAndSettle();

      final save = tester.widget<TextButton>(
        find.byKey(ContactDialogKeys.save),
      );
      expect(save.onPressed, isNull);
    });

    testWidgets('it reads the number back before it will save', (tester) async {
      // The parent cannot check this number and will not know a wrong one
      // until a stranger answers.
      await _openAppSettings(tester);

      await tapInAppSettings(tester, find.text('버튼 추가하기'));
      await tester.tap(
        find.byKey(CategoryPickerKeys.option(AppCategory.contact)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(ContactDialogKeys.name), '딸 영희');
      await tester.enterText(
        find.byKey(ContactDialogKeys.number),
        '01012345678',
      );
      await tester.pumpAndSettle();

      // Scoped to the preview: the field itself holds the digits too, and
      // the point is that the *confirmation* groups them for reading.
      expect(
        tester.widget<Text>(find.byKey(ContactDialogKeys.preview)).data,
        contains('010-1234-5678'),
      );
    });
  });

  group('the number is read back in groups', () {
    test(
      'mobile',
      () => expect(formatKoreanNumber('01012345678'), '010-1234-5678'),
    );
    test(
      'seoul landline',
      () => expect(formatKoreanNumber('0212345678'), '02-1234-5678'),
    );
    test(
      'other landline',
      () => expect(formatKoreanNumber('0311234567'), '031-123-4567'),
    );
    test(
      'already punctuated stays put',
      () => expect(formatKoreanNumber('010-1234-5678'), '010-1234-5678'),
    );
  });

  test('a person is lettered in ink, because the amber cannot hold white', () {
    // Same rule as 카카오톡 and the 가족 button, and the same amber.
    expect(
      AppCategory.contact.letteringColor,
      AppCategory.kakao.letteringColor,
    );
    expect(AppCategory.contact.baseColor, isNot(AppCategory.phone.baseColor));
  });
}
