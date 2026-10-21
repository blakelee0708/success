import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/data/phone_dialer.dart';
import 'package:app/features/launcher/presentation/sos_screen.dart';

import '../../support/pump_app.dart';

/// 긴급 연락's third button.
///
/// `04_SCREEN_SPEC` asks for 119, 112 and 보호자. The first two worked from
/// the day the screen existed; the third was `onTap: null` with a caption
/// reading 가족을 연결하면 사용할 수 있어요 — and connecting a family did not
/// enable it, because the number lived in a table the parent's phone has no
/// policy to read. The data was collected at pairing and the one phone that
/// needs it in an emergency could not see it.
class FakePhoneDialer implements PhoneDialer {
  final List<String> opened = [];

  @override
  Future<void> openDialer(String number) async => opened.add(number);
}

Future<({InMemorySeniorLinkRepository links, FakePhoneDialer dialer})>
_pumpSos(
  WidgetTester tester, {
  bool linked = true,
  String? guardianPhone = '01012345678',
  String guardianName = '영희',
}) async {
  final links = InMemorySeniorLinkRepository();
  final pairing = InMemoryPairingRepository(links);
  await links.ensureGuardianAccount(
    displayName: guardianName,
    phoneNumber: guardianPhone,
  );
  final started = await pairing.startSeniorPairing(installId: 'senior-phone');
  final profile = await pairing.claimSeniorPairingCode(
    code: started.code,
    displayName: '어머니',
  );

  final dialer = FakePhoneDialer();
  await pumpApp(
    tester,
    overrides: [
      appLauncherProvider.overrideWithValue(FakeAppLauncher(defaultHome: true)),
      phoneDialerProvider.overrideWithValue(dialer),
      seniorLinkRepositoryProvider.overrideWithValue(links),
      pairingRepositoryProvider.overrideWithValue(pairing),
      homeAppsRepositoryProvider.overrideWithValue(InMemoryHomeAppsRepository()),
      seniorLinkStoreProvider.overrideWithValue(
        InMemorySeniorLinkStore(
          SeniorLink(
            installId: 'senior-phone',
            seniorProfileId: linked ? profile.id : null,
          ),
        ),
      ),
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
  await tester.tap(find.text('긴급 구조 요청'));
  await tester.pumpAndSettle();
  return (links: links, dialer: dialer);
}

void main() {
  testWidgets('a connected family makes the 보호자 button work', (tester) async {
    final h = await _pumpSos(tester);

    await tester.tap(find.byKey(SosKeys.guardian));
    await tester.pumpAndSettle();

    expect(h.dialer.opened, ['01012345678']);
  });

  testWidgets('it opens the dialer and never places the call', (tester) async {
    // `06_PERMISSION_AND_POLICY` requires the user press call themselves, and
    // that rule is not only about 119 — it is about every number this app can
    // put in front of a frightened person. `PhoneDialer` is `tel:`, which is
    // ACTION_DIAL on Android and shows the keypad.
    final h = await _pumpSos(tester);

    await tester.tap(find.byKey(SosKeys.guardian));
    await tester.pumpAndSettle();

    expect(h.dialer.opened, hasLength(1));
  });

  testWidgets('the button says who it calls', (tester) async {
    await _pumpSos(tester, guardianName: '영희');

    expect(find.text('보호자'), findsOneWidget);
    expect(find.textContaining('영희'), findsOneWidget);
  });

  testWidgets('with no family connected it stays off and says why', (
    tester,
  ) async {
    final h = await _pumpSos(tester, linked: false);

    await tester.tap(find.byKey(SosKeys.guardian));
    await tester.pumpAndSettle();

    expect(h.dialer.opened, isEmpty);
    expect(find.textContaining('가족을 연결하면'), findsOneWidget);
  });

  testWidgets('a family with no number given stays off, and does not pretend', (
    tester,
  ) async {
    // The number is optional when the guardian connects — the field says
    // 비워 두셔도 됩니다. A tile that looks pressable and dials nothing is
    // worse on this screen than one that plainly cannot be pressed.
    final h = await _pumpSos(tester, guardianPhone: null);

    await tester.tap(find.byKey(SosKeys.guardian));
    await tester.pumpAndSettle();

    expect(h.dialer.opened, isEmpty);
    expect(find.textContaining('전화번호'), findsOneWidget);
  });

  testWidgets('119 and 112 never depend on any of this', (tester) async {
    // They are the two that must work on a phone with no family, no account
    // and no signal.
    final h = await _pumpSos(tester, linked: false);

    await tester.tap(find.text('119'));
    await tester.pumpAndSettle();
    expect(h.dialer.opened, ['119']);
  });
}
