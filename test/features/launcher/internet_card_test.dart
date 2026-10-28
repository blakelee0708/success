import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/internet_status.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/data/phone_controls.dart';
import 'package:app/features/launcher/presentation/widgets/internet_card.dart';

import '../../support/pump_app.dart';

/// 인터넷, and the two doors behind it.
///
/// **The app cannot switch either one.** `setWifiEnabled` has been a no-op
/// for ordinary apps since Android 10 and mobile data needs carrier
/// privileges, so all this card does is say what is happening and open the
/// one settings screen the senior needs.
///
/// **Wi-Fi and mobile data are two destinations, and that was learnt from a
/// photograph of a real Galaxy.** The card this replaces announced one system
/// sheet carrying both; what arrived was Settings > 연결, where Wi-Fi is a
/// switch at the top and mobile data is not on that screen at all - two taps
/// further in, behind 모바일 네트워크 or 데이터 사용. Nothing here could have
/// caught that: the Kotlin has never been compiled in this environment, let
/// alone run, and a test can only confirm which method the app asked for.
Future<FakePhoneControls> _openCard(
  WidgetTester tester, {
  required InternetStatus status,
}) async {
  final phone = FakePhoneControls()..status = status;
  await pumpApp(
    tester,
    overrides: [
      appLauncherProvider.overrideWithValue(FakeAppLauncher(defaultHome: true)),
      phoneControlsProvider.overrideWithValue(phone),
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
  await tester.tap(find.text('인터넷'));
  await tester.pumpAndSettle();
  return phone;
}

void main() {
  testWidgets('on Wi-Fi it says so and offers only the other door', (
    tester,
  ) async {
    await _openCard(tester, status: InternetStatus.wifi);

    expect(find.byKey(InternetCardKeys.card), findsOneWidget);
    expect(find.textContaining('와이파이로'), findsOneWidget);
    // Nothing to turn on, so the Wi-Fi door would be a button that changes
    // nothing. The other one is there because the reason to switch is money.
    expect(find.byKey(InternetCardKeys.wifi), findsNothing);
    expect(find.byKey(InternetCardKeys.data), findsOneWidget);
    expect(find.textContaining('요금'), findsOneWidget);
  });

  testWidgets('on mobile data it offers Wi-Fi, and says why', (tester) async {
    await _openCard(tester, status: InternetStatus.mobile);

    expect(find.textContaining('데이터로'), findsOneWidget);
    expect(find.byKey(InternetCardKeys.wifi), findsOneWidget);
    expect(find.byKey(InternetCardKeys.data), findsNothing);
    expect(find.textContaining('요금이 안 나가요'), findsOneWidget);
  });

  testWidgets('with nothing connected both doors are offered', (tester) async {
    await _openCard(tester, status: InternetStatus.none);

    expect(find.textContaining('꺼져 있어요'), findsOneWidget);
    expect(find.byKey(InternetCardKeys.wifi), findsOneWidget);
    expect(find.byKey(InternetCardKeys.data), findsOneWidget);
  });

  testWidgets('a phone that will not say claims nothing', (tester) async {
    // `flutter test` is such a phone, and so is a build whose
    // `ACCESS_NETWORK_STATE` went with the plugin that merged it in. Saying
    // 꺼져 있어요 while a page is loading is worse than saying nothing.
    await _openCard(tester, status: InternetStatus.unknown);

    expect(find.textContaining('꺼져 있어요'), findsNothing);
    expect(find.textContaining('잘 되고 있어요'), findsNothing);
    expect(find.byKey(InternetCardKeys.wifi), findsOneWidget);
    expect(find.byKey(InternetCardKeys.data), findsOneWidget);
  });

  testWidgets('each door asks the phone for its own screen', (tester) async {
    // The whole point of the split. One destination for both is what sent a
    // senior to Settings > 연결 with their mobile data two taps out of sight.
    final phone = await _openCard(tester, status: InternetStatus.none);

    await tester.tap(find.byKey(InternetCardKeys.wifi));
    await tester.pumpAndSettle();
    expect(phone.wifiCalls, 1);
    expect(phone.dataCalls, 0);

    await tester.tap(find.text('인터넷'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(InternetCardKeys.data));
    await tester.pumpAndSettle();
    expect(phone.dataCalls, 1);
    expect(phone.wifiCalls, 1);
  });

  testWidgets('a phone that never answers does not strand the senior', (
    tester,
  ) async {
    // A channel that does not answer throws nothing at all, so catching is
    // not enough - the card must not be waiting on it. This trap has now
    // appeared five times in this codebase.
    final phone = FakePhoneControls.silent();
    await pumpApp(
      tester,
      overrides: [
        appLauncherProvider.overrideWithValue(
          FakeAppLauncher(defaultHome: true),
        ),
        phoneControlsProvider.overrideWithValue(phone),
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
    await tester.tap(find.text('인터넷'));
    await tester.pumpAndSettle();

    // Drawn on the unknown answer rather than held on a spinner.
    expect(find.byKey(InternetCardKeys.card), findsOneWidget);
    expect(find.byKey(InternetCardKeys.wifi), findsOneWidget);

    await tester.tap(find.byKey(InternetCardKeys.wifi));
    await tester.pumpAndSettle();
    // Closed on its own answer, not the phone's.
    expect(find.byKey(InternetCardKeys.card), findsNothing);
  });
}
